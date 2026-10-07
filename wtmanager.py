#!/usr/bin/env python3
"""wt-manager — what am I in the middle of, and what is it costing me?

A read-only census of every git worktree on this machine: which are alive,
which are finished, which you forgot, and how much disk each one is holding.

Zero config, zero dependencies, no network unless `gh` is present and useful.
Never fetches. Never deletes anything it cannot justify.
"""
from __future__ import annotations

import argparse
import calendar
import concurrent.futures as futures
import contextlib
import io
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from collections import Counter
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

VERSION = "0.3.1"

# ─────────────────────────────────────────────────────────────────────────────
# Safety classification — the heart of `clean`.
#
# `git` tells us what is ignored. It does NOT tell us what is *disposable*.
# Ignored files are a mix of two very different things:
#
#   regenerable  — a build or install command reproduces it byte for byte
#   precious     — local-only config and secrets that exist NOWHERE else,
#                  not in git, not on a remote. Deleting one is real data loss
#                  and git cannot undo it.
#
# A tool that treats "ignored" as "safe to delete" will eventually eat someone's
# .env file and break a build in an app they never touched. So the default is:
# delete only what we affirmatively recognise as regenerable, report the rest,
# and never guess.
# ─────────────────────────────────────────────────────────────────────────────

REGENERABLE = {
    # JS / TS
    "node_modules", ".next", ".nuxt", ".turbo", ".svelte-kit", ".vite",
    ".parcel-cache", ".angular", ".astro", "bower_components",
    # generic build output
    "dist", "build", "out", "output", ".output", "coverage", ".nyc_output",
    # Rust / Go / Java / Kotlin
    "target", ".gradle", ".kotlin", "vendor",
    # Python
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox",
    ".ipynb_checkpoints", ".venv", "venv",
    # Apple
    "DerivedData", ".build", "Pods", ".swiftpm", "Carthage",
    # Dart / Flutter, PHP
    ".dart_tool", ".flutter-plugins", ".phpunit.cache",
    # misc caches
    ".cache", ".eslintcache", ".sass-cache",
}

# Names that are regenerable only when the directory has the shape of the
# artifact the name suggests. A name recognises a *class* of things that share
# a word, not the thing in front of you: `env/` is a Python virtualenv, and it
# is also where people keep a folder of environment secrets. The virtualenv
# has a `pyvenv.cfg`; the secrets folder does not. Without the shape, unknown.
SHAPED = {
    "env": lambda full: os.path.isfile(os.path.join(full, "pyvenv.cfg")),
}

# Output recognised by what is inside it, whatever the folder is called. A
# generator's own fingerprint is stronger evidence than any name: measured, a
# docs site kept `cargo doc` output in `site/public/api/` — 266MB that no name
# rule could safely claim, since `public` is source in most web projects.
SIGNATURES = {
    "rustdoc": ("static.files", "crates.js"),
}


def signed(full: str) -> bool:
    """Whether `full`, or the lone folder it wraps, carries a known generator's
    fingerprint. Wrappers count only when they hold nothing else: git reports
    `site/public/` whole once its only tracked file is gone, and the rustdoc
    output is the one folder inside it."""
    for _ in range(4):
        if not os.path.isdir(full) or os.path.islink(full):
            return False
        if any(all(os.path.exists(os.path.join(full, m)) for m in marks)
               for marks in SIGNATURES.values()):
            return True
        try:
            inside = [e for e in os.scandir(full) if e.name != ".DS_Store"]
        except OSError:
            return False
        if len(inside) != 1 or not inside[0].is_dir(follow_symlinks=False):
            return False
        full = inside[0].path
    return False


# Deliberately absent from both lists, so they fall to "unknown" and are kept:
#   .bundle    - `bundle config --local` writes private gem-server credentials there
#   .terraform - holds the current workspace name; deleting it silently moves
#                the next `plan` onto `default`
#   tmp        - people put things there on purpose

# Never removed automatically, even though git ignores them.
PRECIOUS_PATTERNS = [
    r"^\.env($|\..*)", r".*\.env$",
    r"^\.envrc$",
    r".*\.(pem|key|p12|pfx|jks|keystore|mobileprovision|cer|crt)$",
    r"^\.netrc$", r"^\.npmrc$", r"^\.yarnrc(\.yml)?$", r"^\.pypirc$",
    r"(^|.*[-_.])secret(s)?($|[-_.].*)", r"(^|.*[-_.])credential(s)?($|[-_.].*)",
    r"^local\.properties$",
    r"^service[-_]?account.*\.json$", r".*-key\.json$",
    r"^\.gradle\.properties$", r"^gradle\.properties$",
    r"^\.aws$", r"^\.ssh$", r"^\.gnupg$",
    r"^google-services\.json$", r"^GoogleService-Info\.plist$",
]
_PRECIOUS_RE = [re.compile(p, re.I) for p in PRECIOUS_PATTERNS]

# Collected non-fatal problems, surfaced in the footer. Silently degrading to
# "no PR data" would make every open PR look like un-offered local work, which is
# the exact inversion this tool exists to prevent.
NOTICES: List[Tuple[str, str, str]] = []

SAFE = "regenerable"
PRECIOUS = "precious"
UNKNOWN = "unknown"


def classify_ignored(name: str, root: Optional[str] = None) -> str:
    """Classify one ignored path. Conservative by construction.

    By basename alone when `root` is not given. With it, two things are also
    checked on disk: a shaped name must have its shape, and a regenerable
    directory must not hold a precious file anywhere beneath it. That second check
    exists because `git status --ignored=traditional` collapses a wholly-ignored
    directory to one line, so `dist/.env` is never listed — the only place it
    can be seen is from inside `dist/`, and a directory that hides a precious
    file is not one we recognise.
    """
    base = name.rstrip("/").split("/")[-1]
    for rx in _PRECIOUS_RE:
        if rx.match(base):
            return PRECIOUS
    full = os.path.join(root, name) if root else None
    if base in SHAPED:
        if full and SHAPED[base](full) and not precious_inside(full):
            return SAFE
        return UNKNOWN
    if base in REGENERABLE:
        if full and precious_inside(full):
            return UNKNOWN
        return SAFE
    if full and signed(full) and not precious_inside(full):
        return SAFE
    return UNKNOWN


def recognized_output(name: str, root: str) -> bool:
    """Whether the folder is known build output, before protected-file checks."""
    base = name.rstrip("/").split("/")[-1]
    full = os.path.join(root, name)
    return (base in REGENERABLE
            or (base in SHAPED and SHAPED[base](full)) or signed(full))


def record_ignored(w: Worktree, entry: str) -> str:
    kind = classify_ignored(entry, w.path)
    if kind == PRECIOUS:
        w.precious_hits.append(entry)
    elif kind == UNKNOWN:
        hidden = hidden_precious(w.path, entry)
        w.precious_hits.extend(hidden)
        # A known output folder with secrets needs those secrets archived,
        # not a backup of gigabytes that a build will recreate. Clean still
        # leaves the whole folder alone; only reap archives then removes it.
        if not hidden or not recognized_output(entry, w.path):
            w.unknown_paths.append(entry)
    return kind


def precious_paths(full: str) -> List[str]:
    """All protected descendants, without following directory symlinks.

    An unreadable subtree is uncertain, not safe. Callers must preserve it.
    Protected directories are kept whole rather than inspecting their secrets.
    """
    if not os.path.isdir(full) or os.path.islink(full):
        return []
    hits = []
    def unreadable(error):
        raise error
    for parent, dirs, files in os.walk(full, followlinks=False, onerror=unreadable):
        for name in dirs + files:
            if any(rx.match(name) for rx in _PRECIOUS_RE):
                hits.append(os.path.relpath(os.path.join(parent, name), full))
                if name in dirs:
                    dirs.remove(name)
    return sorted(hits)


def precious_inside(full: str) -> Optional[str]:
    """A protected descendant, or an uncertainty marker when inspection fails."""
    try:
        return next(iter(precious_paths(full)), None)
    except OSError:
        return "(unreadable subtree)"


def hidden_precious(root: str, entry: str) -> List[str]:
    try:
        return [os.path.join(entry.rstrip("/"), p)
                for p in precious_paths(os.path.join(root, entry))]
    except OSError as e:
        warn(f"could not inspect {os.path.join(root, entry)}: {e}")
        # Do not invent a file to copy. The unknown folder is kept whole;
        # an explicit discard must not bypass incomplete protection checks.
        raise OSError(f"cannot safely classify ignored folder {entry}") from e


# ─────────────────────────────────────────────────────────────────────────────
# Config — optional. Everything works with none of it.
# ─────────────────────────────────────────────────────────────────────────────

DEFAULT_CONFIG = {
    "roots": [],            # dirs to scan for repos; empty => current repo only
    "base": {},             # repo name -> base branch override (resolution rule 1)
    "stale_days": 14,
    "min_base_votes": 5,    # rule-3 confidence floor; an ABSOLUTE count, not a share
    "regenerable": [],      # extra dir names treated as safe to delete
    "precious": [],         # extra regexes never deleted
}


def config_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
    return Path(base) / "wt-manager" / "config.json"


def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    p = config_path()
    if p.exists():
        try:
            cfg.update(json.loads(p.read_text()))
        except Exception as e:
            warn(f"ignoring unreadable config {p}: {e}")
    REGENERABLE.update(cfg.get("regenerable") or [])
    for pat in cfg.get("precious") or []:
        try:
            _PRECIOUS_RE.append(re.compile(pat, re.I))
        except re.error as e:
            warn(f"bad 'precious' regex {pat!r}: {e}")
    return cfg


def cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")
    d = Path(base) / "wt-manager"
    d.mkdir(parents=True, exist_ok=True)
    return d


# A cache file not touched in this long belongs to a repo no longer scanned -
# every live one is rewritten within its TTL, and the longest TTL is an hour.
_CACHE_MAX_AGE = 7 * 86400


def sweep_cache(now: Optional[float] = None) -> int:
    """Drop cache files nothing has touched in a week. Returns how many.

    A tool that reclaims other people's disk has to tidy its own. pr-*.json
    and unseen-* are written per repo and were never removed - not when the
    repo left the roots, not when it was deleted. Their names are hashes of
    the origin URL, so the only honest question is "has anything touched this
    lately", and a week is past every TTL by a wide margin. sizes.json and
    state.json prune their own entries on load instead.
    """
    now = now or time.time()
    gone = 0
    try:
        for f in cache_dir().iterdir():
            if not (f.name.startswith(("pr-", "unseen-", "repos-", "seenby-"))):
                continue
            try:
                if now - f.stat().st_mtime > _CACHE_MAX_AGE:
                    f.unlink()
                    gone += 1
            except OSError:
                pass
    except OSError:
        pass
    return gone


def clear_cache() -> Tuple[int, int]:
    """Remove every cache file. Returns (files, bytes). Config is not touched."""
    files = size = 0
    try:
        for f in cache_dir().iterdir():
            if f.is_file():
                try:
                    size += f.stat().st_size
                    f.unlink()
                    files += 1
                except OSError:
                    pass
    except OSError:
        pass
    return files, size


# ─────────────────────────────────────────────────────────────────────────────
# Shell
# ─────────────────────────────────────────────────────────────────────────────

def sh(args: Sequence[str], cwd: Optional[str] = None, timeout: int = 30,
       env: Optional[Dict[str, str]] = None) -> Tuple[int, str, str]:
    """`env` is an overlay on this process's environment, not a replacement:
    handing a subprocess a bare dict strips PATH, HOME and everything `gh`
    needs to find its own config."""
    try:
        p = subprocess.run(
            list(args), cwd=cwd, timeout=timeout,
            env=None if env is None else {**os.environ, **env},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True, errors="replace",
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"
    except FileNotFoundError:
        return 127, "", "not found"


def git(args: Sequence[str], cwd: Optional[str] = None, gitdir: Optional[str] = None,
        timeout: int = 30) -> Tuple[int, str, str]:
    pre = ["git"]
    if gitdir:
        pre += ["--git-dir", gitdir]
    return sh(pre + list(args), cwd=cwd, timeout=timeout)


def have(tool: str) -> bool:
    return shutil.which(tool) is not None


def warn(msg: str) -> None:
    print(f"{C.dim}wt-manager: {msg}{C.off}", file=sys.stderr)


# ─────────────────────────────────────────────────────────────────────────────
# Colour — honoured only when it helps
# ─────────────────────────────────────────────────────────────────────────────

class C:
    enabled = False
    off = red = green = yellow = blue = magenta = cyan = dim = bold = ""

    @classmethod
    def setup(cls, force: Optional[bool] = None) -> None:
        on = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
        if force is not None:
            on = force
        cls.enabled = on
        if on:
            cls.off, cls.bold, cls.dim = "\033[0m", "\033[1m", "\033[2m"
            cls.red, cls.green, cls.yellow = "\033[31m", "\033[32m", "\033[33m"
            cls.blue, cls.magenta, cls.cyan = "\033[34m", "\033[35m", "\033[36m"
        else:
            cls.off = cls.bold = cls.dim = ""
            cls.red = cls.green = cls.yellow = ""
            cls.blue = cls.magenta = cls.cyan = ""


# ─────────────────────────────────────────────────────────────────────────────
# Model
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class PR:
    number: int
    state: str              # OPEN | MERGED | CLOSED
    draft: bool
    checks: str             # passing | failing | pending | none
    review: str             # APPROVED | CHANGES_REQUESTED | REVIEW_REQUIRED | none
    url: str = ""           # so a client can open it without reconstructing it
    merged_at: str = ""     # ISO8601. "merged" is a claim; this is the evidence
    head_oid: str = ""      # the commit the forge merged. Names are reused; this is not
    author: str = ""
    base: str = ""          # the branch this PR targets: this branch's own base
    failing: List[str] = field(default_factory=list)   # failing check names, raw
    distinct_failing: List[str] = field(default_factory=list)  # minus repo baseline
    endemic: List[str] = field(default_factory=list)   # failing repo-wide, not yours


@dataclass
class Worktree:
    repo: str
    path: str
    branch: Optional[str]
    primary: bool
    base: str
    base_source: str
    repo_id: str = ""       # common Git directory, not the display name
    ahead: int = 0
    behind: int = 0
    staged: int = 0
    unstaged: int = 0
    untracked: int = 0
    # Of the staged and unstaged changes, the ones that delete a tracked file.
    # Git still holds every one of them, so removing the worktree loses
    # nothing: a checkout with 724 files gone from disk read "724 uncommitted"
    # and sat at the top of the risk card with nothing in it to lose.
    deleted: int = 0
    last_commit: int = 0
    age_days: int = 0
    unpushed: int = 0
    # Of those, the ones you wrote. A review checkout of a colleague's PR
    # holds their commits, often an old version of a PR that has since moved
    # on the forge; counting them as your work at risk put two review
    # checkouts at the top of "at risk" with 23 commits nobody here wrote.
    # `unpushed` stays the whole count: `reap` refuses on it either way.
    unpushed_mine: int = 0
    # The subjects of the commits that exist only here, newest first, capped.
    # The count alone tells you something is at stake and not what: to find
    # out you had to open a terminal, which is the tool handing back the
    # question it just raised.
    solo_log: List[str] = field(default_factory=list)
    is_base: bool = False
    landed: bool = False    # HEAD is inside the commit a merged PR landed; see landed()
    pr: Optional[PR] = None
    status: str = "?"
    size_kb: int = -1
    reclaim_kb: int = -1
    precious_hits: List[str] = field(default_factory=list)
    reclaim_paths: List[str] = field(default_factory=list)
    unknown_paths: List[str] = field(default_factory=list)
    ignored_scanned: bool = False
    unknown_kb: int = -1
    locked: str = ""
    has_submodules: bool = False

    @property
    def dirty(self) -> int:
        return self.staged + self.unstaged + self.untracked

    @property
    def clean(self) -> bool:
        return self.dirty == 0

    @property
    def would_lose(self) -> int:
        """Uncommitted changes that exist nowhere else: everything but deletions."""
        return self.dirty - self.deleted

    @property
    def name(self) -> str:
        return self.branch or "(detached)"


# ─────────────────────────────────────────────────────────────────────────────
# Discovery
#
# A repo is identified by its git *common dir*, never by a directory path:
# the same repo is reachable from its main checkout and from every worktree,
# and on a case-insensitive filesystem (macOS by default) the same repo is
# reachable under several spellings of the same path. Canonicalising here is
# what stops one worktree being counted twice.
# ─────────────────────────────────────────────────────────────────────────────

def common_dir(path: str) -> Optional[str]:
    rc, out, _ = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=path)
    if rc != 0 or not out:
        return None
    try:
        return str(Path(out).resolve())
    except OSError:
        return out


_REPO_SCAN_TTL = 3600     # repos are created and deleted in hours, not seconds


def find_repos(roots: Sequence[str], max_depth: int = 3) -> List[str]:
    """Every distinct repo under the given roots, as canonical common dirs.

    Cached: walking two roots costs about two seconds and returns the same
    answer all day. Paid on every invocation it is a quarter of the runtime,
    and it is the part of the work least likely to have changed.
    """
    key = hashlib.sha1("|".join(sorted(roots)).encode()).hexdigest()[:16]
    ck = cache_dir() / f"repos-{key}.json"
    if _REPO_SCAN_TTL > 0 and ck.exists() and (time.time() - ck.stat().st_mtime) < _REPO_SCAN_TTL:
        try:
            cached = json.loads(ck.read_text())
            # A repo that has since been deleted would otherwise be reported as
            # an empty one rather than as gone.
            live = [c for c in cached if os.path.isdir(c)]
            if len(live) == len(cached):
                return live
        except Exception:
            pass
    seen: Dict[str, str] = {}
    for root in roots:
        r = Path(os.path.expanduser(root))
        if not r.is_dir():
            continue
        stack = [(r, 0)]
        while stack:
            d, depth = stack.pop()
            try:
                entries = list(d.iterdir())
            except (PermissionError, OSError):
                continue
            if any(e.name == ".git" for e in entries):
                cd = common_dir(str(d))
                if cd:
                    seen.setdefault(cd.lower(), cd)
                # a repo's own subdirs can still hold nested repos, so keep walking
            if depth < max_depth:
                for e in entries:
                    if e.is_dir() and not e.is_symlink() and e.name not in (
                        ".git", "node_modules", "target", "DerivedData", ".build",
                    ):
                        stack.append((e, depth + 1))
    found = sorted(seen.values())
    try:
        ck.write_text(json.dumps(found))
        os.chmod(ck, 0o600)
    except OSError:
        pass
    return found


class NotConfigured(Exception):
    """No roots, and not run from inside a repo. A state, not a failure."""


# The folders people actually keep code in, in the order worth trying. Not a
# preference — a list of conventions, and the machine settles it by having
# repos in one of them or not.
HOME_DIRS = ("dev", "Developer", "Projects", "projects", "src", "code",
             "work", "repos", "git", "Documents/GitHub", "go/src")


def discover_roots(max_roots: int = 4) -> List[Tuple[str, int]]:
    """Where this machine keeps its repositories, with how many are in each.

    The tool has exactly one setting that matters, and it can answer it
    itself: measured here, the conventional folders resolve in under a second
    and a full sweep of `$HOME` at depth three takes about two. A question a
    program can answer in a second is not a question worth a wizard.

    Conventional names first. Only if none of them holds a repo does it look
    at everything under `$HOME`, and then it reports the *folders* the repos
    are in rather than `$HOME` itself — pointing the tool at a home directory
    would make every later scan walk it.
    """
    home = Path.home()
    named = []
    for d in HOME_DIRS:
        root = home / d
        if not root.is_dir():
            continue
        n = len(find_repos([str(root)]))
        if n:
            named.append((str(root), n))
    if named:
        return sorted(named, key=lambda t: -t[1])[:max_roots]

    groups: Dict[str, int] = {}
    # Against the resolved home. `find_repos` reports git's own common dir,
    # which is realpath'd, and on macOS `/var` is a symlink to `/private/var`
    # — so a home under either spelling fails `relative_to` and every repo is
    # silently dropped. Two spellings of one directory is the normal case, not
    # the odd one.
    real = Path(os.path.realpath(home))
    for gitdir in find_repos([str(home)]):
        try:
            rel = Path(os.path.realpath(gitdir)).relative_to(real)
        except ValueError:
            continue
        # The folder the repo sits in, not the repo and not the home dir.
        top = str(real / rel.parts[0]) if len(rel.parts) > 1 else str(real)
        groups[top] = groups.get(top, 0) + 1
    return sorted(groups.items(), key=lambda t: -t[1])[:max_roots]


def write_roots(roots: Sequence[str]) -> Path:
    """Set `roots`, keeping whatever else is already in the file."""
    p = config_path()
    cfg = dict(DEFAULT_CONFIG)
    if p.exists():
        try:
            cfg.update(json.loads(p.read_text()))
        except (OSError, ValueError):
            pass            # an unreadable config is replaced, not inherited
    cfg["roots"] = list(dict.fromkeys(os.path.realpath(os.path.expanduser(str(r)))
                                     for r in roots))
    p.parent.mkdir(parents=True, exist_ok=True)
    # A crash between truncating and writing the config must not erase the
    # user's watched folders. Keep the temporary file private as paths can be
    # sensitive, then replace the old config in one filesystem operation.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=p.parent,
                                         prefix=".config-", delete=False) as stream:
            temporary = Path(stream.name)
            os.chmod(temporary, 0o600)
            stream.write(json.dumps(cfg, indent=2) + "\n")
        os.replace(temporary, p)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return p


def parse_worktree_list(porcelain: str) -> List[Tuple[str, Optional[str]]]:
    out: List[Tuple[str, Optional[str]]] = []
    path: Optional[str] = None
    branch: Optional[str] = None
    detached = False
    for line in porcelain.splitlines() + [""]:
        if line.startswith("worktree "):
            path, branch, detached = line[9:], None, False
        elif line.startswith("branch "):
            branch = line[7:].replace("refs/heads/", "", 1)
        elif line.strip() == "detached":
            detached = True
        elif line == "" and path:
            out.append((path, None if detached else branch))
            path, branch, detached = None, None, False
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Base resolution
#
# Getting this wrong makes ahead/behind wrong, which makes status wrong, which
# makes the whole tool a lying instrument. So: four rules, first that succeeds,
# and whichever wins is DISPLAYED. A base you can see is a base you can correct.
# ─────────────────────────────────────────────────────────────────────────────

_base_cache: Dict[Tuple[str, str], Tuple[str, str]] = {}


def resolve_base(gitdir: str, repo: str, branch: Optional[str], cfg: dict,
                 pr_bases: Optional[Counter], pr_base: str = "") -> Tuple[str, str]:
    """Memoised per (repo, branch, PR target). Rules 1, 4 and 5 are repo-wide;
    rules 0 and 2 can differ per branch."""
    key = (gitdir, branch or "", pr_base)
    if key not in _base_cache:
        _base_cache[key] = _resolve_base(gitdir, repo, branch, cfg, pr_bases, pr_base)
    return _base_cache[key]


def _resolve_base(gitdir: str, repo: str, branch: Optional[str], cfg: dict,
                  pr_bases: Optional[Counter], pr_base: str = "") -> Tuple[str, str]:
    # 0. the branch's own open PR. Every other rule guesses what this branch
    #    will merge into; the PR says so. Measured: a sprint branch whose PR
    #    targets `beta` was read as +0/-56 against the repo's newer sprint
    #    branch — the modal vote — which is the base of other branches, not
    #    of this one. A stacked PR is measured against the branch below it,
    #    which is exactly the work the PR contains.
    if pr_base:
        ref = "origin/" + pr_base
        if ref_exists(gitdir, ref):
            return ref, "pr"

    # 1. explicit override
    override = (cfg.get("base") or {}).get(repo)
    if override:
        ref = override if "/" in override else "origin/" + override
        if ref_exists(gitdir, ref):
            return ref, "config"
        if ref_exists(gitdir, override):
            return override, "config"

    # 2. the branch's own configured upstream, when it names something else
    if branch:
        _, merge, _ = git(["config", "--get", f"branch.{branch}.merge"], gitdir=gitdir)
        _, remote, _ = git(["config", "--get", f"branch.{branch}.remote"], gitdir=gitdir)
        up = merge.replace("refs/heads/", "", 1) if merge else ""
        if up and up != branch and remote:
            ref = f"{remote}/{up}"
            if ref_exists(gitdir, ref):
                return ref, "upstream"

    # 3. the most common base among the repo's OPEN prs.
    #
    #    Guarded by an absolute vote count, never a share. Measured: the correct
    #    base for a busy repo won with only 52% of the vote, so any "clear
    #    majority" threshold rejects the right answer and falls back to a wrong
    #    one. What distinguishes signal from noise here is how many PRs agree,
    #    not what fraction of them did.
    if pr_bases:
        top, votes = pr_bases.most_common(1)[0]
        if votes >= int(cfg.get("min_base_votes", 5)):
            ref = "origin/" + top
            if ref_exists(gitdir, ref):
                return ref, f"prs({votes})"

    # 4. the remote's default branch
    default, _ = repo_facts(gitdir)
    if default:
        return "origin/" + default, "origin/HEAD"

    for guess in ("origin/main", "origin/master"):
        if ref_exists(gitdir, guess):
            return guess, "guess"

    # 5. a repo with no remote at all. There is nothing to be behind and no
    #    forge to merge into, so its own main branch is the only base there can
    #    be. Without this the main checkout of every local-only repo read as
    #    "your move", unresolved, beside "2 unpushed" — true of every commit
    #    in a repo that has nowhere to push to.
    if not git(["remote"], gitdir=gitdir)[1]:
        for local in ("main", "master", "trunk"):
            if ref_exists(gitdir, "refs/heads/" + local):
                return local, "local"
    return "", "unresolved"


_repo_facts: Dict[str, Tuple[str, str]] = {}


def repo_facts(gitdir: str) -> Tuple[str, str]:
    """(default branch, origin url) for a repo, asked once.

    Both were being asked per *worktree*, and a repo here has up to nineteen.
    The answer cannot differ between them — they share one common dir — so the
    extra calls were pure repetition: two thirds of every refresh's subprocesses.
    """
    if gitdir not in _repo_facts:
        rc, out, _ = git(["symbolic-ref", "-q", "refs/remotes/origin/HEAD"], gitdir=gitdir)
        default = out.replace("refs/remotes/origin/", "", 1) if rc == 0 and out else ""
        _, origin, _ = git(["remote", "get-url", "origin"], gitdir=gitdir)
        _repo_facts[gitdir] = (default, origin)
    return _repo_facts[gitdir]


_ref_cache: Dict[Tuple[str, str], bool] = {}


def ref_exists(gitdir: str, ref: str) -> bool:
    key = (gitdir, ref)
    if key not in _ref_cache:
        rc, _, _ = git(["rev-parse", "--verify", "-q", ref + "^{commit}"], gitdir=gitdir)
        _ref_cache[key] = rc == 0
    return _ref_cache[key]


# ─────────────────────────────────────────────────────────────────────────────
# Pull requests
# ─────────────────────────────────────────────────────────────────────────────

def rollup_verdict(rollup) -> Tuple[str, List[str]]:
    """Reduce a statusCheckRollup to a verdict plus the names that failed."""
    if not rollup:
        return "none", []
    failing, pending, total = [], False, 0
    for c in rollup:
        total += 1
        state = c.get("conclusion") or c.get("state")
        name = c.get("name") or c.get("context") or "?"
        if state in ("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED"):
            failing.append(name)
        elif state in ("PENDING", "IN_PROGRESS", "QUEUED", "EXPECTED", None):
            pending = True
    if failing:
        return "failing", failing
    if pending:
        return "pending", []
    return ("passing", []) if total else ("none", [])


# ─────────────────────────────────────────────────────────────────────────────
# GitHub accounts
#
# `gh` answers for whichever account is *active* and for no other. Anyone signed
# in to two — a work identity and a personal one being the common pair — gets
# "not visible to the active account" for every repo belonging to the other.
# On this machine that was sixteen repos of twenty-seven, and the notice read
# as a permissions problem when the truth was that the tool was asking the
# wrong account. A count that is right about half your work looks exactly like
# a count that is right, which is the failure this section exists to end.
#
# The token is passed as GH_TOKEN rather than by switching the active account:
# switching is global, persistent, and would change what every other terminal
# on the machine sees. A tool that reads your repos must not reconfigure them.
# ─────────────────────────────────────────────────────────────────────────────

Account = Tuple[str, str]        # (login, host)

_accounts: Optional[List[Account]] = None
_tokens: Dict[Account, Optional[str]] = {}
# Repos are scanned on up to sixteen threads, and both caches above are filled
# by whichever thread arrives first while the rest are already running. See
# gh_accounts() for what that cost before there was a lock here.
_account_lock = threading.Lock()


def gh_accounts() -> List[Account]:
    """Every healthy account `gh` knows about, active first.

    An older `gh` without `auth status --json` returns an empty list, which
    means "ask the way we always did" — the caller then runs with no token
    overlay at all and the behaviour is exactly what it was before any of this.
    An empty list is never "you have no accounts".
    """
    global _accounts
    with _account_lock:
        if _accounts is not None:
            return _accounts
        _accounts = _read_accounts()
        return _accounts


def _read_accounts() -> List[Account]:
    """Ask `gh`. Called once, under the lock, and never publishes half of it.

    This used to assign `_accounts = []` on entry and fill it in at the end,
    with a `gh auth status` subprocess — about 200ms — in between. Every one of
    the other fifteen scan threads arriving in that window saw a non-None
    `_accounts` and took the empty list, which `accounts_for` turns into
    `[None]`: no token overlay, so the call runs as whichever account `gh` has
    active. For a repo only the *other* account can see that is "Could not
    resolve to a Repository", which is exactly the string that marks a repo
    unseen for the next fifteen minutes.

    Measured before the lock: fifteen of sixteen threads took the empty list,
    and seventeen readable repos out of twenty-seven were reported invisible.
    The multi-account support worked perfectly in every serial test and was
    defeated on almost every repo in the run that matters.

    The sentinel is what made it silent. An empty list already meant something
    — "an older `gh`, ask the way we always did" — so the half-built value was
    indistinguishable from a legitimate answer, and nothing anywhere could
    tell them apart.
    """
    if not have("gh"):
        return []
    rc, out, _ = sh(["gh", "auth", "status", "--json", "hosts"], timeout=10)
    if rc != 0 or not out:
        return []
    try:
        hosts = json.loads(out).get("hosts", {})
    except json.JSONDecodeError:
        return []
    found: List[Tuple[bool, str, str]] = []
    for host, entries in hosts.items():
        for e in entries or []:
            # Anything other than a reported success is skipped: an unfamiliar
            # state is not evidence of a working token, and spending a round
            # trip to find that out is the cost this whole section avoids.
            if e.get("state") != "success" or not e.get("login"):
                continue
            found.append((bool(e.get("active")), host, str(e["login"])))
    # Active first, then stable: `gh`'s own order is unspecified, and an order
    # that changes between runs makes the cached per-repo answer churn.
    found.sort(key=lambda t: (not t[0], t[1].lower(), t[2].lower()))
    return [(login, host) for _, host, login in found]


def account_token(acct: Account) -> Optional[str]:
    """The token for one account, fetched once however many threads ask.

    Held for the fetch, not only for the dictionary write: sixteen threads
    that each miss the cache are sixteen `gh auth token` subprocesses for one
    answer, and the wrong half of that race is a thread proceeding with no
    token at all.
    """
    login, host = acct
    with _account_lock:
        if acct not in _tokens:
            rc, out, _ = sh(["gh", "auth", "token", "--user", login,
                             "--hostname", host], timeout=10)
            _tokens[acct] = out if rc == 0 and out else None
        return _tokens[acct]


def gh_env(acct: Optional[Account]) -> Optional[Dict[str, str]]:
    """The environment that makes `gh` speak as `acct`, or None for "as it is"."""
    if acct is None:
        return None
    token = account_token(acct)
    if token is None:
        return None
    return {"GH_TOKEN": token, "GH_HOST": acct[1]}


def origin_owner(origin: str) -> str:
    """The `owner` of `github.com/owner/repo`, from either URL form."""
    m = re.search(r"github\.com[:/]+([^/]+)/", origin or "")
    return m.group(1) if m else ""


def _seen_by_file(origin: str) -> Path:
    key = hashlib.sha1(("seenby:" + origin).encode()).hexdigest()[:16]
    return cache_dir() / f"seenby-{key}"


_SEEN_BY_TTL = 6 * 3600     # an account's *visibility* of a repo changes when
                            # you are added to it, which is a rare event; the
                            # cost of being wrong is one wasted call


def remembered_account(origin: str) -> Optional[Account]:
    """Which account answered for this repo last time.

    Without this, a machine with two accounts pays an extra failed round trip
    per repo per run, forever. With it, the probe is paid once.
    """
    f = _seen_by_file(origin)
    if not f.exists() or (time.time() - f.stat().st_mtime) >= _SEEN_BY_TTL:
        return None
    try:
        login, _, host = f.read_text().strip().partition("\t")
    except OSError:
        return None
    acct = (login, host)
    return acct if acct in gh_accounts() else None


def remember_account(origin: str, acct: Account) -> None:
    try:
        f = _seen_by_file(origin)
        f.write_text(f"{acct[0]}\t{acct[1]}")
        os.chmod(f, 0o600)
    except OSError:
        pass


def accounts_for(origin: str) -> List[Optional[Account]]:
    """The accounts to try for this repo, best guess first.

    Three rules, and the first two mean the usual case costs one call:

    1. whichever account answered for this repo before;
    2. the account whose login *is* the repo's owner — `samiesmilz/AIGovSpec`
       is almost certainly readable by `samiesmilz` and by nobody else;
    3. everything else in `gh`'s order, active first.

    `[None]` when `gh` cannot list accounts: one attempt, unmodified, which is
    the behaviour this tool had before it knew accounts existed.
    """
    accts = gh_accounts()
    if len(accts) <= 1:
        return [None]
    order: List[Account] = []
    for candidate in (remembered_account(origin),):
        if candidate:
            order.append(candidate)
    owner = origin_owner(origin).lower()
    for a in accts:
        if a[0].lower() == owner and a not in order:
            order.append(a)
    for a in accts:
        if a not in order:
            order.append(a)
    return list(order)


UNRESOLVED = "Could not resolve to a Repository"


def gh_json(args: Sequence[str], workdir: str, origin: str,
            timeout: int = 45) -> Tuple[int, str, str, Optional[Account]]:
    """Run a `gh` query as whichever signed-in account can see this repo.

    Returns the first account that does not answer "no such repository". A
    repo genuinely nobody can see costs one call per account, once, and is
    then remembered as unseen — the alternative is a tool that reports half
    your work and looks certain about it.
    """
    last: Tuple[int, str, str] = (1, "", "no account tried")
    for acct in accounts_for(origin):
        rc, out, err = sh(list(args), cwd=workdir, timeout=timeout, env=gh_env(acct))
        if rc == 0:
            if acct is not None:
                remember_account(origin, acct)
            return rc, out, err, acct
        last = (rc, out, err)
        # Only "this account cannot see the repo" is worth asking someone else
        # about. A timeout or a rate limit will fail the same way for every
        # account, and trying each of them turns one slow call into N.
        if UNRESOLVED not in err:
            break
    return last[0], last[1], last[2], None


_UNSEEN_TTL = 900        # long enough to stop re-asking, short enough to notice
                         # an account switch within a coffee break


def _unseen_file(origin: str) -> Path:
    """Keyed by the accounts that were asked, not by the repo alone.

    The marker means "nobody we can ask can see this", and *who we can ask*
    changes the moment you `gh auth login`. Keying on the repo alone leaves a
    refusal recorded against a question that is no longer the one being asked:
    when this file's meaning widened from one account to all of them, every
    repo the second account could see went on being reported invisible,
    because a marker written by the old code still answered for the new.

    Folding the account list into the key retires those markers automatically
    and — more usefully — makes signing in to another account re-ask every
    repo that had given up, which is exactly what someone who just signed in
    expects to happen.
    """
    who = ",".join(sorted(login for login, _ in gh_accounts()))
    key = hashlib.sha1(f"unseen:{who}:{origin}".encode()).hexdigest()[:16]
    return cache_dir() / f"unseen-{key}"


def known_unseen(origin: str) -> bool:
    """Whether this repo already refused to resolve recently, for *every*
    account signed in.

    Ten of the repos on this machine are invisible to all of them — never
    pushed, or deleted on the forge — and each one costs a round trip per
    account to be told so again. Remembering the refusal is most of the time
    the tool used to spend waiting.
    """
    f = _unseen_file(origin)
    return f.exists() and (time.time() - f.stat().st_mtime) < _UNSEEN_TTL


def mark_unseen(origin: str) -> None:
    try:
        _unseen_file(origin).write_text("")
    except OSError:
        pass


# Long enough that repeated runs in one sitting are free, short enough that the
# app's five-minute refresh always fetches rather than re-reading itself. At 60s
# almost every run missed, which is why the runtime swung between 5 and 13
# seconds for no visible reason.
PR_TTL = 180


def fetch_prs(workdir: str, gitdir: str, ttl: int = PR_TTL) -> Tuple[Dict[str, PR], Counter, Counter, int]:
    """One batched call per repo — it answers both "what is the state of my
    PRs" and "what do this repo's PRs actually target". Open PRs only.

    Asking for --state all together with statusCheckRollup returns HTTP 504 on a
    busy repo: the rollup fans out to every check run of every PR, and closed PRs
    make that set unbounded. We never need it — whether work landed is answered
    by git, locally and for free.
    """
    if not have("gh"):
        return {}, Counter(), Counter(), 0
    origin = repo_facts(gitdir)[1]
    expects_forge = "github.com" in origin
    if expects_forge and known_unseen(origin):
        NOTICES.append(("unseen", Path(workdir).name, "not visible to any signed-in account"))
        return {}, Counter(), Counter(), 0

    # A short cache makes repeated runs free without ever showing stale state
    # long enough to mislead. Skipped entirely when the answer would be useless.
    # str.__hash__ is salted per process, so it can never produce a stable key.
    key = hashlib.sha1((origin or workdir).encode()).hexdigest()[:16]
    ck = cache_dir() / f"pr-{key}.json"
    if ttl > 0 and ck.exists() and (time.time() - ck.stat().st_mtime) < ttl:
        try:
            return decode_prs(json.loads(ck.read_text()))
        except Exception:
            pass

    rc, out, err, _ = gh_json([
        "gh", "pr", "list", "--limit", "100", "--state", "open", "--json",
        "headRefName,baseRefName,number,state,isDraft,statusCheckRollup,reviewDecision,url,author",
    ], workdir, origin)
    if rc != 0 or not out:
        if expects_forge:
            detail = (err or "no response").splitlines()[0]
            # "no account can see this repo" is one condition about the
            # session, not one problem per repo. Tagged so the footer can
            # collapse it — and it now means every signed-in account was
            # asked, not merely the active one.
            kind = "unseen" if UNRESOLVED in detail else "other"
            if kind == "unseen":
                mark_unseen(origin)
            NOTICES.append((kind, Path(workdir).name, detail[:100]))
        return {}, Counter(), Counter(), 0
    try:
        rows = json.loads(out)
    except json.JSONDecodeError:
        if expects_forge:
            NOTICES.append(("other", Path(workdir).name, "unreadable pull request data"))
        return {}, Counter(), Counter(), 0

    if ttl > 0:
        try:
            ck.write_text(json.dumps(rows))
            os.chmod(ck, 0o600)
        except OSError:
            pass
    return decode_prs(rows)


MergedRef = Dict[str, object]     # number, url, merged_at, author, head_oid


def fetch_merged_refs(workdir: str, gitdir: str, ttl: int = 600) -> Dict[str, MergedRef]:
    """Branch names whose PR merged, with the commit that merged.

    `ahead == 0` cannot by itself tell "this landed" from "this never had a
    commit" — the tip is contained in the base either way. Only the forge knows,
    and asking costs one query with no statusCheckRollup, which is the field that
    makes the combined --state all query time out.

    The name alone is not evidence. Branch names are reused — `fix-typo`,
    `release`, a colleague's fork branch checked out to review — so a merged PR
    called X says nothing about the commits currently on your X. The head oid the
    forge merged is what the local HEAD is checked against, in `landed()`.
    """
    if not have("gh"):
        return {}
    origin = repo_facts(gitdir)[1]
    if "github.com" not in origin or known_unseen(origin):
        return {}
    key = hashlib.sha1(("merged:" + (origin or workdir)).encode()).hexdigest()[:16]
    ck = cache_dir() / f"pr-{key}.json"
    if ttl > 0 and ck.exists() and (time.time() - ck.stat().st_mtime) < ttl:
        try:
            cached = json.loads(ck.read_text())
            # An older cache stored entries without the oids. Without them there
            # is no evidence to check, so it is a miss rather than a weaker hit.
            if all(isinstance(v, dict) and "merge_oid" in v for v in cached.values()):
                return cached
        except Exception:
            pass
    rc, out, _, _ = gh_json(["gh", "pr", "list", "--limit", "100", "--state", "merged",
                             "--json", "headRefName,headRefOid,mergeCommit,number,url,mergedAt,author"],
                            workdir, origin, timeout=30)
    if rc != 0 or not out:
        return {}
    try:
        refs = {r["headRefName"]: {"number": int(r["number"]), "url": r.get("url", ""),
                                   "merged_at": r.get("mergedAt", ""),
                                   "author": (r.get("author") or {}).get("login", ""),
                                   "head_oid": r.get("headRefOid", ""),
                                   "merge_oid": (r.get("mergeCommit") or {}).get("oid", "")}
                for r in json.loads(out)}
    except (json.JSONDecodeError, KeyError, ValueError):
        return {}
    if ttl > 0:
        try:
            ck.write_text(json.dumps(refs))
            os.chmod(ck, 0o600)
        except OSError:
            pass
    return refs


def landed(gitdir: str, head: str, merged_oid: str, merge_oid: str = "") -> bool:
    """Whether every commit at `head` is inside the commit the forge merged.

    Equal oids is the common case. Otherwise `head` must be an ancestor of the
    merged tip — you have *fewer* commits than landed, which is still landed.
    The reverse (you committed after the merge) is not, and neither is an oid
    we do not have locally: `merge-base` fails on an unknown commit, and a
    failure here means "unproven", never "merged".

    One more proof needs no oid of the PR's at all: a squash merge whose
    change is byte-identical to this branch's. The PR's last head is often a
    commit this machine never saw — the branch was updated on the forge, then
    squashed and deleted — while the squash itself is on the base you
    fetched. Measured: a worktree whose six commits were all inside #695
    read "6 unpushed" for a month, because its head was not the PR's.
    """
    if not head or not merged_oid:
        return False
    if head == merged_oid:
        return True
    rc, _, _ = git(["merge-base", "--is-ancestor", head, merged_oid], gitdir=gitdir)
    if rc == 0:
        return True
    return bool(merge_oid) and squashed(gitdir, head, merge_oid)


def squashed(gitdir: str, head: str, merge_oid: str) -> bool:
    """Whether `merge_oid` made exactly the change this branch makes.

    Compared by patch-id, which ignores line numbers and whitespace in the
    hunk headers, so the squash still matches after the base moved under the
    branch. Anything short of identical — a commit added here after the
    merge, a fix-up made only on the forge — stays unproven.
    """
    rc, base, _ = git(["merge-base", f"{merge_oid}^", head], gitdir=gitdir)
    if rc != 0 or not base.strip():
        return False

    def patch_id(a: str, b: str) -> str:
        rc, diff, _ = git(["diff", a, b], gitdir=gitdir, timeout=60)
        if rc != 0 or not diff.strip():
            return ""
        out = subprocess.run(["git", "patch-id", "--stable"], input=diff,
                             capture_output=True, text=True).stdout.split()
        return out[0] if out else ""

    mine = patch_id(base.strip(), head)
    return bool(mine) and mine == patch_id(f"{merge_oid}^", merge_oid)


def decode_prs(rows) -> Tuple[Dict[str, PR], Counter, Counter, int]:
    """The PR map, from gh's rows or the cached copy of them."""
    prs: Dict[str, PR] = {}
    bases: Counter = Counter()
    failure_rate: Counter = Counter()
    for r in rows:
        verdict, failing = rollup_verdict(r.get("statusCheckRollup"))
        prs[r["headRefName"]] = PR(
            number=r["number"], state=r.get("state", "OPEN"),
            draft=bool(r.get("isDraft")), checks=verdict,
            review=r.get("reviewDecision") or "none", failing=failing,
            url=r.get("url", ""),
            author=(r.get("author") or {}).get("login", ""),
            base=r.get("baseRefName") or "",
        )
        failure_rate.update(set(failing))
        if r.get("baseRefName"):
            bases[r["baseRefName"]] += 1
    return prs, bases, failure_rate, len(rows)


def subtract_baseline(prs: Dict[str, PR], failure_rate: Counter, total: int) -> None:
    """Remove checks that fail across the whole repo from each PR's blame.

    A check failing on nearly every open PR is broken shared infrastructure; it
    says nothing about your branch. Measured on a real repo: one check failed on
    16 of 17 open PRs. Reporting that as "you are blocked" on each of them turns
    one infrastructure problem into N personal ones, and a tool that manufactures
    work is a tool you learn to ignore.

    We already hold every open PR, so the denominator is free.
    """
    if total < 3:
        for pr in prs.values():
            pr.distinct_failing = list(pr.failing)
        return
    endemic = {name for name, n in failure_rate.items() if n / total >= 0.5}
    for pr in prs.values():
        pr.distinct_failing = [f for f in pr.failing if f not in endemic]
        pr.endemic = [f for f in pr.failing if f in endemic]
        # The verdict has to move with the evidence. Leaving `checks` at
        # "failing" after deciding none of the failures are yours would let the
        # raw verdict veto the very correction we just made.
        if pr.failing and not pr.distinct_failing:
            pr.checks = "endemic"


# ─────────────────────────────────────────────────────────────────────────────
# Status derivation — the answer. Everything else is evidence.
#
# First match wins, and the ORDER is load-bearing. A broad rule placed early
# silently starves a narrow rule below it, and the symptom is a status that
# never appears in the output at all. Each ordering choice below is commented
# with what it would swallow if moved.
# ─────────────────────────────────────────────────────────────────────────────

TRUNK, MERGED, EMPTY = "trunk", "merged", "empty"
BLOCKED, REVIEW, WAITING, DRAFT = "blocked", "review", "waiting", "draft"
STALE, ACTIVE = "stale", "active"

ORDER = [BLOCKED, REVIEW, ACTIVE, WAITING, DRAFT, STALE, EMPTY, MERGED, TRUNK]

MEANING = {
    TRUNK:   "the base itself — not yours to finish",
    MERGED:  "landed; check local files before removal",
    EMPTY:   "nothing here the base does not already have",
    BLOCKED: "your move, and it is specific to this branch",
    REVIEW:  "changes requested — your move",
    WAITING: "someone else's move",
    DRAFT:   "yours, not yet offered",
    STALE:   "you forgot this exists",
    ACTIVE:  "your move",
}

GLYPH = {
    TRUNK: "=", MERGED: "*", EMPTY: "o", BLOCKED: "!", REVIEW: "!",
    WAITING: ">", DRAFT: ".", STALE: "~", ACTIVE: "+",
}

COLOR = {}


def init_colors() -> None:
    COLOR.update({
        TRUNK: C.blue, MERGED: C.dim + C.cyan, EMPTY: C.dim,
        BLOCKED: C.red, REVIEW: C.red, WAITING: C.yellow,
        DRAFT: C.dim + C.yellow, STALE: C.magenta, ACTIVE: C.green,
    })


def quiet_days(w: Worktree) -> int:
    """Days since anything happened here: the last commit, or the merge if later."""
    merged = w.pr.merged_at if w.pr else ""
    try:
        when = calendar.timegm(time.strptime(merged[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return w.age_days
    return min(w.age_days, int((time.time() - when) / 86400))


def derive_status(w: Worktree, stale_days: int) -> str:
    pr = w.pr
    # Every "finished" verdict is a claim about a base. With no base resolved,
    # ahead/behind are both 0 by default, which makes an untouched branch look
    # identical to a fully merged one. Refusing to decide is the only honest
    # answer, and it keeps `reap` away from work it cannot reason about.
    grounded = w.base_source != "unresolved" and w.base != "(none)"

    # B1. The base branch is trivially an ancestor of itself, so every naive
    #     "merged" test reports the integration branch as reapable. It is the
    #     one branch that is never finished and must never be reaped.
    if w.is_base and grounded:
        return TRUNK

    # Uncommitted work outranks everything below: whatever the remote thinks,
    # there is state here that exists nowhere else. Except where there is not:
    # a merged PR whose only leftovers are deleted tracked files has nothing
    # here that git lacks. Measured: 724 files gone from a squash-merged
    # checkout kept it out of `merged` for a month.
    landed_clean = pr is not None and pr.state == "MERGED" and w.would_lose == 0
    if not w.clean and not landed_clean:
        # ...but a dirty tree nothing has happened to for weeks is forgotten,
        # not in flight. Only an open PR keeps it in flight: a merged one is
        # work that landed with a file left behind. That case used to read
        # "your move" — three worktrees here, merged 20 to 43 days ago, each
        # holding one stray file — because this guard asked only for no PR.
        if (pr is None or pr.state != "OPEN") and quiet_days(w) > stale_days:
            return STALE
        return ACTIVE

    if pr and pr.state == "OPEN":
        # B3. Only failures distinct from the repo-wide baseline are yours.
        if pr.review == "CHANGES_REQUESTED":
            return REVIEW
        if pr.distinct_failing:
            return BLOCKED
        if pr.draft:
            return DRAFT
        # B4. `waiting` must not require checks == passing. A repo with no CI
        #     reports "none" forever, so requiring green makes `waiting`
        #     unreachable there and mislabels "awaiting review" as "your move".
        if pr.checks in ("passing", "none", "pending", "endemic"):
            return WAITING
        return ACTIVE

    if pr and pr.state == "MERGED":
        return MERGED

    if not grounded:
        return STALE if w.age_days > stale_days else ACTIVE

    # B2. `ahead == 0` means the tip is already contained in the base — but that
    #     is true both for work that landed AND for a branch that never had a
    #     commit. They are different answers: one is finished, the other was
    #     abandoned before it began. Only a merged PR proves the first, and that
    #     case was handled above; with no such proof this is `empty`. A branch
    #     created a minute ago with no commits used to read "landed; safe to
    #     reap" here, which is the one label a zero-commit branch must never get.
    if w.ahead == 0:
        return EMPTY

    # B5. `stale` must be tested before the catch-all. "Ahead of base with no
    #     PR" describes forgotten work precisely, so an `active` rule containing
    #     that clause swallows the entire population `stale` exists to name.
    if w.age_days > stale_days:
        return STALE
    return ACTIVE


# ─────────────────────────────────────────────────────────────────────────────
# Disk
# ─────────────────────────────────────────────────────────────────────────────

_SIZE_CACHE: Dict[str, List] = {}
_SIZE_CACHE_TTL = 900          # 15 min: long enough to be free, short enough to be true
_size_cache_loaded = False


def _size_cache_file() -> Path:
    return cache_dir() / "sizes.json"


def load_size_cache() -> None:
    global _size_cache_loaded
    if _size_cache_loaded:
        return
    _size_cache_loaded = True
    try:
        _SIZE_CACHE.update(json.loads(_size_cache_file().read_text()))
    except Exception:
        return
    # Paths that no longer exist, and entries past their TTL: pruned on load,
    # not only on write, so a run that measures nothing still tidies.
    now = time.time()
    for k in [k for k, v in _SIZE_CACHE.items()
              if now - v[1] >= _SIZE_CACHE_TTL or not os.path.exists(k)]:
        _SIZE_CACHE.pop(k, None)


def save_size_cache() -> None:
    if not _SIZE_CACHE:
        return
    try:
        now = time.time()
        fresh = {k: v for k, v in _SIZE_CACHE.items() if now - v[1] < _SIZE_CACHE_TTL}
        f = _size_cache_file()
        f.write_text(json.dumps(fresh))
        # These name private repositories and branches. Default umask leaves
        # them world-readable, which hands every local account a map of what
        # you work on.
        os.chmod(f, 0o600)
    except OSError:
        pass


def forget_size(path: str) -> None:
    """Drop cached sizes for a path and everything under it, after we change it."""
    for k in [k for k in _SIZE_CACHE if k == path or k.startswith(path + os.sep)]:
        _SIZE_CACHE.pop(k, None)


def du_many(paths: List[str], timeout: int = 180) -> Dict[str, int]:
    """Size several paths in one `du`.

    One spawn per path is the whole cost of a sized scan: a monorepo worktree
    has about thirty reclaimable directories, and nineteen of those worktrees
    meant nearly six hundred processes to answer one question. `du -sk a b c`
    answers it once, and its output is already keyed by path.
    """
    if not paths:
        return {}
    load_size_cache()
    now = time.time()
    out: Dict[str, int] = {}
    ask: List[str] = []
    for p in paths:
        hit = _SIZE_CACHE.get(p)
        if hit and (now - hit[1]) < _SIZE_CACHE_TTL:
            out[p] = int(hit[0])
        else:
            ask.append(p)
    if not ask:
        return out
    rc, text, _ = sh(["du", "-sk"] + ask, timeout=timeout)
    # du keeps going after an unreadable path, so a non-zero exit still carries
    # usable lines for everything it did manage to read.
    for line in text.splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        try:
            kb = int(parts[0].strip())
        except ValueError:
            continue
        path = parts[1]
        out[path] = kb
        _SIZE_CACHE[path] = [kb, now]
    for p in ask:
        out.setdefault(p, -1)
    return out


def du_kb(path: str, timeout: int = 120, cache: bool = True) -> int:
    if cache:
        load_size_cache()
        hit = _SIZE_CACHE.get(path)
        if hit and (time.time() - hit[1]) < _SIZE_CACHE_TTL:
            return int(hit[0])
    rc, out, _ = sh(["du", "-sk", path], timeout=timeout)
    if rc != 0 or not out:
        return -1
    try:
        kb = int(out.split()[0])
    except (ValueError, IndexError):
        return -1
    if cache:
        _SIZE_CACHE[path] = [kb, time.time()]
    return kb


# Ignored entries the probe's own status call already reported, per worktree.
# A sized scan used to walk every tree twice: once for dirty state, once for
# the ignored list, and both are answered by one `git status`.
_IGNORED: Dict[str, List[str]] = {}


def ignored_entries(path: str) -> List[str]:
    """Top-level ignored paths, as git itself reports them.

    `--ignored=traditional` collapses a wholly-ignored directory to one entry,
    so a 40,000-file node_modules costs one line instead of forty thousand.
    This is what keeps the scan agnostic: the repo's own .gitignore decides what
    is ignored, and we only decide what is *safe*.

    Served from the probe's status call when it asked for them; otherwise one
    call here.
    """
    if path in _IGNORED:
        return _IGNORED[path]
    # --untracked-files=no suppresses the ignored list too, so it cannot be used
    # here however much faster it looks.
    rc, out, _ = git(
        ["status", "--porcelain=v2", "--ignored=traditional"], cwd=path, timeout=90,
    )
    if rc != 0:
        return []
    # Not memoised here: only the probe's capture is trusted to be current,
    # and a listing kept across two measurements of one tree would miss what
    # a build wrote in between.
    return parse_ignored(out)


def parse_ignored(porcelain_v2: str) -> List[str]:
    entries = []
    for ln in porcelain_v2.splitlines():
        if ln.startswith("! "):
            path = unquote_path(ln[2:])
            if path is not None:
                entries.append(path)
    return entries


def unquote_path(raw: str) -> Optional[str]:
    """A path as git prints it, back to the path on disk.

    Git C-quotes a path holding a space, a quote, a control character or any
    non-ASCII byte: `"cach\303\251dir/"` is `cachédir/`. The escapes are of
    UTF-8 *bytes*, so decoding them as characters yields `cachÃ©dir/` - a path
    that does not exist, which then silently dropped out of both the size and
    the plan. Decode the escapes to bytes, then the bytes as UTF-8. None means
    it could not be decoded, and a path we cannot name is a path we do not touch.
    """
    raw = raw.strip()
    if not (raw.startswith('"') and raw.endswith('"') and len(raw) >= 2):
        return raw
    try:
        return raw[1:-1].encode("utf-8").decode("unicode_escape") \
                  .encode("latin-1").decode("utf-8")
    except (UnicodeDecodeError, UnicodeEncodeError, ValueError):
        return None


def measure(w: Worktree, want_detail: bool = True) -> None:
    """Fill in size_kb / reclaim_kb and the three path buckets."""
    if not want_detail:
        w.size_kb = du_kb(w.path)
        return
    safe: List[Tuple[str, str]] = []
    for entry in ignored_entries(w.path):
        if record_ignored(w, entry) == SAFE:
            safe.append((entry, os.path.join(w.path, entry)))
    w.ignored_scanned = True
    unknown = [os.path.join(w.path, e.rstrip("/")) for e in w.unknown_paths]
    sizes = du_many([w.path] + [full for _, full in safe] + unknown)
    w.unknown_kb = (sum(sizes.get(p, -1) for p in unknown)
                    if all(sizes.get(p, -1) >= 0 for p in unknown) else -1)
    w.size_kb = sizes.get(w.path, -1)
    reclaim = 0
    for entry, full in safe:
        kb = sizes.get(full, -1)
        if kb > 0:
            reclaim += kb
            w.reclaim_paths.append(entry)
    w.reclaim_kb = reclaim


def human(kb: int) -> str:
    """A size, with the unit spelled far enough to be a unit.

    `348M` was `348` with a letter after it, and the letter is the only thing
    saying this column is bytes at all. In a row of plain counts — 3 needing
    you, 17 forgotten, 56 commits only here — it reads as "348 million", which
    is a perfectly sensible thing for a column of counts to say and is wrong.
    `MB` cannot be read as anything but a size, and costs one character.
    """
    if kb < 0:
        return "—"
    units = [("TB", 1 << 30), ("GB", 1 << 20), ("MB", 1 << 10)]
    for suffix, factor in units:
        if kb >= factor:
            v = kb / factor
            return f"{v:.1f}{suffix}" if v < 10 else f"{v:.0f}{suffix}"
    return f"{kb}KB"


# ─────────────────────────────────────────────────────────────────────────────
# Gather
# ─────────────────────────────────────────────────────────────────────────────

_state: Dict[str, dict] = {}
_state_loaded = False
_state_ignore_file = False  # --refresh: start empty, and overwrite on save


def _state_file() -> Path:
    return cache_dir() / "state.json"


def load_state() -> None:
    global _state_loaded
    if _state_loaded:
        return
    _state_loaded = True
    if _state_ignore_file:
        return
    try:
        _state.update(json.loads(_state_file().read_text()))
    except Exception:
        pass


def save_state() -> None:
    if not _state:
        return
    try:
        f = _state_file()
        f.write_text(json.dumps(_state))
        os.chmod(f, 0o600)
    except OSError:
        pass


def _worktree_gitdir(path: str, gitdir: str) -> Optional[str]:
    """The directory holding this worktree's HEAD and index, or None.

    A linked worktree's .git is a file naming it, absolute or - with
    worktree.useRelativePaths - relative to the worktree. The main checkout's
    .git is the common dir itself. None means we cannot find it, and a
    fingerprint that cannot see HEAD must not exist rather than exist weakly.
    """
    dot = os.path.join(path, ".git")
    if os.path.isdir(dot):
        return dot
    try:
        with open(dot) as fh:
            target = fh.read().strip().split("gitdir:", 1)[-1].strip()
    except OSError:
        return None
    if not target:
        return None
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(path, target))
    return target if os.path.isdir(target) else None


_packed_cache: Dict[str, Tuple[str, Dict[str, str]]] = {}


def _packed_refs(gitdir: str) -> Tuple[str, Dict[str, str]]:
    """(stat signature, {refname: oid}) for packed-refs, parsed once per change."""
    p = os.path.join(gitdir, "packed-refs")
    try:
        st = os.stat(p)
    except OSError:
        return "-", {}
    sig = f"{st.st_mtime_ns}:{st.st_size}"
    hit = _packed_cache.get(gitdir)
    if hit and hit[0] == sig:
        return sig, hit[1]
    refs: Dict[str, str] = {}
    try:
        with open(p) as fh:
            for line in fh:
                if line[:1] in ("#", "^"):
                    continue
                parts = line.split()
                if len(parts) == 2:
                    refs[parts[1]] = parts[0]
    except OSError:
        return sig, {}
    _packed_cache[gitdir] = (sig, refs)
    return sig, refs


def ref_value(gitdir: str, refname: str) -> Optional[str]:
    """What a ref points at, read from disk: the loose file first, then
    packed-refs. Loose wins, as it does in git. None when the ref does not exist."""
    try:
        with open(os.path.join(gitdir, refname)) as fh:
            v = fh.read().strip()
        if v:
            return v
    except OSError:
        pass
    return _packed_refs(gitdir)[1].get(refname)


def _refs_digest(gitdir: str) -> Optional[str]:
    """One hash over every loose ref file's path, mtime and size.

    A directory's mtime moves only when its *direct* entries change, so
    stat'ing refs/heads saw a commit on `main` and was blind to one on
    `feat/sprint/x`, and stat'ing refs/remotes never saw a fetch move
    origin/main. Whether the cache was correct depended on the team's branch
    naming convention. Walking the files is the only stat-based answer that
    does not; a repo has hundreds of loose refs at most, and a scandir over
    them costs less than one git process.
    """
    h = hashlib.sha1()
    stack = [os.path.join(gitdir, "refs")]
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    if e.is_dir(follow_symlinks=False):
                        stack.append(e.path)
                    else:
                        st = e.stat(follow_symlinks=False)
                        h.update(f"{e.path}:{st.st_mtime_ns}:{st.st_size}\n".encode())
        except OSError:
            return None
    return h.hexdigest()[:20]


def fingerprint(path: str, gitdir: str, salt: Sequence[str] = ()) -> str:
    """A signature of everything the cached history answers depend on.

    Pure file IO - no subprocess - which is the point: a fingerprint that
    costs a git invocation to compute saves nothing.

    What it reads, and why each is a value rather than a directory stat:

    * HEAD's content and, for a symbolic HEAD, the oid of the branch it names,
      from the loose file or packed-refs. The branch ref is *read*, not
      stat'ed, because an oid is always 40 bytes and a rewrite within one
      mtime tick would otherwise look identical.
    * The index's own checksum - git stores a hash of the index's content in
      its last twenty bytes - since staging changes what the history calls
      compare. Content, not mtime, so a coarse or skewed clock cannot hide a
      rewrite.
    * A digest over every loose ref file under refs/ (heads, remotes, tags),
      and packed-refs' stat, so a fetch, a push, a pack, a prune or a commit
      on any branch invalidates regardless of how deeply the ref is nested.
    * The repo config, for the branch's upstream; the tool config, for a
      pinned base; and `salt` - facts held in memory rather than on disk, such
      as the base ref's own oid and the oid the forge says merged.

    Anything it cannot read makes it empty, and an empty fingerprint is never
    cached against. A placeholder in one slot would keep the key well-formed
    while quietly removing the thing it was meant to watch.

    Repos on the reftable backend keep refs in a binary table this does not
    parse, so they are never cached: correct and slower beats fast and stale.
    """
    wt_git = _worktree_gitdir(path, gitdir)
    if wt_git is None or os.path.exists(os.path.join(gitdir, "reftable")):
        return ""
    parts: List[str] = []
    for p in (os.path.join(wt_git, "HEAD"), os.path.join(gitdir, "config")):
        try:
            st = os.stat(p)
        except OSError:
            return ""
        parts.append(f"{st.st_mtime_ns}:{st.st_size}")
    try:
        with open(os.path.join(wt_git, "index"), "rb") as fh:
            fh.seek(-20, os.SEEK_END)
            parts.append(fh.read(20).hex())
    except (OSError, ValueError):
        return ""
    try:
        with open(os.path.join(wt_git, "HEAD")) as fh:
            head = fh.read().strip()
    except OSError:
        return ""
    if not head:
        return ""
    parts.append(head)
    if head.startswith("ref: "):
        parts.append(ref_value(gitdir, head[5:].strip()) or "-")   # "-": unborn branch
    parts.append(_packed_refs(gitdir)[0])
    digest = _refs_digest(gitdir)
    if digest is None:
        return ""
    parts.append(digest)
    try:
        parts.append(str(config_path().stat().st_mtime_ns))
    except OSError:
        parts.append("-")
    parts.extend(salt)
    return "|".join(parts)


_identity: Dict[str, str] = {}


def identity(gitdir: str, path: str) -> str:
    """Your commit email in this repo, lowercased; asked once per repo.

    Per repo because one machine commits as a work identity in some repos and
    a personal one in others, and per-repo config is where that is decided.
    """
    if gitdir not in _identity:
        _identity[gitdir] = git(["config", "user.email"], cwd=path)[1].strip().lower()
    return _identity[gitdir]


def base_value(gitdir: str, base: Optional[str]) -> str:
    """The oid the resolved base points at, so a moved base is content-compared."""
    if not base or base == "(none)":
        return "-"
    ref = base if base.startswith("refs/") else "refs/remotes/" + base
    return ref_value(gitdir, ref) or ref_value(gitdir, "refs/heads/" + base) or "-"


STATE_VERSION = 6       # bumped whenever what a fingerprint covers changes


CACHED_FIELDS = ("ahead", "behind", "last_commit", "unpushed", "unpushed_mine",
                 "base", "base_source",
                 "landed", "solo_log")


def probe_worktree(gitdir: str, repo: str, main_wt: str, path: str,
                   branch: Optional[str], cfg: dict, pr_bases: Counter,
                   prs: Dict[str, PR],
                   merged_refs: Optional[Dict[str, MergedRef]] = None,
                   want_ignored: bool = False) -> Optional[Worktree]:
    """Everything knowable about one worktree. Pure reads; safe to run in parallel.

    `want_ignored` folds the ignored listing a sized scan needs into the status
    call that runs anyway, instead of a second full-tree walk later."""
    if not os.path.isdir(path):
        return None
    load_state()
    w = Worktree(
        repo=repo, path=path, branch=branch,
        primary=(os.path.realpath(path) == os.path.realpath(main_wt)),
        base="(none)", base_source="unresolved", repo_id=os.path.realpath(gitdir),
    )

    # The working tree first, and before the fingerprint. `git status` may
    # rewrite the index to settle racy timestamps, and a fingerprint taken
    # before it would be stale by the end of this same run - the run would act
    # on values it was about to invalidate, then miss twice more.
    status_args = ["status", "--porcelain=v2", "--untracked-files=normal"]
    if want_ignored:
        status_args.append("--ignored=traditional")
    rc, pv2, _ = git(status_args, cwd=path, timeout=90)
    if want_ignored and rc == 0:
        _IGNORED[path] = parse_ignored(pv2)
    for line in pv2.splitlines():
        if line.startswith(("1 ", "2 ")):
            xy = line.split()[1]
            if xy[0] != ".":
                w.staged += 1
            if xy[1] != ".":
                w.unstaged += 1
            w.deleted += xy.count("D")
        elif line.startswith("? "):
            w.untracked += 1

    merged = (merged_refs or {}).get(branch) if branch else None
    merged_oid = str(merged["head_oid"]) if merged else "-"
    merge_oid = str(merged.get("merge_oid", "")) if merged else ""
    top_vote = pr_bases.most_common(1)[0][0] if pr_bases else ""
    open_pr = prs.get(branch) if branch else None
    pr_base = open_pr.base if open_pr else ""
    me = identity(gitdir, path)
    cached = _state.get(path)
    if cached is not None and cached.get("v") != STATE_VERSION:
        cached = None

    def fp_for(base: Optional[str]) -> str:
        return fingerprint(path, gitdir,
                           salt=(merged_oid, merge_oid, top_vote, pr_base, me,
                                 base_value(gitdir, base)))

    fp = fp_for(cached["base"]) if cached else ""
    fresh = (bool(fp) and cached is not None and cached.get("fp") == fp
             and all(f in cached for f in CACHED_FIELDS))

    if fresh:
        # Nothing HEAD, the index or the refs depend on has moved, so the
        # history answers cannot have changed. Six git invocations per worktree,
        # skipped - which across sixty of them is most of a refresh.
        for field in CACHED_FIELDS:
            setattr(w, field, cached[field])
    else:
        base, source = resolve_base(gitdir, repo, branch, cfg, pr_bases, pr_base)
        w.base, w.base_source = base or "(none)", source
        head = git(["rev-parse", "HEAD"], cwd=path)[1]
        w.landed = bool(merged) and landed(gitdir, head, merged_oid, merge_oid)
        if base and head and ref_exists(gitdir, base):
            rc, ab, _ = git(["rev-list", "--left-right", "--count", f"{base}...{head}"],
                            gitdir=gitdir)
            if rc == 0 and ab:
                parts = ab.split()
                if len(parts) == 2:
                    w.behind, w.ahead = int(parts[0]), int(parts[1])
        ts = git(["log", "-1", "--format=%ct"], cwd=path)[1]
        w.last_commit = int(ts) if ts.isdigit() else 0
        # Commits reachable from HEAD that no remote-tracking ref contains -
        # i.e. work that exists on this machine and nowhere else. Asking the
        # branch's upstream instead answers nothing when there is no upstream,
        # and "no upstream" is exactly the case where everything is unpushed.
        # Getting this backwards lets `reap` delete the only copy of someone's
        # work.
        _, solo, _ = git(["rev-list", "--count", "HEAD", "--not", "--remotes"], cwd=path)
        w.unpushed = int(solo) if solo.isdigit() else max(w.ahead, 1)
        if w.unpushed > 0:
            # The same revision walk, asked who wrote each commit and what it
            # says. The subjects are capped at five: this is a reminder of
            # what is at stake, not a log viewer, and it rides inside an
            # envelope the app re-reads every five minutes.
            _, log, _ = git(["log", "--format=%ae%x00%s", "HEAD",
                             "--not", "--remotes"], cwd=path, timeout=60)
            rows = [l.split("\0", 1) for l in log.splitlines() if "\0" in l]
            # With no identity configured there is no telling whose they are,
            # so all of them count: overstating a risk is the safe mistake.
            mine = [r for r in rows if not me or r[0].strip().lower() == me]
            w.unpushed_mine = len(mine) if rows else w.unpushed
            w.solo_log = [r[1].strip()[:120] for r in (mine or rows)[:5] if r[1].strip()]
        if w.landed:
            # Proven inside what the forge merged, so not at risk whoever
            # wrote them. `unpushed` keeps the raw count, as evidence.
            w.unpushed_mine = 0
        fp = fp_for(w.base)
        if fp:
            _state[path] = dict({f: getattr(w, f) for f in CACHED_FIELDS},
                                fp=fp, v=STATE_VERSION)

    w.is_base = bool(branch) and w.base != "(none)" and w.base.split("/", 1)[-1] == branch
    w.age_days = int((time.time() - w.last_commit) / 86400) if w.last_commit else 9999

    if branch:
        w.pr = prs.get(branch)
        # A merged PR by this name is attached only once the commits here are
        # proven to be inside what merged. Otherwise the branch is judged on
        # its git state alone, like any branch with no PR.
        if w.pr is None and merged and w.landed:
            w.pr = PR(number=int(merged["number"]), state="MERGED", draft=False,
                      checks="none", review="none", url=str(merged["url"]),
                      merged_at=str(merged["merged_at"]), author=str(merged["author"]),
                      head_oid=merged_oid)

    if os.path.isfile(os.path.join(path, ".gitmodules")):
        rc, modules, _ = git(["ls-files", "--stage"], cwd=path)
        w.has_submodules = rc == 0 and any(l.startswith("160000 ") for l in modules.splitlines())

    w.status = derive_status(w, int(cfg.get("stale_days", 14)))
    return w


def scan_repo(gitdir: str, cfg: dict, want_ignored: bool = False) -> List[Worktree]:
    repo = Path(gitdir).parent.name
    rc, out, _ = git(["worktree", "list", "--porcelain"], gitdir=gitdir)
    if rc != 0:
        return []
    entries = parse_worktree_list(out)
    if not entries:
        return []
    main_wt = str(Path(gitdir).parent)

    pr_bases: Counter = Counter()
    prs: Dict[str, PR] = {}
    merged_refs: Dict[str, MergedRef] = {}
    if have("gh"):
        probe = next((p for p, _ in entries if os.path.isdir(p)), None)
        if probe:
            prs, pr_bases, failure_rate, total = fetch_prs(probe, gitdir)
            subtract_baseline(prs, failure_rate, total)
            merged_refs = fetch_merged_refs(probe, gitdir)

    # Each worktree costs ~5 git invocations and they do not touch each other.
    # Sequentially this is the whole runtime; in parallel it is one worktree.
    workers = max(1, min(12, len(entries)))
    with futures.ThreadPoolExecutor(max_workers=workers) as pool:
        results = pool.map(
            lambda e: probe_worktree(gitdir, repo, main_wt, e[0], e[1], cfg,
                                     pr_bases, prs, merged_refs, want_ignored),
            entries)
    rows = [w for w in results if w is not None]
    locks = {}
    for block in out.strip().split("\n\n"):
        lines = block.splitlines()
        path = next((l[9:] for l in lines if l.startswith("worktree ")), "")
        reason = next((l[6:].strip() or "locked" for l in lines if l == "locked" or l.startswith("locked ")), "")
        if path and reason:
            locks[os.path.realpath(path)] = reason
    for w in rows:
        w.locked = locks.get(os.path.realpath(w.path), "")
    return rows


def gather(cfg: dict, roots: Sequence[str], sizes: bool, detail: bool = True,
           paths: Optional[Sequence[str]] = None) -> List[Worktree]:
    # An explicit --path is authoritative scope, not a filter over whatever the
    # configured roots happened to include. Otherwise asking to clean one
    # worktree by its absolute path answers "nothing found" whenever that path
    # sits outside your roots — which reads as "there is nothing to reclaim".
    if paths:
        gitdirs = []
        for p in paths:
            cd = common_dir(os.path.expanduser(p))
            if cd and cd not in gitdirs:
                gitdirs.append(cd)
        if not gitdirs:
            die("none of those paths are inside a git repository")
    else:
        gitdirs = find_repos(roots) if roots else []
        if not gitdirs:
            cd = common_dir(os.getcwd())
            if not cd:
                # Raised, not died. "Nobody has said where the repos are" is a
                # state this tool knows how to get out of, and a caller with a
                # window to draw needs to tell it apart from a tool that is
                # broken. A terminal still gets the sentence, because in a
                # terminal `run this command` is the right next move.
                raise NotConfigured(
                    "not inside a git repository, and no roots configured.\n"
                    "       run `wt-manager config --init` to find them for you.")
            gitdirs = [cd]

    wts: List[Worktree] = []
    # Twenty-seven repos take about twelve seconds, most of it waiting on the
    # forge. Printing nothing for twelve seconds is indistinguishable from
    # having done nothing at all, which is how a working tool gets reported as
    # broken. The spinner costs nothing and removes the ambiguity.
    spin = Spinner(f"reading {len(gitdirs)} repo{'s' if len(gitdirs) != 1 else ''}",
                   total=len(gitdirs))
    # Network-bound, so the useful width is the number of repos, not of cores.
    with futures.ThreadPoolExecutor(max_workers=min(16, max(4, len(gitdirs)))) as pool:
        for res in pool.map(lambda g: scan_repo(g, cfg, sizes and detail), gitdirs):
            wts.extend(res)
            spin.step()
    spin.done()
    # Drop worktrees that no longer exist, or the file grows forever.
    for gone in [k for k in _state if not os.path.isdir(k)]:
        _state.pop(gone, None)
    save_state()

    if paths:
        wanted = {os.path.realpath(os.path.expanduser(p)) for p in paths}
        wts = [w for w in wts if os.path.realpath(w.path) in wanted]

    if sizes and wts:
        spin = Spinner(f"measuring {len(wts)} worktrees", total=len(wts))
        with futures.ThreadPoolExecutor(max_workers=12) as pool:
            list(pool.map(lambda w: (measure(w, detail), spin.tick()), wts))
        spin.done()
        save_size_cache()

    wts.sort(key=lambda w: (ORDER.index(w.status) if w.status in ORDER else 99,
                            -w.last_commit))
    return wts


# ─────────────────────────────────────────────────────────────────────────────
# Output
# ─────────────────────────────────────────────────────────────────────────────

# Progress, for a caller that is not a terminal.
#
# The app runs this file as a subprocess and otherwise has no way at all to
# know how far into a ninety-second walk it is; an indeterminate spinner over
# a minute and a half is indistinguishable from a hang.
#
# On stderr, never stdout: `--json` captures the whole of stdout into the
# plan's `text`, so a progress line written there would arrive at the end,
# inside a string, which is the one place it is no use.
#
# Opt-in, not "whenever stderr is not a terminal". That test is true of every
# pipe, so `wt-manager --json agent | jq` would start printing sixty lines of
# progress into a terminal that never asked for any — a caller that wants it
# says so.
# A run is not one bar, it is several. Reading every repo, measuring every
# worktree and removing what you approved are separate passes with separate
# totals, and the second cannot even be *counted* until the first has finished
# — you do not know how many worktrees there are until you have read the repos.
#
# So the line carries which pass it is. A bar that empties and starts again
# under the same heading is the single most reliable way to look broken; the
# same bar under "Step 2 of 3 · measuring 56 worktrees" is just a bar. The
# alternative — one bar weighted across all passes — would be a worse lie:
# reading 27 repos is four seconds and measuring 56 worktrees is eighty, so
# any weighting by item count sprints to a third and then appears to hang.
PROGRESS = "wt-progress"
_progress_on = False
_steps = 1          # how many passes this command will make
_step = 0           # which one is running, 1-based


def set_progress(on: bool, steps: int = 1) -> None:
    global _progress_on, _steps, _step
    _progress_on = bool(on)
    _steps = max(1, steps)
    _step = 0
    # Say the shape before doing any of it. The reader draws one segment per
    # pass, and without this it learns there are three only when the first
    # count arrives — so the bar is drawn once as a single segment and then
    # re-laid-out as three, a second into a ninety-second wait. A total of 0
    # is the honest opening position: the shape is known, the size of the
    # first pass is not. No label: the reader has its own opening words and
    # they are better than any this can supply before it has looked at
    # anything ("Nothing has changed yet", not "starting").
    progress(0, 0)


def begin_step() -> int:
    """Start the next pass. Called once per bar, before any of its work."""
    global _step
    _step += 1
    return _step


def progress(done: int, total: int, label: str = "") -> None:
    if not _progress_on:
        return
    sys.stderr.write(f"{PROGRESS} {done} {total} {max(_step, 1)} {_steps} {label}\n")
    sys.stderr.flush()


class Spinner:
    FRAMES = "|/-\\"

    def __init__(self, label: str, total: int = 0):
        self.label, self.n, self.total = label, 0, total
        self.on = sys.stderr.isatty()
        # Every caller of tick() is a thread pool. `self.n += 1` is a read, an
        # add and a write, and the interpreter can switch threads between any
        # two of them — so two workers read 14, both write 15, and one unit of
        # work is lost. Worse for the reader: each thread then *reports* the
        # count it happens to hold, so the bar goes 12, 18, 15 and jumps
        # backwards. Measured on a real run: one backwards jump in 56.
        self._lock = threading.Lock()
        begin_step()

    def tick(self) -> None:
        """One unit of fine-grained work; reported every few so it is not all
        cursor writes."""
        self._bump(every=3)

    def step(self) -> None:
        """One unit of coarse work — reported every time. A spinner that moves
        on every third of twenty-seven steps reads as a stuck spinner, which is
        worse than showing none at all."""
        self._bump(every=1)

    def _bump(self, every: int) -> None:
        # The count and the report are one critical section, not two. Bumping
        # under the lock and reporting outside it fixes the arithmetic and
        # leaves the ordering just as wrong.
        with self._lock:
            self.n += 1
            if self.n % every == 0:
                self._report()

    def _report(self) -> None:
        if self.on:
            f = self.FRAMES[self.n % len(self.FRAMES)]
            sys.stderr.write(f"\r{C.dim}{f} {self.label}… {self.n}{C.off}   ")
            sys.stderr.flush()
        else:
            progress(self.n, self.total, self.label)

    def done(self) -> None:
        if self.on:
            sys.stderr.write("\r" + " " * (len(self.label) + 24) + "\r")
            sys.stderr.flush()
        else:
            with self._lock:
                progress(self.total or self.n, self.total or self.n, self.label)


def die(msg: str, code: int = 2):
    print(f"{C.red}wt-manager: {msg}{C.off}", file=sys.stderr)
    sys.exit(code)


def bar(frac: float, width: int = 12) -> str:
    frac = max(0.0, min(1.0, frac))
    full = int(frac * width)
    rest = frac * width - full
    tip = "" if rest < 0.25 else ("." if rest < 0.75 else "|")
    return ("#" * full + tip).ljust(width)


def pr_cell(w: Worktree) -> str:
    if not w.pr:
        return ""
    p = w.pr
    bits = [f"#{p.number}"]
    if p.state == "MERGED":
        return " ".join(bits + ["merged"])
    if p.draft:
        bits.append("draft")
    if p.review == "CHANGES_REQUESTED":
        bits.append("changes")
    elif p.review == "APPROVED":
        bits.append("approved")
    if p.distinct_failing:
        shown = p.distinct_failing[0]
        extra = f"+{len(p.distinct_failing)-1}" if len(p.distinct_failing) > 1 else ""
        bits.append(f"x {shown[:22]}{extra}")
    elif p.endemic:
        bits.append(f"x{len(p.endemic)} repo-wide")
    elif p.checks == "pending":
        bits.append("...")
    elif p.checks == "none":
        bits.append("no ci")
    return " ".join(bits)


def active_account() -> str:
    rc, out, _ = sh(["gh", "api", "user", "--jq", ".login"], timeout=10)
    return out if rc == 0 and out else ""


def asked_accounts() -> str:
    """Who was asked, for the notice. Naming only the active account was the
    misleading part: it implied there was one, and the reader's next move was
    to go and switch it — which would have made the other half invisible
    instead."""
    logins = [login for login, _ in gh_accounts()]
    if not logins:
        return active_account()
    return ", ".join(logins)


def print_notices() -> None:
    if not NOTICES:
        return
    seen = list(dict.fromkeys(NOTICES))
    unseen = sorted({n[1] for n in seen if n[0] == "unseen"})
    other = [n for n in seen if n[0] != "unseen"]
    print()
    if unseen:
        who = asked_accounts()
        n = len(gh_accounts())
        listed = ", ".join(unseen[:5]) + ("…" if len(unseen) > 5 else "")
        which = "any signed-in GitHub account" if n > 1 else "the active GitHub account"
        print(f"{C.yellow}!{C.off} {C.dim}{len(unseen)} repos are not visible to "
              f"{which}{f' ({who})' if who else ''}: {listed}{C.off}")
        print(f"{C.dim}  their branches show local state only — "
              + ("`gh auth login` with an account that can see them."
                 if n > 1 else
                 "`gh auth login` to add the account that owns them.")
              + f"{C.off}")
    for _, repo, detail in other[:3]:
        print(f"{C.yellow}!{C.off} {C.dim}{repo}: {detail}{C.off}")
    if len(other) > 3:
        print(f"{C.dim}  …and {len(other)-3} more{C.off}")


def render_table(wts: List[Worktree], show_size: bool, multi_repo: bool) -> None:
    if not wts:
        print(f"{C.dim}nothing in flight.{C.off}")
        return

    rows = []
    for w in wts:
        delta = f"+{w.ahead}/-{w.behind}" if w.base != "(none)" else "?"
        dirty = "clean" if w.clean else f"{w.dirty}*"
        if w.unpushed > 0:
            dirty += f" {w.unpushed}^"
        rows.append({
            "g": GLYPH.get(w.status, "?"), "status": w.status,
            "repo": w.repo if multi_repo else "",
            "branch": w.name, "delta": delta, "dirty": dirty,
            "age": f"{w.age_days}d" if w.age_days < 9999 else "—",
            "pr": pr_cell(w),
            "size": human(w.size_kb) if show_size else "",
            "reclaim": human(w.reclaim_kb) if show_size and w.reclaim_kb > 0 else "",
        })

    def wid(k, lo=0):
        return max([lo] + [len(r[k]) for r in rows])

    w_status, w_repo = wid("status"), wid("repo")
    w_branch = min(max(wid("branch"), 6), 44)
    w_delta, w_age = wid("delta"), wid("age")
    w_dirty = max(wid("dirty"), len("*CHANGED ^UNPUSHED"))
    w_size, w_rec = wid("size"), wid("reclaim")

    # The column goes away entirely with one repo in view, header included.
    # A REPO heading over a column of blanks is a column that failed to fill,
    # and the two spaces it still reserved put a visible gutter mid-row.
    repo_hdr = f"{'REPO':<{w_repo}}  " if multi_repo else ""
    hdr = (f"  {'STATUS':<{w_status}}  {repo_hdr}{'BRANCH':<{w_branch}}  "
           f"{'±BASE':>{w_delta}}  {'*CHANGED ^UNPUSHED':<{w_dirty}}  {'AGE':>{w_age}}")
    if show_size:
        hdr += f"  {'SIZE':>{w_size}}  {'FREE':>{w_rec}}"
    hdr += "  PR"
    print(f"{C.dim}{hdr.rstrip()}{C.off}")

    for w, r in zip(wts, rows):
        col = COLOR.get(w.status, "")
        branch = r["branch"]
        if len(branch) > w_branch:
            branch = "…" + branch[-(w_branch - 1):]
        repo = f"{C.dim}{r['repo']:<{w_repo}}{C.off}  " if multi_repo else ""
        line = (f"{col}{r['g']} {r['status']:<{w_status}}{C.off}  "
                f"{repo}"
                f"{branch:<{w_branch}}  "
                f"{C.dim}{r['delta']:>{w_delta}}{C.off}  "
                f"{r['dirty']:<{w_dirty}}  "
                f"{C.dim}{r['age']:>{w_age}}{C.off}")
        if show_size:
            line += f"  {r['size']:>{w_size}}  {C.green}{r['reclaim']:>{w_rec}}{C.off}"
        if r["pr"]:
            line += f"  {C.dim}{r['pr']}{C.off}"
        print(line.rstrip())

    counts = Counter(w.status for w in wts)
    summary = "  ".join(
        f"{COLOR.get(s,'')}{counts[s]} {s}{C.off}" for s in ORDER if counts.get(s)
    )
    print(f"\n{summary}")
    hint = next((f"{MEANING[s]} — {counts[s]} of them" for s in (BLOCKED, REVIEW, STALE)
                 if counts.get(s)), None)
    if hint:
        print(f"{C.dim}{hint}{C.off}")
    print_notices()


def render_size(wts: List[Worktree], detailed: bool = True) -> None:
    sized = [w for w in wts if w.size_kb > 0]
    if not sized:
        print(f"{C.dim}nothing measurable.{C.off}")
        return
    sized.sort(key=lambda w: -w.size_kb)
    total = sum(w.size_kb for w in sized)
    reclaim_total = sum(max(w.reclaim_kb, 0) for w in sized)
    biggest = sized[0].size_kb

    w_repo = max(len(w.repo) for w in sized)
    w_br = min(max(len(w.name) for w in sized), 38)
    print(f"{C.dim}  {'REPO':<{w_repo}}  {'BRANCH':<{w_br}}  {'SIZE':>7}  "
          f"{'RECLAIMABLE':>11}  {'STATUS':<8}{C.off}")
    for w in sized:
        name = w.name if len(w.name) <= w_br else "…" + w.name[-(w_br - 1):]
        frac = w.size_kb / biggest if biggest else 0
        rec = human(w.reclaim_kb) if w.reclaim_kb > 0 else ("" if detailed else "—")
        pct = f"{100*w.reclaim_kb/w.size_kb:.0f}%" if w.reclaim_kb > 0 and w.size_kb else ""
        print(f"  {C.dim}{w.repo:<{w_repo}}{C.off}  {name:<{w_br}}  "
              f"{human(w.size_kb):>7}  {C.green}{rec:>7}{C.off} {C.dim}{pct:>3}{C.off}  "
              f"{COLOR.get(w.status,'')}{w.status:<8}{C.off} {C.dim}{bar(frac)}{C.off}")

    tail = (f"{C.green}{human(reclaim_total)} reclaimable{C.off} "
            f"{C.dim}({100*reclaim_total/total:.0f}%){C.off}" if detailed
            else f"{C.dim}reclaimable not measured (--fast){C.off}")
    print(f"\n  {C.bold}{human(total)}{C.off} across {len(sized)} worktrees   {tail}")

    reapable = [w for w in sized if w.status in (MERGED, EMPTY)]
    if reapable:
        kb = sum(w.size_kb for w in reapable)
        print(f"  {C.dim}{len(reapable)} finished worktrees hold {human(kb)} — "
              f"preview eligibility with `wt-manager reap`{C.off}")
    precious = sorted({p for w in sized for p in w.precious_hits})
    if precious:
        shown = ", ".join(precious[:4]) + ("…" if len(precious) > 4 else "")
        print(f"  {C.dim}protected from cleanup: {shown}{C.off}")
    unknown = sorted({p for w in sized for p in w.unknown_paths})
    if unknown:
        print(f"  {C.dim}{len(unknown)} ignored paths not recognised either way "
              f"(left alone; `wt-manager clean --list-unknown` to see them){C.off}")
    print_notices()


# ─────────────────────────────────────────────────────────────────────────────
# Verbs that write
#
# Two rules, both absolute:
#   1. Never remove a worktree by deleting its directory tree directly.
#      `git worktree remove` keeps git's own metadata consistent; deleting the
#      tree by hand leaves a registration pointing at nothing, and a repo that
#      needs pruning before it makes sense again.
#   2. Never delete an ignored path we have not affirmatively recognised.
#      Unknown stays on disk. The cost of a wrong guess is unrecoverable.
# ─────────────────────────────────────────────────────────────────────────────

def only(wts: List[Worktree], args) -> List[Worktree]:
    """Narrow to the paths asked for, matched exactly after resolving symlinks.

    A substring match here would be a quiet way to delete the wrong thing when
    one worktree's path is a prefix of another's.
    """
    wanted = getattr(args, "path", None)
    if not wanted:
        return wts
    canon = {os.path.realpath(os.path.expanduser(p)) for p in wanted}
    return [w for w in wts if os.path.realpath(w.path) in canon]


def ignored_by_kind(w: Worktree) -> Tuple[List[str], List[str]]:
    """(precious, unknown) ignored paths in a worktree, read now if not already.

    `reap` removes the whole directory, ignored files included - and
    `git worktree remove` does that without --force, because ignored files are
    not "untracked" to it. So the classifier that protects `.env` from `clean`
    has to be consulted here too, or the verb that deletes the most is the one
    verb that never looked.
    """
    if not w.ignored_scanned and not (w.precious_hits or w.unknown_paths or w.reclaim_paths):
        for entry in ignored_entries(w.path):
            record_ignored(w, entry)
    w.ignored_scanned = True
    return w.precious_hits, w.unknown_paths


def plan_hash(kind: str, items: Sequence[str]) -> str:
    """The identity of a plan: what it would touch, and nothing else.

    The confirm sheet approves a *set*, not a filter. Re-running the filter
    at commit time would delete whatever had entered scope since the preview
    - a dist/ a build just wrote, a worktree whose status flipped - without
    it ever having been shown. So a preview carries this hash, the commit
    presents it back, and a mismatch is refused: review again, delete nothing.
    """
    h = hashlib.sha1(kind.encode())
    for item in sorted(items):
        h.update(b"\0" + item.encode("utf-8", "surrogateescape"))
    return h.hexdigest()[:20]


def with_plan_json(kind: str, args, body) -> int:
    """Run a verb, and with --json wrap its text in a machine-readable plan."""
    if not getattr(args, "json", False):
        return body({})
    plan: dict = {}
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = body(plan)
    plan.update(kind=kind, text=buf.getvalue(), rc=rc)
    plan.setdefault("paths", [])
    plan.setdefault("plan", plan_hash(kind, []))
    print(json.dumps(plan))
    return rc


def plan_mismatch(kind: str, args, actual: str) -> bool:
    """True, having said so, when the commit's plan is not the one reviewed.

    Asked as soon as the set is known, and before anything is said about it —
    including before "nothing to do". A set that has *emptied* since the
    preview is precisely the case this hash exists to catch: something else
    removed what was approved, and answering rc=0 there tells the caller its
    own plan went through.
    """
    if not getattr(args, "yes", False):
        return False                     # a dry run commits nothing to compare
    wanted = getattr(args, "plan", None)
    if not wanted or wanted == actual:
        return False
    did = {"reap": "removed", "push": "pushed"}.get(kind, "deleted")
    print(f"{C.red}the plan changed since it was reviewed — nothing {did}.{C.off} "
          f"{C.dim}review it again.{C.off}")
    return True


KEEP_UNKNOWN_KB = 100 * 1024    # past this, unclassified files are refused, not copied


def kept_root() -> Path:
    """Where `reap` sets aside the files git cannot give back.

    Not the cache: `config --clear-cache` removes every file there, and the
    copies in here may be the only ones.
    """
    base = os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")
    return Path(base) / "wt-manager" / "kept"


def verify_copy(src: str, dst: str) -> bool:
    """Verify every file byte and link target; refuse unsupported file kinds."""
    import stat
    source_mode, dest_mode = os.lstat(src).st_mode, os.lstat(dst).st_mode
    if stat.S_IFMT(source_mode) != stat.S_IFMT(dest_mode):
        return False
    if stat.S_ISLNK(source_mode):
        return os.readlink(src) == os.readlink(dst)
    if stat.S_ISDIR(source_mode):
        source_names, dest_names = set(os.listdir(src)), set(os.listdir(dst))
        return source_names == dest_names and all(
            verify_copy(os.path.join(src, name), os.path.join(dst, name))
            for name in source_names)
    if stat.S_ISREG(source_mode):
        # Do not use filecmp's metadata cache: unchanged size/mtime is not
        # evidence of unchanged contents, especially during a concurrent write.
        with open(src, "rb") as original, open(dst, "rb") as copied:
            while True:
                left, right = original.read(1024 * 1024), copied.read(1024 * 1024)
                if left != right:
                    return False
                if not left:
                    return True
    return False


def keep_precious(w: Worktree, entries: Sequence[str], on_progress=None) -> Tuple[Optional[Path], str]:
    """Copy precious and unclassified paths out of a worktree before it goes.
    Returns (where, error).

    This is what makes `reap` able to act at all. Measured here: all thirteen
    finished worktrees held a `.env.local`, every copy different, so refusing
    them was correct and left the verb with nothing it would ever remove. The
    files are not the reason to keep the worktree; they are the reason to keep
    the files. Every copy is compared byte for byte before anything is removed.
    """
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", w.name).strip("-") or "worktree"
    root = kept_root()
    dest = root / w.repo / f"{slug}-{time.strftime('%Y%m%d-%H%M%S')}"
    n = 1
    while dest.exists():
        n += 1
        dest = dest.with_name(f"{dest.name.rsplit('~', 1)[0]}~{n}")
    # `dist/.env` is listed beside `dist/` when the folder is kept too; the
    # folder's copy already holds it.
    rels = sorted({e.rstrip("/") for e in entries})
    rels = [r for r in rels if not any(r.startswith(o + "/") for o in rels if o != r)]
    try:
        dest.mkdir(parents=True)
        for d in (root, dest):
            os.chmod(d, 0o700)      # these are secrets; nobody else reads them
        for kept_count, rel in enumerate(rels):
            if on_progress:
                on_progress(kept_count, len(rels))
            src, dst = os.path.join(w.path, rel), dest / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if os.path.islink(src):
                os.symlink(os.readlink(src), dst)
            elif os.path.isdir(src):
                shutil.copytree(src, dst, symlinks=True)
            else:
                shutil.copy2(src, dst)
            if not verify_copy(src, str(dst)):
                raise OSError(f"{rel} did not copy exactly")
        (dest / "FROM.txt").write_text(
            f"worktree: {w.path}\nbranch: {w.name}\n"
            f"kept: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    except OSError as e:
        return None, str(e)
    return dest, ""


def finished(w: Worktree) -> bool:
    return w.status in (MERGED, EMPTY) or (w.pr is not None and w.pr.state == "MERGED")


def reap_blocker(w: Worktree, force: bool = False, discard_unknown: bool = False,
                 inspect: bool = False) -> Optional[Tuple[str, str]]:
    """One eligibility policy for the app, preview, and execution."""
    if w.primary:
        return "the repo's main checkout — git cannot remove it", ""
    if w.is_base:
        return f"the checkout of {w.base} itself", ""
    if w.locked:
        return f"worktree is locked: {w.locked} — unlock it in Terminal first", ""
    if not finished(w):
        return f"{w.status} — only finished work is removed", ""
    if w.base_source == "unresolved" or w.base == "(none)":
        return "no base resolved — cannot confirm it landed", ""
    if w.would_lose > 0 and not force:
        return f"{w.would_lose} uncommitted", "--force"
    if w.unpushed > 0 and not w.landed and not force:
        return f"{w.unpushed} unpushed", "--force"
    if w.has_submodules and not force:
        return "contains submodules — review and remove explicitly in Terminal", "--force"
    if inspect:
        try:
            ignored_by_kind(w)
        except OSError as e:
            return str(e), ""
    if w.ignored_scanned and w.unknown_paths and not discard_unknown:
        if inspect:
            sizes = [du_kb(os.path.join(w.path, e.rstrip("/")), cache=False)
                     for e in w.unknown_paths]
            w.unknown_kb = sum(sizes) if all(k >= 0 for k in sizes) else -1
        if w.unknown_kb < 0:
            return "cannot measure unclassified files safely", ""
        if w.unknown_kb > KEEP_UNKNOWN_KB:
            shown = ", ".join(w.unknown_paths[:3]) + ("…" if len(w.unknown_paths) > 3 else "")
            return (f"holds {human(w.unknown_kb)} of unclassified ignored files, too much "
                    f"to set aside: {shown}", "--discard-unknown")
    return None


def removal_info(w: Worktree) -> dict:
    blocker = reap_blocker(w)
    if blocker:
        return {"state": "blocked", "reason": blocker[0]}
    if not w.ignored_scanned:
        return {"state": "check", "reason": "Local files need checking before removal"}
    return {"state": "ready", "reason": "Protected and small unclassified files will be archived first"}


def cmd_reap(wts: List[Worktree], args) -> int:
    return with_plan_json("reap", args, lambda plan: _reap(wts, args, plan))


def _reap(wts: List[Worktree], args, plan: dict) -> int:
    wts = only(wts, args)
    # Whether the caller named these worktrees. When they did, every refusal
    # is worth a sentence: they pointed at one thing and asked, and "nothing
    # to reap" as the only answer reads as the tool having done nothing.
    named = bool(getattr(args, "path", None))
    cands, skipped = [], []
    discard = bool(getattr(args, "discard_precious", False))
    discard_unknown = bool(getattr(args, "discard_unknown", False))
    begin_step()
    for i, w in enumerate(wts):
        progress(i, len(wts), f"checking safety of {w.repo}/{w.name}")
        blocker = reap_blocker(w, force=args.force, discard_unknown=discard_unknown, inspect=True)
        if blocker:
            if named or finished(w):
                skipped.append((w, blocker[0], blocker[1]))
            continue
        cands.append(w)
    progress(len(wts), len(wts), "safety checks complete")

    for w, why, flag in skipped:
        over = f" — {flag} overrides" if flag else ""
        print(f"{C.yellow}skip{C.off} {w.repo}/{w.name} {C.dim}({why}{over}){C.off}")
    plan["skipped"] = [{"path": w.path, "repo": w.repo, "name": w.name, "why": why,
                        "override": flag} for w, why, flag in skipped]
    plan["paths"] = [w.path for w in cands]
    # An override approves the ignored files too. If one appears after the
    # preview, the same worktree path must no longer authorise its removal.
    # Keeping and discarding are different plans over the same set, so the
    # hash says which: a preview that set files aside must not approve a run
    # that deletes them.
    plan["plan"] = plan_hash("reap", [
        f"{w.path}\t{','.join(sorted(w.precious_hits))}\t{','.join(sorted(w.unknown_paths))}"
        f"\t{'discard' if discard else 'keep'}\t{'discard' if discard_unknown else 'keep'}"
        for w in cands])
    plan["precious"] = {w.path: list(w.precious_hits) for w in cands if w.precious_hits}
    plan["unknown"] = {w.path: list(w.unknown_paths) for w in cands if w.unknown_paths}
    plan["keeps_unknown"] = bool(plan["unknown"]) and not discard_unknown
    # Where the precious files go; empty when they are discarded instead.
    plan["kept_in"] = str(kept_root()) if plan["precious"] and not discard else ""
    plan["count"] = len(cands)
    plan["kb"] = sum(w.size_kb for w in cands if w.size_kb > 0)
    if plan_mismatch("reap", args, plan["plan"]):
        return 3
    if not cands:
        print(f"{C.dim}nothing to reap.{C.off}")
        return 0

    total = plan["kb"]
    for w in cands:
        print(f"  {C.dim}{w.repo:<16}{C.off} {w.name:<40} "
              f"{COLOR.get(w.status,'')}{w.status}{C.off} {C.dim}{human(w.size_kb)}{C.off}")
        if w.deleted:
            # Said, because "--force" is about to be passed for it.
            print(f"           {C.dim}{w.deleted} deleted tracked file"
                  f"{'s' if w.deleted != 1 else ''} — git still has "
                  f"{'them' if w.deleted != 1 else 'it'}, nothing to lose{C.off}")
        precious, unknown = ignored_by_kind(w)
        if precious and discard:
            # Said once more, right above the number, because this is the line
            # that is about to go.
            print(f"           {C.red}discarding{C.off} {C.dim}{', '.join(precious[:5])}{C.off}")
        elif precious:
            shown = ", ".join(precious[:3]) + ("…" if len(precious) > 3 else "")
            print(f"           {C.cyan}keeping{C.off} {C.dim}{shown} — set aside first{C.off}")
        if unknown:
            shown = ", ".join(unknown[:4]) + ("…" if len(unknown) > 4 else "")
            verb = f"{C.yellow}discarding{C.off}" if discard_unknown else f"{C.cyan}keeping{C.off}"
            print(f"           {verb} {len(unknown)} unclassified ignored path"
                  f"{'s' if len(unknown) != 1 else ''} not recognised as build output: {shown}{C.off}")
    print(f"\n{len(cands)} worktrees" + (f", {human(total)}" if total > 0 else ""))
    if plan["kept_in"] or plan["keeps_unknown"]:
        print(f"{C.dim}files git cannot give back are copied to {kept_root()} "
              f"first — --discard-precious and --discard-unknown delete them instead{C.off}")

    if not args.yes:
        print(f"{C.dim}dry run — add --yes to remove them{C.off}")
        return 0

    begin_step()
    removed, failed, freed = 0, 0, 0
    completed = []
    for i, w in enumerate(cands):
        progress(i, len(cands), f"removing {w.repo}/{w.name}")
        keep = (([] if discard else w.precious_hits)
                + ([] if discard_unknown else w.unknown_paths))
        archived_kb = 0
        if keep:
            kept, err = keep_precious(w, keep, on_progress=lambda n, total: progress(
                i, len(cands), f"preserving {w.repo}/{w.name}: {n} of {total} paths"))
            if kept is None:
                # Not one file is worth guessing about: the worktree stays.
                failed += 1
                print(f"{C.red}failed{C.off}  {w.repo}/{w.name} "
                      f"{C.dim}could not set its files aside, so it was left: {err[:90]}{C.off}")
                continue
            archived_kb = max(du_kb(str(kept), cache=False), 0)
            progress(i, len(cands), f"removing {w.repo}/{w.name}")
            print(f"{C.cyan}kept{C.off}    {w.repo}/{w.name} {C.dim}{len(keep)} "
                  f"path{'s' if len(keep) != 1 else ''} in {kept}{C.off}")
        cd = common_dir(w.path) or ""
        # Git refuses a worktree with deleted tracked files without --force,
        # though every one of them is still in git. Only when nothing else is
        # uncommitted, and ignored files were already set aside above.
        forced = args.force or (w.deleted > 0 and w.would_lose == 0)
        cmd = ["worktree", "remove", w.path] + (["--force"] if forced else [])
        rc, _, err = git(cmd, gitdir=cd or None, cwd=None if cd else w.path)
        if rc == 0:
            removed += 1
            completed.append(w.path)
            freed += max(w.size_kb - archived_kb, 0)
            forget_size(w.path)
            print(f"{C.green}removed{C.off} {w.repo}/{w.name}")
        else:
            failed += 1
            print(f"{C.red}failed{C.off}  {w.repo}/{w.name} {C.dim}{err[:90]}{C.off}")
    progress(len(cands), len(cands), "")
    save_size_cache()
    plan.update(done=True, removed=removed, failed=failed, freed_kb=freed, completed_paths=completed)
    print(f"\n{removed} removed" + (f", {failed} failed" if failed else "")
          + (f", {human(freed)} returned" if removed and total > 0 else ""))
    return 1 if failed else 0


def inside(root: str, candidate: str) -> bool:
    """True only if `candidate` really lives under `root`.

    Delete paths are built from git output, so they should always be relative and
    contained. "Should" is not a property you rely on in code that removes files.
    """
    try:
        r = os.path.realpath(root)
        c = os.path.realpath(candidate)
    except OSError:
        return False
    return c != r and (c + os.sep).startswith(r + os.sep)


def cmd_clean(wts: List[Worktree], args) -> int:
    return with_plan_json("clean", args, lambda plan: _clean(wts, args, plan))


def _clean(wts: List[Worktree], args, plan: dict) -> int:
    if args.list_unknown:
        seen = sorted({p for w in wts for p in w.unknown_paths})
        if not seen:
            print(f"{C.dim}every ignored path was recognised.{C.off}")
            return 0
        print(f"{C.dim}ignored, but not recognised as regenerable or precious.\n"
              f"left alone. add to 'regenerable' or 'precious' in "
              f"{config_path()} to classify.{C.off}\n")
        for p in seen:
            print(f"  {p}")
        return 0

    wts = only(wts, args)
    targets = []
    for w in wts:
        if args.stale and w.status not in (STALE, MERGED, EMPTY):
            continue
        if w.reclaim_kb > 0 and w.reclaim_paths:
            targets.append(w)
    targets.sort(key=lambda w: -w.reclaim_kb)
    plan["paths"] = [w.path for w in targets]
    plan["plan"] = plan_hash("clean", [f"{w.path}\t{rel}" for w in targets
                                       for rel in w.reclaim_paths])
    plan["entries"] = {w.path: list(w.reclaim_paths) for w in targets}
    plan["precious"] = {w.path: list(w.precious_hits) for w in targets if w.precious_hits}
    plan["count"] = len(targets)
    plan["kb"] = sum(w.reclaim_kb for w in targets)

    if plan_mismatch("clean", args, plan["plan"]):
        return 3
    if not targets:
        print(f"{C.dim}nothing reclaimable under that filter.{C.off}")
        return 0

    total = plan["kb"]
    for w in targets:
        print(f"  {C.green}{human(w.reclaim_kb):>7}{C.off}  {C.dim}{w.repo:<14}{C.off} "
              f"{w.name:<38} {COLOR.get(w.status,'')}{w.status}{C.off}")
        if args.verbose:
            for p in w.reclaim_paths:
                print(f"           {C.dim}{p}{C.off}")
        if w.precious_hits:
            print(f"           {C.yellow}keeping{C.off} {C.dim}"
                  f"{', '.join(w.precious_hits[:5])}{C.off}")

    print(f"\n{C.green}{human(total)}{C.off} reclaimable from {len(targets)} worktrees")
    protected = sorted({p for w in targets for p in w.precious_hits})
    if protected:
        print(f"{C.dim}never touched: {', '.join(protected[:6])}"
              f"{'…' if len(protected) > 6 else ''}{C.off}")

    if not args.yes:
        print(f"{C.dim}dry run — add --yes to delete. "
              f"everything listed is reproducible by a build or install.{C.off}")
        return 0

    begin_step()
    freed, failed = 0, 0
    completed = []
    for i, w in enumerate(targets):
        row_failed = False
        progress(i, len(targets), f"cleaning {w.repo}/{w.name}")
        for rel in w.reclaim_paths:
            full = os.path.join(w.path, rel)
            if classify_ignored(rel, w.path) != SAFE:      # belt and braces
                failed += 1
                row_failed = True
                print(f"failed {w.repo}/{w.name}: {rel} is no longer safe build output")
                continue
            if not inside(w.path, full):
                print(f"failed {w.repo}/{w.name}: {full} is outside the worktree")
                failed += 1
                row_failed = True
                continue
            if not os.path.exists(full):
                continue
            kb = du_kb(full, timeout=60)
            try:
                if os.path.isdir(full) and not os.path.islink(full):
                    shutil.rmtree(full)
                else:
                    os.remove(full)
                freed += max(kb, 0)
                forget_size(full)
                forget_size(w.path)
            except OSError as e:
                failed += 1
                row_failed = True
                print(f"failed {w.repo}/{w.name}: could not remove {rel}: {e}")
        if not row_failed:
            completed.append(w.path)
            print(f"{C.green}cleaned{C.off} {w.repo}/{w.name}")
    progress(len(targets), len(targets), "")
    save_size_cache()
    plan.update(done=True, freed_kb=freed, failed=failed, completed_paths=completed)
    print(f"\n{C.bold}{human(freed)}{C.off} returned"
          + (f", {failed} failures" if failed else ""))
    return 1 if failed else 0


def worktree_remote(path: str, branch: Optional[str]) -> Optional[str]:
    """Where this branch would push to, asked rather than assumed.

    `origin` is the usual answer and not the only one: a fork checkout often
    pushes to `fork`, and guessing sends someone's work to the repo they were
    careful not to write to.
    """
    if not branch:
        return None
    rc, out, _ = git(["config", "--get", f"branch.{branch}.pushRemote"], cwd=path)
    if rc == 0 and out.strip():
        return out.strip()
    rc, out, _ = git(["config", "--get", "remote.pushDefault"], cwd=path)
    if rc == 0 and out.strip():
        return out.strip()
    rc, out, _ = git(["config", "--get", f"branch.{branch}.remote"], cwd=path)
    if rc == 0 and out.strip():
        return out.strip()
    rc, out, _ = git(["remote"], cwd=path)
    remotes = out.split() if rc == 0 else []
    return "origin" if "origin" in remotes else (remotes[0] if remotes else None)


def cmd_push(wts: List[Worktree], args) -> int:
    return with_plan_json("push", args, lambda plan: _push(wts, args, plan))


def _push(wts: List[Worktree], args, plan: dict) -> int:
    """Send commits that exist only on this machine to their remote.

    The one verb here that *creates* rather than removes, and the answer to a
    question the tool had been raising and dropping: it counted the commits
    that exist nowhere else, put the number on a card headed AT RISK, and
    offered nothing but two ways to delete things.

    It writes to a remote, which nothing else here does, so it is scoped hard:
    named worktrees only, never a sweep, and the plan hash is checked like any
    other. Nothing is rewritten, nothing is forced, and a branch with no
    remote is refused rather than guessed at.
    """
    wts = only(wts, args)
    if not getattr(args, "path", None):
        die("push needs --path: it writes to a remote, so it is never a sweep.\n"
            "       `wt-manager --json` lists every worktree and its path.")
    cands, skipped = [], []
    for w in wts:
        if not w.branch:
            skipped.append((w, "detached HEAD — no branch to push", ""))
            continue
        if w.unpushed <= 0:
            skipped.append((w, "every commit here is already on a remote", ""))
            continue
        remote = worktree_remote(w.path, w.branch)
        if not remote:
            skipped.append((w, "no remote configured", ""))
            continue
        cands.append((w, remote, git(["rev-parse", "HEAD"], cwd=w.path)[1].strip()))

    for w, why, flag in skipped:
        print(f"{C.yellow}skip{C.off} {w.repo}/{w.name} {C.dim}({why}){C.off}")
    plan["skipped"] = [{"path": w.path, "repo": w.repo, "name": w.name, "why": why,
                        "override": flag} for w, why, flag in skipped]
    plan["paths"] = [w.path for w, _, _ in cands]
    # The commit, not the count. Amending leaves the count at one and changes
    # everything about what would be sent, so a hash over `unpushed` would
    # approve a preview of the commit you replaced.
    plan["plan"] = plan_hash("push", [f"{w.path}\t{r}\t{head}" for w, r, head in cands])
    plan["count"] = len(cands)
    plan["commits"] = sum(w.unpushed for w, _, _ in cands)
    # Said as data too, because the app draws it and the sentence below is the
    # only place a terminal reader sees it.
    plan["still_local"] = {w.path: w.dirty for w, _, _ in cands if w.dirty}

    if plan_mismatch("push", args, plan["plan"]):
        return 3
    if not cands:
        print(f"{C.dim}nothing to push.{C.off}")
        return 0

    for w, remote, _ in cands:
        print(f"  {C.dim}{w.repo:<16}{C.off} {w.name:<38} "
              f"{C.green}{w.unpushed} commit{'s' if w.unpushed != 1 else ''}{C.off} "
              f"{C.dim}-> {remote}{C.off}")
        for subject in w.solo_log[:5]:
            print(f"           {C.dim}{subject}{C.off}")
        if w.unpushed > len(w.solo_log):
            print(f"           {C.dim}…and {w.unpushed - len(w.solo_log)} more{C.off}")
        if w.dirty:
            # The honest half. A person reading "pushed" takes it to mean
            # "safe", and uncommitted files are exactly what it does not
            # cover - they are also the larger half of what is at stake here.
            print(f"           {C.yellow}{w.dirty} uncommitted file"
                  f"{'s' if w.dirty != 1 else ''} stay on this machine{C.off}")

    print(f"\n{plan['commits']} commit{'s' if plan['commits'] != 1 else ''} from {len(cands)} "
          f"branch{'es' if len(cands) != 1 else ''}")
    if not args.yes:
        print(f"{C.dim}dry run — add --yes to push. nothing is forced, and "
              f"nothing already on a remote is rewritten.{C.off}")
        return 0

    begin_step()
    pushed, failed = 0, 0
    for i, (w, remote, _) in enumerate(cands):
        progress(i, len(cands), f"pushing {w.repo}/{w.name}")
        rc, _, err = git(["push", "--set-upstream", remote, w.branch],
                         cwd=w.path, timeout=180)
        if rc == 0:
            pushed += 1
            print(f"{C.green}pushed{C.off}  {w.repo}/{w.name} {C.dim}-> {remote}{C.off}")
        else:
            failed += 1
            print(f"{C.red}failed{C.off}  {w.repo}/{w.name} {C.dim}{err.strip()[:110]}{C.off}")
    progress(len(cands), len(cands), "")
    plan.update(done=True, pushed=pushed, failed=failed)
    print(f"\n{pushed} pushed" + (f", {failed} failed" if failed else ""))
    return 1 if failed else 0


def cmd_doctor(wts: List[Worktree]) -> int:
    """Show how each repo's base was resolved. A base you can see is correctable."""
    by_repo: Dict[str, List[Worktree]] = {}
    for w in wts:
        by_repo.setdefault(w.repo, []).append(w)
    print(f"{C.dim}how each repo's base branch was resolved{C.off}\n")
    for repo in sorted(by_repo):
        ws = by_repo[repo]
        # The repo's base is what a branch without a PR is measured against;
        # a branch with one is measured against its target, counted below.
        repo_wide = [w for w in ws if w.base_source != "pr"] or ws
        base, src = repo_wide[0].base, repo_wide[0].base_source
        own = sum(1 for w in ws if w.base_source == "pr")
        note = {
            "config":      "pinned in your config",
            "upstream":    "the branch's own upstream",
            "origin/HEAD": "the remote's default branch",
            "guess":       "guessed — no default branch is set on the remote",
            "local":       "no remote — the repo's own main branch",
            "pr":          "every branch here has a PR — each measured against its target",
            "unresolved":  "NOT RESOLVED — ahead/behind and status are unreliable here",
        }.get(src, "")
        if src.startswith("prs("):
            n = src[4:-1]
            note = f"learned from {n} open PRs — outranks the default branch"
        colour = C.red if src in ("unresolved", "guess") else C.dim
        if own and src != "pr":
            note += f"; {own} with a PR measured against its target"
        print(f"  {repo:<30} {C.bold}{base or '—':<34}{C.off} "
              f"{colour}{src:<12}{C.off} {C.dim}{note}{C.off}")
    bad = [w for w in wts if w.base_source in ("unresolved", "guess")]
    if bad:
        print(f"\n{C.yellow}{len(bad)} worktrees have no trustworthy base.{C.off} "
              f"{C.dim}pin one per repo under \"base\" in {config_path()}{C.off}")

    # Who we can ask. This is the first thing to look at when a repo reports
    # no pull requests, and until it was printed the only way to find out was
    # to read the source.
    accts = gh_accounts()
    print()
    if not have("gh"):
        print(f"{C.dim}gh is not installed — every repo shows local state only.{C.off}")
    elif not accts:
        print(f"{C.dim}gh accounts: could not be listed (an older gh). Asking the "
              f"active account only.{C.off}")
    else:
        print(f"{C.dim}gh accounts, in the order each repo is tried:{C.off}")
        for i, (login, host) in enumerate(accts):
            mark = "active" if i == 0 else ""
            tok = "" if account_token((login, host)) else f"  {C.red}no token{C.off}"
            print(f"  {C.bold}{login:<20}{C.off} {C.dim}{host:<16}{mark}{C.off}{tok}")
        if len(accts) > 1:
            print(f"{C.dim}  a repo owned by one of these logins is tried under that "
                  f"account first.{C.off}")
    print_notices()
    return 0


def notice_lines() -> List[str]:
    """The tuples `NOTICES` collects, as sentences a reader can act on."""
    seen = list(dict.fromkeys(NOTICES))
    unseen = sorted({n[1] for n in seen if n[0] == "unseen"})
    out = []
    if unseen:
        who = asked_accounts()
        named = ", ".join(unseen[:6]) + ("\u2026" if len(unseen) > 6 else "")
        whose = " (%s)" % who if who else ""
        which = ("any signed-in GitHub account" if len(gh_accounts()) > 1
                 else "the active GitHub account")
        out.append("%d repos are not visible to %s%s: %s"
                   % (len(unseen), which, whose, named))
    for _, repo, detail in [n for n in seen if n[0] != "unseen"][:5]:
        out.append(f"{repo}: {detail}")
    return out


def cmd_unconfigured() -> int:
    """The envelope for a machine that has not been told where its repos are.

    A valid envelope and not an error, because "nobody has said yet" is a
    state the tool knows how to leave, and a window that renders `exited 2:
    not inside a git repository` has turned a first run into a fault report.
    The candidates ride along so the screen that asks the question arrives
    with the answer already in it.
    """
    sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
    import mascot
    face = mascot.face(reclaim_kb=0)
    for k in ("sprite", "frames", "mark_rows"):
        face.pop(k, None)
    found = discover_roots()
    print(json.dumps({
        "version": 1,
        "generated_at": int(time.time()),
        "unconfigured": True,
        "candidates": [{"root": r, "repos": n} for r, n in found],
        "roots": [],
        "config_path": str(config_path()),
        "counts": {}, "reclaim_kb": 0, "total_kb": 0, "measured_disk": False,
        "notices": [], "insights": [], "worktrees": [],
        "headline": "Tell me where your repos are",
        "face": {k: face[k] for k in ("mood", "meaning", "eyes", "tint",
                                      "tint_name", "bob", "gauge", "mark")},
    }))
    return 0


def cmd_agent(wts: List[Worktree], args) -> int:
    """One envelope with everything an ambient client needs, mood included.

    The face is computed here rather than in whatever draws it, for the same
    reason the page's headline is: a second implementation of the precedence
    rule would disagree with this one the first time either learned a new case,
    and a mascot that contradicts the menu beneath it is worse than no mascot.
    """
    sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
    import mascot

    counts: Dict[str, int] = {}
    for w in wts:
        counts[w.status] = counts.get(w.status, 0) + 1
    reclaim = sum(w.reclaim_kb for w in wts if w.reclaim_kb > 0)
    total = sum(w.size_kb for w in wts if w.size_kb > 0)
    if not reclaim and getattr(args, "reclaim_kb", None):
        reclaim = args.reclaim_kb
    ungrounded = sum(1 for w in wts if w.base_source in ("unresolved", "guess"))
    share = ungrounded / len(wts) if wts else 0.0

    face = mascot.face(blocked=counts.get("blocked", 0), review=counts.get("review", 0),
                       stale=counts.get("stale", 0), active=counts.get("active", 0),
                       waiting=counts.get("waiting", 0), draft=counts.get("draft", 0),
                       reclaim_kb=reclaim, untrusted_share=share)
    face.pop("sprite", None)          # the client holds the art already
    face.pop("frames", None)
    face.pop("mark_rows", None)

    print(json.dumps({
        "version": 1,
        "generated_at": int(time.time()),
        "counts": counts,
        "reclaim_kb": reclaim,
        "total_kb": total,
        "measured_disk": any(w.size_kb > 0 for w in wts),
        "notices": notice_lines(),
        "roots": load_config().get("roots", []),
        # The sentence, decided here beside the mood it is derived from. A
        # client that wrote its own would rank the same facts a second time.
        "headline": mascot.headline(face["mood"], counts, reclaim, len(wts)),
        # One fact per tag; the headline is the state only. Same source as the
        # page, so the two never disagree about what is worth pointing at.
        "insights": mascot.insights(
            counts, reclaim, sum(w.unpushed_mine for w in wts),
            finished=counts.get(MERGED, 0) + counts.get(EMPTY, 0),
            unreadable=len({n[1] for n in NOTICES if n[0] == "unseen"})),
        "face": {k: face[k] for k in ("mood", "meaning", "eyes", "tint",
                                      "tint_name", "bob", "gauge", "mark")},
        "worktrees": [
            {"repo": w.repo, "repo_id": w.repo_id, "branch": w.branch, "status": w.status,
             "meaning": MEANING.get(w.status, ""), "path": w.path,
             "ahead": w.ahead, "behind": w.behind, "dirty": w.dirty,
             "deleted": w.deleted,
             "unpushed": w.unpushed, "unpushed_mine": w.unpushed_mine,
             "solo_log": w.solo_log,
             "age_days": w.age_days,
             "last_commit": w.last_commit, "base": w.base,
             "base_source": w.base_source, "primary": w.primary, "removal": removal_info(w),
             # Both of the reasons `git worktree remove` will always refuse.
             # A client that does not know them offers a button that cannot
             # work and reports "nothing to do" when it is pressed.
             "is_base": w.is_base,
             "size_kb": w.size_kb, "reclaim_kb": w.reclaim_kb,
             "pr": (asdict(w.pr) if w.pr else None)}
            for w in wts],
    }))
    return 0


def cmd_config(args) -> int:
    p = config_path()
    if getattr(args, "clear_roots", False):
        written = write_roots([])
        print(f"roots cleared in {written}")
        return 0
    if getattr(args, "clear_cache", False):
        files, size = clear_cache()
        print(f"removed {files} cache file{'s' if files != 1 else ''} "
              f"({human(size // 1024)}) from {cache_dir()}")
        print(f"{C.dim}config at {p} was not touched.{C.off}")
        return 0
    if getattr(args, "roots", None):
        written = write_roots(args.roots)
        print(f"roots set in {written}")
        for r in load_config().get("roots", []):
            print(f"  {r}")
        return 0
    if args.init:
        if p.exists() and not args.force:
            die(f"{p} already exists (use --force to overwrite)")
        # Found, not guessed. This used to write `~/dev` whatever was on the
        # machine, so a laptop that keeps its code anywhere else got a config
        # naming a folder that did not exist and a sentence telling it to fix
        # the thing it had just been handed.
        found = discover_roots()
        write_roots([r for r, _ in found])
        print(f"wrote {p}")
        if found:
            for root, n in found:
                print(f"  {root}  {C.dim}{n} repo{'s' if n != 1 else ''}{C.off}")
            print(f"{C.dim}run `wt-manager` from anywhere.{C.off}")
        else:
            print(f"{C.dim}no repositories found in the usual places. add the "
                  f"directories holding yours to \"roots\", or run "
                  f"`wt-manager config --roots ~/where/they/are`.{C.off}")
        return 0
    print(f"{C.dim}# {p}{'' if p.exists() else '  (not created yet)'}{C.off}")
    print(json.dumps(load_config(), indent=2))
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# Entry
# ─────────────────────────────────────────────────────────────────────────────

HIDDEN_BY_DEFAULT = (MERGED, EMPTY, TRUNK)

EPILOG = """\
examples
  wt-manager                     what is in flight, here or everywhere
  wt-manager --all               include finished, empty and trunk
  wt-manager size                disk held per worktree, and what is reclaimable
  wt-manager clean --stale       free build output from forgotten work (dry run)
  wt-manager clean --stale --yes and actually free it
  wt-manager reap                list finished worktrees; --yes removes them
  wt-manager push --path P       send commits that exist only on this machine
  wt-manager doctor              show how each repo's base branch was resolved
  wt-manager config --init       scan every repo under a set of roots

wt-manager never fetches, never writes to a repo except through `git worktree remove`,
and never deletes an ignored file it does not recognise as reproducible.
"""


def add_global_flags(p: argparse.ArgumentParser, after_verb: bool = False) -> None:
    """The flags that mean the same thing wherever they appear on the line.

    Added once to the top parser with real defaults, and again to every
    subparser with `SUPPRESS`. Without the second copy argparse rejects
    `wt-manager clean --json` outright — flags declared before `add_subparsers`
    are simply not accepted after the verb — and "clean, as JSON" is the order
    almost everyone types. `SUPPRESS` is what makes the second copy safe: it
    leaves the attribute unset when the flag is absent, so a subparser can no
    longer overwrite a value given *before* the verb with its own default.
    """
    d = dict(default=argparse.SUPPRESS) if after_verb else {}
    p.add_argument("--repo", action="append", metavar="NAME", **d,
                   help="limit to repos whose name contains NAME (repeatable)")
    p.add_argument("--all", action="store_true", **d,
                   help="include finished/empty/trunk")
    p.add_argument("--here", action="store_true", **d,
                   help="only the current repo, ignoring configured roots")
    p.add_argument("--json", action="store_true", **d,
                   help="machine-readable output; with a change verb, the plan as JSON")
    p.add_argument("--size", action="store_true", **d,
                   help="measure disk in the default view")
    p.add_argument("--stale-days", type=int, metavar="N", **d,
                   help="staleness threshold")
    p.add_argument("--color", choices=["auto", "always", "never"],
                   **(d or dict(default="auto")))
    p.add_argument("--progress", action="store_true", **d,
                   help="write 'wt-progress DONE TOTAL LABEL' to stderr as work is done; "
                        "for a caller that is drawing its own progress bar")
    p.add_argument("--refresh", action="store_true", **d,
                   help="ignore every cache: re-measure disk and re-derive history")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wt-manager", description="what am I in the middle of, and what is it costing me?",
        epilog=EPILOG, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", action="version", version=f"wt-manager {VERSION}")
    add_global_flags(p)

    # The globals repeated on each verb, so they parse on either side of it.
    after = argparse.ArgumentParser(add_help=False)
    add_global_flags(after, after_verb=True)

    sub = p.add_subparsers(dest="cmd", parser_class=argparse.ArgumentParser)

    sub.add_parser("size", parents=[after],
                   help="disk held per worktree, biggest first")

    rp = sub.add_parser("reap", parents=[after], help="remove finished worktrees")
    rp.add_argument("--yes", "--prune", action="store_true", dest="yes",
                    help="actually remove them (default is a dry run)")
    rp.add_argument("--force", action="store_true",
                    help="also reap worktrees with uncommitted or unpushed work")
    rp.add_argument("--discard-precious", action="store_true",
                    help="delete ignored .env files, keys and other local-only config "
                         "with the worktree, instead of setting them aside first")
    rp.add_argument("--discard-unknown", action="store_true",
                    help="delete ignored files that cannot be classified as regenerable "
                         "with the worktree, instead of setting them aside first")
    rp.add_argument("--plan", metavar="HASH",
                    help="the plan hash from a --json dry run; --yes refuses to run if "
                         "what it would remove no longer matches")
    rp.add_argument("--path", metavar="P", action="append",
                    help="only this worktree (repeatable). the safe unit: one "
                         "decision about one thing, rather than a whole sweep")

    cl = sub.add_parser("clean", parents=[after],
                        help="reclaim regenerable build output")
    cl.add_argument("--yes", action="store_true",
                    help="actually delete (default is a dry run)")
    cl.add_argument("--stale", action="store_true",
                    help="only forgotten or finished worktrees")
    cl.add_argument("--verbose", "-v", action="store_true", help="list every path")
    cl.add_argument("--path", metavar="P", action="append",
                    help="only this worktree (repeatable)")
    cl.add_argument("--list-unknown", action="store_true",
                    help="show ignored paths wt-manager refuses to classify")
    cl.add_argument("--plan", metavar="HASH",
                    help="the plan hash from a --json dry run; --yes refuses to run if "
                         "what it would delete no longer matches")

    ps = sub.add_parser("push", parents=[after],
                        help="send commits that exist only on this machine")
    ps.add_argument("--yes", action="store_true",
                    help="actually push (default is a dry run)")
    ps.add_argument("--path", metavar="P", action="append",
                    help="the worktree to push (repeatable). required: this is "
                         "the one verb that writes to a remote, so it is never "
                         "a sweep over whatever happened to be in scope")
    ps.add_argument("--plan", metavar="HASH",
                    help="the plan hash from a --json dry run; --yes refuses to run "
                         "if what it would push no longer matches")

    sub.add_parser("doctor", parents=[after],
                   help="explain base-branch resolution per repo")

    ag = sub.add_parser("agent", parents=[after],
                        help="one JSON envelope for an ambient client")
    ag.add_argument("--no-size", action="store_true", help="skip measuring disk")
    ag.add_argument("--reclaim-kb", type=int, metavar="N",
                    help="use this reclaimable total instead of measuring. lets a "
                         "long-running client refresh counts often and disk rarely, "
                         "without the gauge falsely emptying in between")

    cf = sub.add_parser("config", help="show or create the config file")
    cf.add_argument("--init", action="store_true", help="write a starter config")
    cf.add_argument("--force", action="store_true", help="overwrite an existing one")
    cf.add_argument("--roots", metavar="DIR", action="append",
                    help="set the directories to scan for repos (repeatable). "
                         "everything else in the config is kept")
    cf.add_argument("--clear-roots", action="store_true",
                    help="stop watching all folders; other settings are kept")
    cf.add_argument("--clear-cache", action="store_true",
                    help="remove every cache file (PR data, sizes, history); config stays")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    C.setup({"always": True, "never": False}.get(args.color))
    init_colors()

    if args.cmd == "config":
        return cmd_config(args)

    global _SIZE_CACHE_TTL, _REPO_SCAN_TTL, _UNSEEN_TTL, _state_ignore_file
    if args.refresh:
        _SIZE_CACHE_TTL = 0
        _REPO_SCAN_TTL = 0
        _UNSEEN_TTL = 0
        _state_ignore_file = True      # cached history too, not only sizes

    cfg = load_config()
    if args.stale_days is not None:
        cfg["stale_days"] = args.stale_days
    sweep_cache()

    roots = [] if args.here else (cfg.get("roots") or [])
    # `push` moves commits, not bytes: measuring a hundred gigabytes to send
    # six commits is ninety seconds spent on a number nobody asked for.
    needs_size = args.cmd in ("size", "clean", "reap") or args.size \
        or (args.cmd == "agent" and not getattr(args, "no_size", False))
    # `reap` removes whole worktrees, so it only needs each total — not the
    # per-path ignored breakdown, which is the expensive half of measuring.
    detail = args.cmd in ("clean", "size", "agent")

    # How many bars this run will draw, declared before the first one starts so
    # that a bar which empties can say what it is making room for. Reading is
    # always one; measuring is a second when disk is wanted; the work itself is
    # a third, and only when it is actually going to happen.
    steps = 1 + int(needs_size) + int(args.cmd == "reap") + int(args.cmd in ("reap", "clean", "push")
                                      and getattr(args, "yes", False))
    set_progress(args.progress, steps)

    try:
        wts = gather(cfg, roots, sizes=needs_size, detail=detail,
                     paths=getattr(args, "path", None))
    except NotConfigured as e:
        # A client drawing a window gets a state it can render and act on; a
        # person at a prompt gets the sentence and the command, which is the
        # right next move in a terminal and useless in a window.
        if args.cmd == "agent":
            return cmd_unconfigured()
        die(str(e))
    except OSError as e:
        die(f"scan refused: {e}")

    if args.repo:
        pats = [r.lower() for r in args.repo]
        wts = [w for w in wts if any(pat in w.repo.lower() for pat in pats)]

    visible = wts if (args.all or args.cmd in ("reap", "clean", "size", "doctor",
                                               "agent", "push")) \
        else [w for w in wts if w.status not in HIDDEN_BY_DEFAULT]

    # Every verb that carries a plan prints the plan instead of the census.
    if args.json and args.cmd not in ("reap", "clean", "push"):
        payload = [dict(asdict(w), dirty=w.dirty, meaning=MEANING.get(w.status, ""))
                   for w in visible]
        print(json.dumps(payload, indent=2))
        return 0

    if args.cmd == "size":
        render_size(visible, detailed=detail)
        return 0
    if args.cmd == "agent":
        return cmd_agent(visible, args)
    if args.cmd == "doctor":
        return cmd_doctor(wts)
    if args.cmd == "push":
        return cmd_push(wts, args)
    if args.cmd == "reap":
        return cmd_reap(wts, args)
    if args.cmd == "clean":
        return cmd_clean(visible, args)

    multi = len({w.repo for w in wts}) > 1
    render_table(visible, show_size=args.size, multi_repo=multi)
    hidden = [w for w in wts if w.status in HIDDEN_BY_DEFAULT]
    if hidden and not args.all:
        # Counted by kind, and only the reapable half gets the verb.
        #
        # This read "24 finished or empty hidden — `wt-manager reap` to
        # remove". Nineteen of the twenty-four were `trunk`: the repos'
        # own main checkouts, which are neither finished nor empty and which
        # git refuses to remove for ever. Measured against it, `reap` removed
        # 0 of the 24. The count, the category and the advice were each wrong.
        by = Counter(w.status for w in hidden)
        trunk_n = by.get(TRUNK, 0)
        done_n = len(hidden) - trunk_n
        parts = []
        if done_n:
            parts.append(f"{done_n} finished or empty")
        if trunk_n:
            parts.append(f"{trunk_n} main checkout{'s' if trunk_n != 1 else ''}")
        line = f"{' and '.join(parts)} hidden — --all to show"
        if done_n:
            line += ", `wt-manager reap` to remove the finished ones"
        print(f"{C.dim}{line}{C.off}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        os._exit(0)
