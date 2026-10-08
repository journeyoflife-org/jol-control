#!/usr/bin/env python3
"""state_gate.py — refuse a terraform apply whose STATE cannot justify what it would create.

Why this exists: the proven apply.yml failure was a plan against an EMPTY state that
proposed "120 to add". `prevent_destroy` does not catch it — from an empty state nothing
is destroyed, everything is a create. And a 0-byte state file is worse than a missing one:
Terraform writes state atomically, so a zero-length file means the write was truncated
(killed process, full disk, or a copy that raced the original). Terraform never produces
one on its own.

Exit codes, same convention as scripts/plan_gate.py and push_gate.py:
  0  SAFE         apply target with state that accounts for the config, OR a directory
                 that provably is not an apply target (labelled, never silent)
  1  REFUSED      the state cannot account for the config (zero-byte / empty / absent)
  2  UNEVALUATED  the check itself could not be trusted (unparseable state, bad path)

HONEST-CLASSIFICATION RULE (learned the hard way, see FIX HISTORY below): a directory is
skipped only on POSITIVE evidence that `apply` never runs there —
  * it sits inside a vendored/quarantine tree, or
  * another .tf in the same repo references it through a RELATIVE `module { source }`.
"absence of state, tfvars, .terraform/ and backend block" is NOT such evidence: it is
indistinguishable from "state file lost or truncated", which is the very failure this gate
exists to catch. An earlier revision used that absence to return SAFE and thereby
re-opened S10; the regression fixture caught it, not reading the code.

FIX HISTORY (each was a real defect found by a fixture):
  F-a KeyError on kind=="ok",count==0 -> crash surfaced as UNEVALUATED(2) instead of
      REFUSED(1). Replaced by explicit if/elif.
  F-b "no root evidence => not a root module" => exit 0. Defeated the missing-state
      fixture. Replaced by this file's positive-evidence rule.

Counting is NOT recursive: Terraform compiles only the .tf files in the directory it is
run in, so `declared` counts blocks in this directory, and child modules are counted as
`module` blocks (they still create resources, so they belong in `creatable`).
"""
import argparse, json, os, re, sys, pathlib

RESOURCE_RE = re.compile(r'(?m)^\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*\{')
DATASRC_RE  = re.compile(r'(?m)^\s*data\s+"([^"]+)"\s+"([^"]+)"\s*\{')
MODULE_RE   = re.compile(r'(?m)^\s*module\s+"([^"]+)"\s*\{')
SOURCE_RE   = re.compile(r'(?m)^\s*source\s*=\s*"([^"]+)"')
# `backend "s3" {` may sit mid-line in a one-line block, so no ^ anchor; the requirement
# of `backend` + quoted name + `{` rules out `variable "backend"`, `backend = "s3"`.
# A missed remote backend fails CLOSED (REFUSED, not SAFE) — the wrong direction to err in
# only for accuracy, which is why fixture 11 asserts it.
BACKEND_RE  = re.compile(r'\bbackend\s+"([a-z0-9_]+)"\s*\{')

# directories that are copies of someone else's code, or a frozen stale tree
VENDOR_MARKERS = (".external_modules", "ansible_collections", ".terragrunt-cache",
                  "node_modules", ".terraform", ".module-cache")
QUARANTINE_PREFIXES = (".staging-", ".quarantine-", ".old-")
WALK_PRUNE = (".git", ".venv", "node_modules", ".mypy_cache", ".pytest_cache", "__pycache__")

def tf_files_in(d: pathlib.Path):
    """The .tf files Terraform would compile in directory d (non-recursive, hidden excluded)."""
    try:
        return sorted(p for p in d.iterdir()
                      if p.suffix == ".tf" and p.is_file() and not p.name.startswith("."))
    except OSError:
        return []

def vendored_reason(path: pathlib.Path):
    for part in path.parts:
        if part in VENDOR_MARKERS:
            return f"vendored copy inside {part}/"
        if part.startswith(QUARANTINE_PREFIXES):
            return f"quarantined/stale tree {part}/"
    return None

def repo_root(root: pathlib.Path):
    """Nearest ancestor holding .git — the tree a module reference could come from.

    None when the directory is not inside a repository: then no parent can be proven and
    the gate must fall through to the state checks (a bare directory of .tf files with no
    state is REFUSED, not waved through).
    """
    for anc in root.parents:
        if (anc / ".git").exists():
            return anc
    return None

def module_bodies(txt: str):
    """Bodies of every `module "name" { ... }` block, brace-counted (handles one-liners)."""
    out = []
    for m in re.finditer(r'(?m)^\s*module\s+"[^"]+"\s*\{', txt):
        i, depth, start = m.end() - 1, 0, m.end()
        while i < len(txt):
            c = txt[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    out.append(txt[start:i])
                    break
            i += 1
    return out

def oob_backend(root: pathlib.Path, tree):
    """Is state supplied by `terraform init -backend-config=...` instead of a .tf block?

    jolarca keeps its backends in terraform/backends/<env>.backend.hcl and passes them on
    the CLI (.github/workflows/terraform.yml:134, scripts/check-drift.sh:36). Nothing in
    the environment directory itself names a backend, so a gate that only reads the
    directory concludes "no state" about a root whose state is in a GCS bucket. Matching
    is on the directory name against a <name>.backend.hcl that the tree actually uses.
    """
    if tree is None:
        return None
    names = {f.stem[:-len(".backend")] for f in tree.rglob("*.backend.hcl")}
    if root.name not in names:
        return None
    for cand in list(tree.glob("scripts/*.sh")) + list(tree.glob(".github/workflows/*.yml")) \
            + list(tree.glob("Makefile")):
        try:
            if "-backend-config" in cand.read_text(encoding="utf-8", errors="replace"):
                return str(cand.relative_to(tree))
        except OSError:
            pass
    return None


def declared_backends(root: pathlib.Path):
    """Backend names configured in this dir. `*.tpl` counts: a backend supplied through
    `terraform init -backend-config=backend.tpl` is as remote as one written in .tf."""
    names = set()
    for f in sorted(root.iterdir()):
        if f.is_file() and (f.suffix == ".tf" or f.name.endswith(".tpl")) \
           and not f.name.startswith("."):
            try:
                names |= set(BACKEND_RE.findall(f.read_text(encoding="utf-8", errors="replace")))
            except OSError:
                pass
    return names


def module_index(tree: pathlib.Path):
    """{absolute target dir: [referencing file, ...]} for RELATIVE module sources only."""
    idx = {}
    for dirpath, dirnames, filenames in os.walk(tree):
        dirnames[:] = [d for d in dirnames if d not in WALK_PRUNE]
        for fn in filenames:
            if not fn.endswith(".tf"):
                continue
            p = pathlib.Path(dirpath, fn)
            try:
                txt = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            # only sources inside a module block; a bare `source =` elsewhere is not a
            # module call. Brace-counted, because a module block may close on the same
            # line (`module "vpc" { source = "./modules/vpc" }`) — a regex anchored on a
            # lone `}` silently misses those, which is how fixture 8 failed its first run.
            for body in module_bodies(txt):
                for src in SOURCE_RE.findall(body):
                    if not src.startswith(("./", "../", "/")):
                        continue          # registry / git source, not a local child module
                    try:
                        target = (p.parent / src).resolve()
                    except OSError:
                        continue
                    idx.setdefault(target, []).append(str(p))
    return idx

def dir_counts(d: pathlib.Path):
    res, data, mods = [], [], []
    for p in tf_files_in(d):
        txt = p.read_text(encoding="utf-8", errors="replace")
        res  += [(p.name, r, n) for r, n in RESOURCE_RE.findall(txt)]
        data += [(p.name, r, n) for r, n in DATASRC_RE.findall(txt)]
        mods += [(p.name, m) for m in MODULE_RE.findall(txt)]
    return res, data, mods

def root_evidence(root: pathlib.Path):
    ev = []
    if state_paths(root):
        ev.append(f"{len(state_paths(root))} local state file(s)")
    if (root / ".terraform").is_dir():
        ev.append(".terraform/ (initialised)")
    if any(root.glob("*.tfvars")) or any(root.glob("*.tfvars.json")):
        ev.append("tfvars present")
    if declared_backends(root):
        ev.append("backend declared: " + ", ".join(sorted(declared_backends(root))))
    return ev

def state_resources(path: pathlib.Path):
    """Return (kind, count, detail). kind in ok|zero-byte|empty|garbage|missing."""
    if not path.exists():
        return "missing", None, "no state file"
    if path.stat().st_size == 0:
        return "zero-byte", 0, f"{path} is 0 bytes"
    try:
        doc = json.loads(path.read_text())
    except Exception as e:
        return "garbage", None, f"does not parse: {type(e).__name__}: {e}"
    if not isinstance(doc, dict) or "resources" not in doc:
        return "garbage", None, "not a terraform state document (no 'resources' key)"
    try:
        rs = [r for r in doc["resources"] if r.get("mode") != "data"]
    except (TypeError, AttributeError):
        return "garbage", None, "'resources' is not a list of objects"
    return "ok", len(rs), (f"terraform_version={doc.get('terraform_version')} "
                           f"lineage={str(doc.get('lineage'))[:8]}")

def state_paths(root: pathlib.Path):
    """Every local state file Terraform could use in this directory.

    `terraform workspace` moves a LOCAL backend's state to
    terraform.tfstate.d/<ws>/terraform.tfstate — jolarca's bootstrap root does exactly
    that (bootstrap/main.tf: "the workspace SELECTS the environment"). Reading only
    ./terraform.tfstate reported that live, real state as "no state file at all".
    """
    paths = []
    plain = root / "terraform.tfstate"
    if plain.is_file():
        paths.append(plain)
    wsd = root / "terraform.tfstate.d"
    if wsd.is_dir():
        paths += sorted(wsd.glob("*/terraform.tfstate"))
    return paths

def worst_state(paths, forced=None):
    """Evaluate every state file here; return (kind, count, detail, worst_path, per-file).

    Nothing is dropped: when a directory has several workspaces each file is listed, and
    the verdict is the WORST of them (a good `staging` state does not make a truncated
    `prod` state safe)."""
    order = {"garbage": 3, "zero-byte": 2, "missing": 2, "empty": 1, "ok": 0}
    results = []
    for f in (paths or []):
        kind, count, detail = state_resources(f)
        results.append((f, kind, count, detail))
    if not results:
        return ("missing", None,
                "no terraform.tfstate and no terraform.tfstate.d/*/terraform.tfstate", None, [])
    worst = max(results, key=lambda r: (order[r[1]], -(r[2] or 0)))
    lines = []
    if len(results) > 1:
        for f, kind, count, detail in results:
            lab = "empty" if (kind == "ok" and count == 0) else kind
            lines.append(f"file   : {f.relative_to(root)} -> {lab}, {count} managed")
    return worst[1], worst[2], worst[3], worst[0], lines

def classify(root: pathlib.Path, a_state=None, idx=None):
    """Return (exit_code, lines). Shared by single-dir and --sweep modes."""
    out = []
    res, data, mods = dir_counts(root)
    declared, nmod = len(res), len(mods)
    creatable = declared + nmod
    own = state_paths(root)
    if not tf_files_in(root) and not own:
        return 2, [f"UNEVALUATED: {root} holds no .tf files"]
    reason = vendored_reason(root)
    if reason:
        out.append(f"SAFE — {reason}; not our config, `apply` is never run here")
        return 0, out

    # (1) child module, decided on POSITIVE evidence and checked BEFORE "is this a root":
    #     a module dir that has been `terraform init`-ed still is not a place to apply,
    #     but a module dir holding its OWN state is — that is a duplicate inventory.
    refs = sorted({os.path.relpath(r, repo_root(root) or root) for r in (idx or {}).get(root, [])})
    if refs and not a_state:
        if own:
            out.append(f"parent : module block(s) in {', '.join(refs)} call this directory")
            out.append(f"state  : {len(own)} local state file(s) exist HERE")
            out.append("REFUSED — a child module must not hold state of its own. An apply "
                       "here creates a second copy of everything the parent already manages")
            out.append("(duplicate repos / duplicate buckets), and the parent will then plan")
            out.append("to create them again. Delete the local state and apply from the parent.")
            return 1, out
        out.append(f"parent : module block(s) in {', '.join(refs)} call this directory")
        if (root / ".terraform").is_dir():
            out.append("NOTICE — this module directory was `terraform init`-ed as if it were a "
                       "root (.terraform/ present). No state here yet, but someone standing in "
                       "this directory can run apply; that is how duplicate inventories start.")
        out.append("SAFE — child module: state belongs to the root that calls it")
        return 0, out

    ev = root_evidence(root)
    sp = pathlib.Path(a_state) if a_state else root / "terraform.tfstate"

    # (2) remote backend: the inventory lives in the backend; a local file proves nothing.
    remote = sorted(declared_backends(root) - {"local"})
    oob = None if a_state else oob_backend(root, repo_root(root))
    if oob:
        remote = remote or ["via -backend-config (no block in this directory)"]
    if (remote or oob) and not a_state:
        strays = sorted(x for x in root.iterdir()
                        if x.suffix in (".backup", ".bak") and ".tfstate" in x.name)
        out.append(f"config : {len(tf_files_in(root))} .tf, {declared} resource block(s), "
                   f"{nmod} module block(s)")
        if oob:
            out.append(f"backend: supplied on the CLI — {oob} passes -backend-config")
        out.append(f"backend: {', '.join(remote)} — state lives in the backend, not on disk"
                   + (f"; NOTE: {len(own)} local state file(s) exist here anyway, which is an"
                      " anomaly worth explaining" if own else ""))
        if strays:
            out.append(f"NOTE  : {len(strays)} stale state cop(ies) here "
                       f"({', '.join(s.name for s in strays[:4])}"
                       + ("…" if len(strays) > 4 else "") + ") — with a remote backend these "
                       "are dead weight that a human can mistake for the inventory.")
        out.append("UNEVALUATED — the gate reads local files and cannot see remote state. "
                   "Verify by hand: `terraform state pull` (needs credentials, so it is a "
                   "human step), or pass `--state <pulled copy>` to check it here.")
        return 2, out

    strays = sorted(x for x in root.iterdir()
                    if x.suffix in (".backup", ".bak") and ".tfstate" in x.name)
    kind, count, detail, worst_path, per_file = worst_state([sp] if a_state else own, root)
    label = "empty" if (kind == "ok" and count == 0) else kind
    out.append(f"config : {len(tf_files_in(root))} .tf, {declared} resource block(s), "
               f"{nmod} module block(s), {len(data)} data source(s)")
    if per_file:
        out += per_file
    name = (os.path.relpath(worst_path, root) if worst_path is not None
            else f"{len(own)} state files")
    out.append(f"state  : {name} -> {label} ({detail})"
               + (f", {count} managed resource(s) known" if kind == "ok" and not per_file else ""))
    if ev:
        out.append("role   : apply target (" + ", ".join(ev) + ")")
    if kind == "garbage":
        out.append("UNEVALUATED — the state cannot be read. Do not apply: an unreadable "
                   "state is an unaccounted state. Restore from backup and re-plan.")
        return 2, out
    if creatable == 0:
        out.append("SAFE — no managed resources and no module blocks here; "
                   "nothing this config could create")
        return 0, out
    if strays:
        out.append(f"NOTICE — {len(strays)} stale state cop(ies) sit next to the live state "
                   f"({', '.join(s.name for s in strays[:4])}"
                   + ("…" if len(strays) > 4 else "") + "). Terraform does not read them, but a "
                   "human restoring the wrong one silently reverts inventory; and a "
                   ".bak taken before a state surgery is a second answer to 'what exists'.")
    if kind == "ok" and count > 0:
        if count < creatable * 0.5:
            out.append(f"NOTICE — state knows {count} of {creatable} creatable blocks; "
                       "more than half would be created")
        out.append("SAFE — state accounts for managed resources")
        return 0, out
    if kind == "zero-byte":
        why = "the state file is 0 BYTES. Terraform writes state atomically and never produces this"
    elif kind == "missing":
        why = "there is no state file at all"
    else:
        why = "the state parses but contains ZERO managed resources"
    out.append(f"REFUSED — {why};")
    out.append(f"an apply here plans to CREATE all {creatable} block(s). This is the proven")
    out.append("apply.yml failure mode (empty-state plan, '120 to add'), and prevent_destroy")
    out.append("does not catch it. Restore the real state, or re-import, then re-run.")
    out.append("If this genuinely is a first-time apply, that is a human decision: run")
    out.append("`terraform plan` yourself and read the entire output before applying.")
    return 1, out

def sweep(tree: pathlib.Path):
    """Classify every directory holding .tf under tree. One index, one walk."""
    tree = tree.resolve()
    idx = module_index(tree)
    targets = []
    for dirpath, dirnames, filenames in os.walk(tree):
        dirnames[:] = [d for d in dirnames if d not in WALK_PRUNE]
        if any(f.endswith(".tf") and not f.startswith(".") for f in filenames):
            targets.append(pathlib.Path(dirpath).resolve())
    verdicts, cats = {}, {}
    for d in sorted(targets):
        rc, lines = classify(d, idx=idx)
        tag = {0: "SAFE", 1: "REFUSED", 2: "UNEVALUATED"}[rc]
        verdicts.setdefault(tag, []).append(d)
        # SAFE is not one fact. Counting *why* a directory passed is what keeps a
        # "0 REFUSED" result honest: 800 "child module" passes and 800 "state ok"
        # passes mean very different things about the fleet.
        if tag == "SAFE":
            if any(l.startswith("SAFE — child module") for l in lines):
                why = "child module (state lives in the root)"
            elif any("vendored copy" in l or "quarantined" in l for l in lines):
                why = "vendored / quarantined copy"
            elif any("nothing this config could create" in l for l in lines):
                why = "no creatable blocks"
            else:
                why = "state accounts for resources"
            cats[why] = cats.get(why, 0) + 1
        if tag != "SAFE":
            rel = d.relative_to(tree)
            first = next((l for l in lines if l.startswith(("REFUSED", "UNEVALUATED"))), lines[0])
            print(f"  [{tag}] {rel}: {first.split(';')[0][:150]}")
    print(f"sweep {tree}: {len(targets)} .tf director(ies) -> "
          + ", ".join(f"{k}={len(v)}" for k, v in sorted(verdicts.items())))
    for why, n in sorted(cats.items(), key=lambda kv: -kv[1]):
        print(f"      passed because: {why}: {n}")
    return 1 if verdicts.get("REFUSED") else (2 if verdicts.get("UNEVALUATED") else 0)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", nargs="?", default=".")
    ap.add_argument("--state", help="explicit state file (default: ./terraform.tfstate)")
    ap.add_argument("--sweep", action="store_true",
                    help="classify every .tf directory under DIR instead of DIR alone")
    a = ap.parse_args()
    root = pathlib.Path(a.dir).resolve()
    if not root.is_dir():
        print(f"UNEVALUATED: {root} is not a directory"); return 2
    if a.sweep:
        return sweep(root)
    idx = {}
    tree = repo_root(root)
    if tree is not None:
        idx = module_index(tree)
    rc, lines = classify(root, a.state, idx)
    print(f"### state-gate {root.name}")
    for l in lines:
        print(f"    {l}")
    return rc

if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:
        print(f"UNEVALUATED: internal error: {type(e).__name__}: {e}"); sys.exit(2)
