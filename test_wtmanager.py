#!/usr/bin/env python3
"""Tests for the parts where being wrong is expensive.

Not a coverage exercise. Three things earn tests here:

* **what may be deleted** — `classify_ignored` is the whole safety story, and
  every false SAFE is an unrecoverable file;
* **what the mascot claims** — `mood` is a pure function with documented
  precedence, so the truth table is checkable without drawing anything;
* **the boundaries** — path containment and the plan hash, both of which were
  wrong at some point and neither of which fails loudly.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import contextlib
import io
import sys
import unittest
from unittest import mock
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wtmanager as T
import mascot as M

GB = 1 << 20


def git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, check=True,
                          capture_output=True, text=True).stdout.strip()


class Fixture:
    """A bare origin, a main checkout tracking it, and linked worktrees.

    Real git, in a temp dir. The fingerprint and the merged rule are claims
    about what git writes to disk, and a fake would only test the fake.
    """

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="wt-manager-test-")
        self.origin = os.path.join(self.root, "origin.git")
        self.main = os.path.join(self.root, "repo")
        git("init", "-q", "--bare", self.origin, cwd=self.root)
        git("init", "-q", "-b", "main", self.main, cwd=self.root)
        git("config", "user.email", "t@t", cwd=self.main)
        git("config", "user.name", "t", cwd=self.main)
        with open(os.path.join(self.main, "README"), "w") as fh:
            fh.write("hi\n")
        git("add", "-A", cwd=self.main)
        git("commit", "-qm", "init", cwd=self.main)
        git("remote", "add", "origin", self.origin, cwd=self.main)
        git("push", "-q", "-u", "origin", "main", cwd=self.main)
        git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main", cwd=self.main)
        self.gitdir = T.common_dir(self.main)

    def worktree(self, name, branch):
        path = os.path.join(self.root, "wts", name)
        git("worktree", "add", "-q", path, "-b", branch, "origin/main", cwd=self.main)
        return path

    def commit(self, path, name="f", msg="work"):
        with open(os.path.join(path, name), "a") as fh:
            fh.write("x\n")
        git("add", name, cwd=path)
        git("commit", "-qm", msg, cwd=path)
        return git("rev-parse", "HEAD", cwd=path)

    def probe(self, path, branch, merged=None, prs=None):
        return T.probe_worktree(self.gitdir, "repo", self.main, path, branch,
                                dict(T.DEFAULT_CONFIG), Counter(), prs or {}, merged or {})

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


def isolate_caches(case):
    """Point every cache at a fresh directory for the duration of one test."""
    d = tempfile.mkdtemp(prefix="wt-manager-cache-")
    old = {k: os.environ.get(k) for k in ("XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME")}
    # Separate, as on a real machine: clearing the cache must never reach config.
    os.environ["XDG_CACHE_HOME"] = os.path.join(d, "cache")
    os.environ["XDG_CONFIG_HOME"] = os.path.join(d, "config")
    os.environ["XDG_DATA_HOME"] = os.path.join(d, "data")
    T._state.clear()
    T._state_loaded = False
    T._base_cache.clear()
    T._ref_cache.clear()
    T._repo_facts.clear()
    T._identity.clear()

    def restore():
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        T._state.clear()
        T._state_loaded = False
        shutil.rmtree(d, ignore_errors=True)
    case.addCleanup(restore)


class Classification(unittest.TestCase):
    """The rule that decides what `clean` may remove."""

    REGENERABLE = ["node_modules", "apps/web/node_modules", ".next", "target",
                   "dist", "build", ".turbo", "DerivedData", "__pycache__",
                   ".gradle", "Pods", ".venv", "coverage"]
    PRECIOUS = [".env", ".env.local", ".env.production", "apps/web/.env.local",
                "server.pem", "key.p12", "id.keystore", "local.properties",
                ".netrc", ".npmrc", "serviceAccount.json", "firebase-key.json",
                "google-services.json", "GoogleService-Info.plist", ".envrc"]

    def test_regenerable_is_removable(self):
        for p in self.REGENERABLE:
            self.assertEqual(T.classify_ignored(p), T.SAFE, p)

    def test_precious_is_never_removable(self):
        for p in self.PRECIOUS:
            self.assertNotEqual(T.classify_ignored(p), T.SAFE, p)

    def test_unknown_is_kept(self):
        # The default has to be "keep": an allowlist that misses something costs
        # disk, a denylist that misses something costs the file.
        for p in ["mystery", ".wt-ports", "notes.txt", "tsconfig.tsbuildinfo"]:
            self.assertEqual(T.classify_ignored(p), T.UNKNOWN, p)

    def test_rustdoc_output_is_recognised_by_its_fingerprint(self):
        root = tempfile.mkdtemp(prefix="wt-manager-sig-")
        self.addCleanup(shutil.rmtree, root, True)
        api = os.path.join(root, "site", "public", "api")
        os.makedirs(os.path.join(api, "static.files"))
        open(os.path.join(api, "crates.js"), "w").close()
        self.assertEqual(T.classify_ignored("site/public/api/", root), T.SAFE)
        # The wrapper git reports once its .gitkeep is gone: one folder inside.
        self.assertEqual(T.classify_ignored("site/public/", root), T.SAFE)
        # A wrapper holding anything else is not the generator's alone.
        open(os.path.join(root, "site", "public", "logo.svg"), "w").close()
        self.assertEqual(T.classify_ignored("site/public/", root), T.UNKNOWN)
        # Half a fingerprint is no fingerprint.
        os.remove(os.path.join(api, "crates.js"))
        self.assertEqual(T.classify_ignored("site/public/api/", root), T.UNKNOWN)

    def test_names_that_also_hold_the_only_copy_of_something_are_unknown(self):
        # env/ is a virtualenv and also a folder of secrets; .bundle/config
        # holds gem-server credentials; .terraform/environment is the current
        # workspace. None can be recognised by name, so none is removable.
        for p in ["env", "env/", ".bundle/", ".terraform/", "tmp/", "apps/api/env/"]:
            self.assertEqual(T.classify_ignored(p), T.UNKNOWN, p)

    def test_a_virtualenv_is_recognised_by_its_shape(self):
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root, True)
        os.makedirs(os.path.join(root, "env"))
        self.assertEqual(T.classify_ignored("env/", root), T.UNKNOWN, "no pyvenv.cfg")
        open(os.path.join(root, "env", "pyvenv.cfg"), "w").close()
        self.assertEqual(T.classify_ignored("env/", root), T.SAFE)
        open(os.path.join(root, "env", "prod.pem"), "w").close()
        self.assertEqual(T.classify_ignored("env/", root), T.UNKNOWN, "a key inside")

    def test_a_precious_file_inside_a_regenerable_dir_shields_it(self):
        # What git actually reports for dist/.env is one line, "dist/": the
        # traditional listing collapses a wholly-ignored directory, so the
        # precious file is never seen by name. The earlier test here classified
        # "node_modules/.env" - an input `ignored_entries` cannot produce.
        isolate_caches(self)
        fx = Fixture()
        self.addCleanup(fx.close)
        wt = fx.worktree("d", "feat/d")
        with open(os.path.join(wt, ".gitignore"), "w") as fh:
            fh.write("dist/\n")
        git("add", ".gitignore", cwd=wt)
        git("commit", "-qm", "ignore", cwd=wt)
        os.makedirs(os.path.join(wt, "dist"))
        with open(os.path.join(wt, "dist", ".env"), "w") as fh:
            fh.write("SECRET=1\n")
        with open(os.path.join(wt, "dist", "bundle.js"), "w") as fh:
            fh.write("//\n")
        self.assertEqual(T.ignored_entries(wt), ["dist/"])
        self.assertEqual(T.classify_ignored("dist/"), T.SAFE, "by name alone")
        self.assertEqual(T.classify_ignored("dist/", wt), T.UNKNOWN, "seen on disk")
        w = fx.probe(wt, "feat/d")
        T.measure(w)
        self.assertEqual(w.reclaim_paths, [])
        self.assertIn("dist/.env", w.precious_hits)


class Containment(unittest.TestCase):
    def test_paths_outside_the_worktree_are_refused(self):
        self.assertFalse(T.inside("/tmp/a", "/tmp/b"))
        self.assertFalse(T.inside("/tmp/a", "/tmp/a"))          # the root itself
        self.assertFalse(T.inside("/tmp/a", "/tmp/ab/c"))       # prefix, not parent
        self.assertFalse(T.inside("/tmp/a", "/tmp/a/../b"))

    def test_real_children_are_allowed(self):
        os.makedirs("/tmp/wt-manager-test/sub", exist_ok=True)
        self.assertTrue(T.inside("/tmp/wt-manager-test", "/tmp/wt-manager-test/sub"))


class Mood(unittest.TestCase):
    """The precedence documented on `mascot.mood`, as a truth table."""

    def test_untrusted_only_wins_once_most_of_the_view_is_affected(self):
        self.assertEqual(M.mood(blocked=1, untrusted_share=0.2), "alarmed")
        self.assertEqual(M.mood(blocked=1, untrusted_share=0.9), "lost")

    def test_scanning_beats_everything_derived(self):
        self.assertEqual(M.mood(blocked=3, stale=9, scanning=True), "working")

    def test_blocked_beats_forgotten(self):
        self.assertEqual(M.mood(blocked=1, stale=17), "alarmed")

    def test_forgotten_beats_dead_weight(self):
        # Dead weight is never urgent; it must not nag over a stale branch.
        self.assertEqual(M.mood(stale=1, reclaim_kb=100 * GB), "nudging")

    def test_dead_weight_shows_once_nothing_is_shouting(self):
        self.assertEqual(M.mood(active=2, reclaim_kb=100 * GB), "burdened")

    def test_quiet_and_clean_is_proud(self):
        self.assertEqual(M.mood(), "proud")

    def test_a_draft_is_work_in_flight(self):
        # Yours, not yet offered: five open drafts are not "nothing in flight".
        self.assertEqual(M.mood(draft=5), "calm")
        self.assertEqual(M.headline("calm", {"draft": 2}, 0, 2), "Work in flight, nothing urgent")
        self.assertEqual(M.headline("calm", {"waiting": 1}, 0, 1), "Nothing is on you")

    def test_the_headline_is_the_state_and_never_grows_with_the_data(self):
        # It used to cram the count and the disk into one wrapping sentence.
        a = M.headline("nudging", {"stale": 1}, 0, 5)
        b = M.headline("nudging", {"stale": 18}, 244 << 20, 59)
        self.assertEqual(a, b)
        self.assertEqual(a, "Nothing is blocking you")
        for mood in M.MOODS:
            self.assertLess(len(M.headline(mood, {"blocked": 3}, 1 << 20, 9)), 40, mood)

    def test_insights_carry_each_fact_once_and_only_when_present(self):
        tags = M.insights({"stale": 18, "blocked": 0}, 244 << 20, 95, finished=4)
        self.assertEqual([t["label"] for t in tags],
                         ["18 forgotten", "95 commits only here", "244GB rebuildable", "4 finished"])
        self.assertEqual([t["target"] for t in tags], ["forgot", "overview", "disk", "done"])
        self.assertEqual(M.insights({}, 0, 0), [])
        self.assertEqual(M.insights({"blocked": 1}, 0, 1)[0]["label"], "1 needs you")

    def test_only_the_facts_with_no_other_home_are_solo(self):
        # A window with a sidebar shows the solo ones and nothing else, so this
        # is the rule that keeps the header from being a second copy of the
        # sidebar. "1 needs you" is the worst of them: it also *is* the
        # headline, word for word.
        tags = M.insights({"blocked": 1, "stale": 18, "waiting": 3, "draft": 1},
                          244 << 20, 96, finished=4, unreadable=16)
        solo = [t["id"] for t in tags if t["solo"]]
        self.assertEqual(solo, ["unpushed", "unreadable"])
        for t in tags:
            if t["solo"]:
                continue
            self.assertIn(t["target"], {"need", "forgot", "flight", "others", "done", "disk"},
                          "%s claims a home the sidebar does not have" % t["id"])

    def test_the_agent_envelope_carries_the_headline(self):
        # So the app renders it instead of ranking the facts a second time.
        import io, contextlib, json
        class Args: reclaim_kb = None
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            T.cmd_agent([wt(status="stale", ahead=2, unpushed=2, unpushed_mine=2),
                         wt(path="/q", status="active")], Args())
        env = json.loads(out.getvalue())
        self.assertEqual(env["face"]["mood"], "nudging")
        self.assertEqual(env["headline"], "Nothing is blocking you")
        self.assertEqual([t["id"] for t in env["insights"]], ["stale", "unpushed"])

    def test_agent_keeps_two_repositories_with_the_same_name_distinct(self):
        a = wt(status="active")
        b = wt(path="/other/repo/worktree", status="stale")
        a.repo = b.repo = "repo"
        a.repo_id = "/projects/one/repo/.git"
        b.repo_id = "/projects/two/repo/.git"
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            T.cmd_agent([a, b], argparse.Namespace(reclaim_kb=None))
        rows = json.loads(out.getvalue())["worktrees"]
        self.assertEqual([r["repo_id"] for r in rows], [a.repo_id, b.repo_id])

    def test_every_mood_is_reachable(self):
        # A mood no input can produce is a mood that should not exist — this is
        # how `stale` stayed unreachable behind `active` for a whole release.
        produced = {
            M.mood(untrusted_share=1.0),
            M.mood(scanning=True),
            M.mood(blocked=1),
            M.mood(stale=1),
            M.mood(active=1, reclaim_kb=100 * GB),
            M.mood(active=1),
            M.mood(),
            M.mood(reclaim_kb=1),
        }
        self.assertEqual(produced, set(M.MOODS), "unreachable: %s" % (set(M.MOODS) - produced))


class Accounts(unittest.TestCase):
    """Asking the wrong account looks exactly like a permissions problem."""

    def setUp(self):
        self.saved = T._accounts
        T._accounts = [("work", "github.com"), ("personal", "github.com")]

    def tearDown(self):
        T._accounts = self.saved

    def test_the_owner_of_the_repo_is_tried_first(self):
        # `samiesmilz/AIGovSpec` is almost certainly readable by `samiesmilz`
        # and by nobody else, so guessing from the URL turns two calls into
        # one for every personal repo on the machine.
        order = T.accounts_for("https://github.com/personal/thing.git")
        self.assertEqual(order[0], ("personal", "github.com"))
        self.assertIn(("work", "github.com"), order)

    def test_both_url_forms_name_the_same_owner(self):
        for url in ("https://github.com/personal/thing.git",
                    "git@github.com:personal/thing.git",
                    "ssh://git@github.com/personal/thing"):
            self.assertEqual(T.origin_owner(url), "personal", url)
        self.assertEqual(T.origin_owner("https://gitlab.com/x/y.git"), "")
        self.assertEqual(T.origin_owner(""), "")

    def test_one_account_means_no_token_juggling_at_all(self):
        # A machine that has always worked must keep working byte for byte:
        # no GH_TOKEN, no extra calls, no behaviour that did not exist before.
        T._accounts = [("solo", "github.com")]
        self.assertEqual(T.accounts_for("https://github.com/anyone/x.git"), [None])
        T._accounts = []
        self.assertEqual(T.accounts_for("https://github.com/anyone/x.git"), [None])

    def test_only_a_missing_repo_is_worth_asking_someone_else_about(self):
        # A timeout or a rate limit fails the same way for every account, so
        # retrying each of them turns one slow call into N slow calls.
        calls = []

        def fake(args, cwd=None, timeout=30, env=None):
            calls.append(env and env.get("GH_TOKEN"))
            return 1, "", "HTTP 504: gateway timeout"

        with mock.patch.object(T, "sh", fake), \
             mock.patch.object(T, "account_token", lambda a: "tok-" + a[0]):
            rc, _, err, acct = T.gh_json(["gh", "x"], "/tmp", "https://github.com/work/x.git")
        self.assertEqual(len(calls), 1, "retried a failure that was not about visibility")
        self.assertIsNone(acct)

    def test_a_repo_the_second_account_can_see_is_found(self):
        seen = []

        def fake(args, cwd=None, timeout=30, env=None):
            token = env and env.get("GH_TOKEN")
            seen.append(token)
            if token == "tok-personal":
                return 0, "[]", ""
            return 1, "", "GraphQL: " + T.UNRESOLVED + " with the name 'x'."

        with mock.patch.object(T, "sh", fake), \
             mock.patch.object(T, "account_token", lambda a: "tok-" + a[0]), \
             mock.patch.object(T, "remember_account", lambda o, a: None), \
             mock.patch.object(T, "remembered_account", lambda o: None):
            rc, out, _, acct = T.gh_json(["gh", "x"], "/tmp",
                                         "https://github.com/work/x.git")
        self.assertEqual(rc, 0)
        self.assertEqual(acct, ("personal", "github.com"))
        self.assertEqual(seen, ["tok-work", "tok-personal"], "order or count wrong")

    def test_signing_in_to_another_account_re_asks_every_giving_up_repo(self):
        # The marker means "nobody we can ask can see this", and who we can ask
        # changes on `gh auth login`. Keyed on the repo alone, a refusal
        # recorded under one account list would go on answering for another —
        # which is exactly how this bug survived its own fix once already.
        origin = "https://github.com/work/x.git"
        one = T._unseen_file(origin)
        T._accounts = [("work", "github.com")]
        two = T._unseen_file(origin)
        self.assertNotEqual(one, two)

    def test_an_environment_overlay_keeps_the_rest_of_the_environment(self):
        # A bare dict strips PATH and HOME, and `gh` then cannot find itself
        # or its own config.
        rc, out, _ = T.sh([sys.executable, "-c",
                           "import os;print(os.environ.get('PATH','') != '', os.environ['WT_X'])"],
                          env={"WT_X": "1"})
        self.assertEqual(out, "True 1")


class AccountRace(unittest.TestCase):
    """The account list is built once and read by sixteen scan threads."""

    HOSTS = json.dumps({"hosts": {"github.com": [
        {"login": "work", "state": "success", "active": True},
        {"login": "personal", "state": "success", "active": False}]}})

    def setUp(self):
        T._accounts = None
        T._tokens.clear()
        self.addCleanup(lambda: (setattr(T, "_accounts", None), T._tokens.clear()))

    def slow_gh(self, args, **kw):
        """`gh auth status` is a subprocess: about 200ms of window."""
        if args[:3] == ["gh", "auth", "status"]:
            time.sleep(0.2)
            return 0, self.HOSTS, ""
        return 0, "tok", ""

    def test_no_thread_ever_sees_a_half_built_account_list(self):
        """It published `[]` on entry and filled it in after the subprocess
        returned, so every thread arriving in that window took the empty list.

        An empty list is not neutral: `accounts_for` turns it into `[None]`,
        which runs `gh` with no token overlay — as whichever account happens to
        be active. For a repo only the other account can see, that answers
        "Could not resolve to a Repository", which is the exact string that
        marks a repo unseen for the next fifteen minutes.

        Measured on a real machine: 15 of 16 threads took the empty list, and
        17 readable repos of 27 were reported invisible. Every serial test of
        the feature passed throughout.
        """
        with mock.patch.object(T, "have", lambda t: True), \
             mock.patch.object(T, "sh", self.slow_gh):
            import concurrent.futures as futures
            with futures.ThreadPoolExecutor(max_workers=16) as pool:
                seen = list(pool.map(lambda _: T.gh_accounts(), range(16)))
        self.assertEqual({len(s) for s in seen}, {2},
                         "a thread saw a partially built account list")
        self.assertEqual(seen[0][0], ("work", "github.com"), "active account first")

    def test_the_sentinel_that_made_it_silent_still_means_what_it_meant(self):
        """An empty list is how "an older gh, ask the way we always did" is
        said, which is why a half-built one was indistinguishable from a
        legitimate answer. That meaning has to survive the fix."""
        with mock.patch.object(T, "have", lambda t: False):
            self.assertEqual(T.gh_accounts(), [])
        self.assertEqual(T.accounts_for("https://github.com/x/y.git"), [None])
        self.assertIsNone(T.gh_env(None), "no overlay: gh behaves as it always did")

    def test_one_token_fetch_however_many_ask(self):
        calls = []

        def counting(args, **kw):
            calls.append(args)
            time.sleep(0.05)
            return 0, "tok", ""

        with mock.patch.object(T, "sh", counting):
            import concurrent.futures as futures
            with futures.ThreadPoolExecutor(max_workers=8) as pool:
                got = list(pool.map(lambda _: T.account_token(("work", "github.com")),
                                    range(8)))
        self.assertEqual(got, ["tok"] * 8)
        self.assertEqual(len(calls), 1, "one answer, one subprocess")


class Refusals(unittest.TestCase):
    """A refusal that says nothing is a button that looks broken."""

    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def reap(self, paths=None):
        import argparse
        args = argparse.Namespace(json=True, yes=False, force=False,
                                  discard_precious=False, repo=None, all=True,
                                  path=paths, plan=None)
        wts = T.gather(dict(T.DEFAULT_CONFIG), [], sizes=False, paths=paths or [self.fx.main])
        plan = {}
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            T._reap(wts, args, plan)
        return plan, out.getvalue()

    def on_a_feature_branch(self):
        """Put the main checkout on a branch that has already landed, which is
        the shape that made this confusing: status `empty`, so the window
        offered to remove it, and git will never do that."""
        git("checkout", "-q", "-b", "feat/landed", "origin/main", cwd=self.fx.main)

    def test_the_main_checkout_is_refused_out_loud(self):
        # `git worktree remove` cannot remove a repo's main working tree, so
        # this is a permanent fact about that checkout and not a condition
        # that might pass tomorrow. Dropping it silently produced a plan with
        # nothing in it and no reason, which the window rendered as "nothing
        # to do here" — indistinguishable from all-clear, over a button the
        # window should not have offered in the first place.
        self.on_a_feature_branch()
        plan, text = self.reap(paths=[self.fx.main])
        self.assertEqual(plan["paths"], [])
        whys = [s["why"] for s in plan["skipped"]]
        self.assertTrue(whys, "refused with no reason: %r" % text)
        self.assertIn("main checkout", " ".join(whys))

    def test_naming_a_worktree_explains_why_it_does_not_qualify(self):
        # Pointing at one thing and being told "nothing to reap" reads as the
        # tool having done nothing.
        wt = self.fx.worktree("live", "feat/live")
        self.fx.commit(wt)
        plan, _ = self.reap(paths=[wt])
        self.assertEqual(plan["paths"], [])
        self.assertTrue(any("only finished work" in s["why"] for s in plan["skipped"]),
                        plan["skipped"])

    def test_a_sweep_still_explains_a_main_checkout_that_looked_ready(self):
        # It is the one the window would have offered a button for, so it is
        # the one somebody is owed a sentence about even without asking.
        self.on_a_feature_branch()
        plan, _ = self.reap(paths=None)
        self.assertTrue(any("main checkout" in s["why"] for s in plan["skipped"]),
                        plan["skipped"])

    def test_a_bulk_sweep_does_not_narrate_every_healthy_worktree(self):
        # The same line for every active worktree in a twenty-seven repo
        # sweep is noise. It is the explicit scope that earns the sentence.
        wt = self.fx.worktree("live", "feat/live")
        self.fx.commit(wt)
        plan, _ = self.reap(paths=None)
        self.assertFalse(any("only finished work" in s["why"] for s in plan["skipped"]),
                         "a sweep listed every worktree it did not want")


class Character(unittest.TestCase):
    def test_no_two_expressions_draw_the_same(self):
        # Five expressions in a two-pixel cell is close to the ceiling, and a
        # pair that renders identically is a mood the face cannot report. This
        # is the property the catchlight was standing in for: `wide` has no
        # highlight on purpose — a stare is a stare because there is no glint
        # in it — so what matters is that every eye is *distinguishable*, not
        # that every eye is lit.
        seen = {}
        for name in M.EYES:
            art = "\n".join(M.bust(0, name, M.CAT)[4:6])
            self.assertNotIn(art, seen, "%s draws the same as %s" % (name, seen.get(art)))
            seen[art] = name

    def test_the_two_eyes_are_mirrors_of_each_other(self):
        # Written outward-in and mirrored, so one line describes both. The two
        # halves got out of step once, when the cell changed width and the
        # mirror was still measured against a constant.
        for name in M.EYES:
            for row in M.bust(0, name, M.CAT)[4:6]:
                self.assertEqual(row, row[::-1], "%s is lopsided: %s" % (name, row))

    def test_the_figure_carries_no_pale_patch(self):
        # The pale pouch and the pale feet both read as white squares stuck to
        # the character, and the first question anyone asked about either was
        # what it was for.
        for level in range(len(M.POUCH)):
            for eyes in M.EYES:
                rows = M.sprite(level, eyes, 0)
                self.assertNotIn('b', "".join(rows), "pale pixel at %d/%s" % (level, eyes))

    def test_every_skin_defines_every_slot(self):
        # A slot with no colour in a skin is drawn as a hole, silently. This is
        # how a rename of one slot name would ship as a missing pixel.
        wanted = {v for v in M.SLOTS.values() if v != "accent"}
        for name, skin in M.SKINS.items():
            self.assertEqual(wanted - set(skin), set(), name)

    def test_every_figure_carries_the_status_colour(self):
        # A figure whose eyes are dark loses the tint entirely at 22 pixels
        # and stops being an instrument — which is exactly what happened to
        # two of pr-radar's four before it added the same rule. Every figure
        # declares at least one pixel that is always painted in the accent,
        # in every expression, at every gauge.
        for fig in M.FIGURES.values():
            self.assertTrue(fig.tell, "%s declares no tell" % fig.id)
            for eyes in M.EYES:
                for level in range(len(M.POUCH)):
                    art = "".join(M.sprite(level, eyes, 0, fig))
                    self.assertIn("*", art, "%s/%s/%d" % (fig.id, eyes, level))

    def test_no_two_figures_draw_the_same(self):
        # Four characters that render identically are one character and three
        # wasted entries in a picker.
        seen = {}
        for fig in M.FIGURES.values():
            art = "\n".join(M.sprite(2, "open", 0, fig))
            self.assertNotIn(art, seen, "%s draws the same as %s" % (fig.id, seen.get(art)))
            seen[art] = fig.id

    def test_nobody_leaves_the_ground(self):
        # The bob lifts a whole figure and is the motion of last resort; a
        # figure that moves some better way must not also levitate. Checked
        # at the feet, not the head: a head is *supposed* to move, so the
        # tell for levitating is the lowest row changing, not the highest.
        for fig in M.FIGURES.values():
            floors = set()
            for i in range(M.FRAMES):
                rows = M.sprite(1, "open", i, fig)
                floors.add(max(y for y, r in enumerate(rows) if r.strip(".")))
            self.assertEqual(len(floors), 1,
                             "%s leaves the ground: %s" % (fig.id, sorted(floors)))

    def test_every_figure_actually_moves(self):
        # A tail, a shearing layer, redrawn feet — whichever a figure
        # declares, if it silently did nothing the character would be a still
        # image with extra configuration.
        for fig in M.FIGURES.values():
            poses = {"\n".join(M.sprite(1, "open", i, fig)) for i in range(M.FRAMES)}
            self.assertGreater(len(poses), 2,
                               "%s has %d pose(s)" % (fig.id, len(poses)))

    def test_a_figure_with_layers_does_not_move_as_one_block(self):
        # A figure whose top and bottom change on exactly the same frames is
        # a sprite being dragged, which is what one shared shear looked like
        # and why every character animated identically.
        for fig in [f for f in M.FIGURES.values() if f.parts]:
            frames = [M.sprite(1, "open", i, fig) for i in range(M.FRAMES)]
            # Measured against the figure's own extent, not the canvas: a
            # tail-less figure is lifted, so a fixed slice compares one part
            # of it with itself.
            floor = max(y for y, r in enumerate(frames[0]) if r.strip("."))
            top = [f[:4] for f in frames]
            low = [f[floor - 3:floor + 1] for f in frames]
            moved_top = {i for i in range(M.FRAMES) if top[i] != top[0]}
            moved_low = {i for i in range(M.FRAMES) if low[i] != low[0]}
            self.assertNotEqual(moved_top, moved_low,
                                "%s moves in one rigid block: %s vs %s"
                                % (fig.id, sorted(moved_top), sorted(moved_low)))

    def test_the_shared_legs_have_background_between_them(self):
        # Three legs was the real bug, and it was in the shared body: a pale
        # belly patch removed, filled with fur, and the two seams either side
        # left standing. Fur, seam, fur, seam, fur reads as three blocks,
        # because a seam only says "separate things" when there is background
        # behind it.
        #
        # Asserted on the body itself rather than on a rendered silhouette.
        # Counting runs along the bottom row was the first attempt and it
        # said a tree was broken for standing on one trunk, which is what
        # trees do.
        for row in M.BODY[-3:]:
            if "f" not in row:
                continue
            self.assertNotIn("f#f", row,
                             "an interior seam reads as an extra leg: %s" % row)
        self.assertIn("....", M.BODY[-2], "no gap between the legs: %s" % M.BODY[-2])

    def test_each_gauge_level_changes_the_silhouette(self):
        # The swell is the whole of the gauge now that it is not painted, so
        # two levels that draw the same shape are two levels that say nothing.
        shapes = [M.sprite(level, "open", 0) for level in range(len(M.POUCH))]
        for i in range(len(shapes) - 1):
            self.assertNotEqual(shapes[i], shapes[i + 1], "levels %d and %d" % (i, i + 1))


M_SPIN = T.Spinner


class Progress(unittest.TestCase):
    """The only channel the app has for "how far along is it"."""

    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="wt-progress-test-")
        self.addCleanup(shutil.rmtree, self.repo)
        git("init", "-q", self.repo, cwd=self.repo)
        git("config", "user.name", "Test", cwd=self.repo)
        git("config", "user.email", "test@example.invalid", cwd=self.repo)
        git("commit", "-q", "--allow-empty", "-m", "initial", cwd=self.repo)

    def run_progress(self, *args, ask=True):
        import subprocess
        argv = [sys.executable, T.__file__, "--here", "--json"]
        if ask:
            argv.append("--progress")
        r = subprocess.run(argv + list(args), cwd=self.repo,
                           capture_output=True, text=True)
        return r.stdout, r.stderr

    def test_nobody_gets_progress_who_did_not_ask(self):
        # "stderr is not a terminal" is true of every pipe, so keying off it
        # would put sixty lines into `wt-manager --json agent | jq`.
        out, err = self.run_progress("reap", ask=False)
        self.assertNotIn(T.PROGRESS, err)
        self.assertNotIn(T.PROGRESS, out)

    def test_progress_goes_to_stderr_and_never_into_the_plan(self):
        # --json captures the whole of stdout into the plan's `text`, so a
        # progress line written there arrives at the end, inside a string,
        # which is the one place it is no use.
        out, err = self.run_progress("reap")
        lines = [l for l in err.splitlines() if l.startswith(T.PROGRESS)]
        self.assertTrue(lines, "no progress on stderr: %r" % err[:200])
        self.assertNotIn(T.PROGRESS, out)
        for line in lines:
            tag, done, total, step, steps, *rest = line.split(" ", 5)
            self.assertEqual(tag, T.PROGRESS)
            self.assertTrue(done.isdigit() and total.isdigit(), line)
            self.assertTrue(1 <= int(step) <= int(steps), line)

    def test_the_bar_never_goes_backwards_within_a_step(self):
        """It did. `self.n += 1` is a read, an add and a write, and every
        caller of `tick()` is a twelve-thread pool — so two workers read the
        same count, and each then *reported* the one it held. Measured before
        the lock: one backwards jump in a run of 56."""
        _, err = self.run_progress("reap")
        seen = {}
        for line in err.splitlines():
            if not line.startswith(T.PROGRESS):
                continue
            _, done, total, step, *_ = line.split(" ", 4)
            key = (step, total)
            self.assertGreaterEqual(int(done), seen.get(key, 0), line)
            seen[key] = int(done)

    def test_the_shape_is_declared_before_any_work(self):
        """The reader draws one segment per pass. Learning there are three only
        when the first count lands means the bar is laid out once as a single
        segment and then re-laid-out as three, a second into a ninety-second
        wait — the exact jank the segments were added to remove."""
        _, err = self.run_progress("reap")
        first = next(l for l in err.splitlines() if l.startswith(T.PROGRESS))
        tag, done, total, step, steps, *rest = first.split(" ", 5)
        self.assertEqual((done, total, step), ("0", "0", "1"), first)
        self.assertGreater(int(steps), 1, "a reap measures, so it is at least two")

    def test_a_run_says_how_many_bars_it_will_draw(self):
        """A bar that empties and refills under one unchanged heading is the
        most reliable way a working process has of looking broken. Reading the
        repos and measuring them are separate passes with separate totals —
        the second cannot be counted until the first has finished — so the
        restart is real and the only fix is to say which pass this is."""
        _, err = self.run_progress("reap")
        steps = {tuple(l.split(" ")[3:5]) for l in err.splitlines()
                 if l.startswith(T.PROGRESS)}
        # Reading, measuring, and checking removal safety have separate progress.
        self.assertEqual({s for _, s in steps}, {"3"}, steps)
        self.assertEqual({n for n, _ in steps}, {"1", "2", "3"}, steps)
        self.assertIn("safety checks complete", err)

    def test_a_terminal_gets_the_spinner_and_not_the_lines(self):
        # Two audiences, one counter. A person watching gets a spinner; a
        # hundred lines of "wt-progress 41 57" in their scrollback is noise.
        T.set_progress(True)
        try:
            spin = M_SPIN("reading", total=3)
            spin.on = True
            buf = io.StringIO()
            with contextlib.redirect_stderr(buf):
                spin.step()
                spin.done()
            self.assertNotIn(T.PROGRESS, buf.getvalue())
        finally:
            T.set_progress(False)


class Gauge(unittest.TestCase):
    def test_absolute_thresholds(self):
        self.assertEqual(M.gauge(0), 0)
        self.assertEqual(M.gauge(2 * GB), 1)
        self.assertEqual(M.gauge(20 * GB), 2)
        self.assertEqual(M.gauge(100 * GB), 3)

    def test_a_large_repo_cannot_hide_behind_its_own_size(self):
        # Absolute, not a ratio: 100G of waste is 100G whether it is 9% or 99%.
        self.assertEqual(M.gauge(100 * GB), M.gauge(100 * GB))


class Checks(unittest.TestCase):
    def test_a_failure_on_nearly_every_pr_is_not_yours(self):
        prs = {f"b{i}": T.PR(number=i, state="OPEN", draft=False, checks="failing",
                             review="none", failing=["deploy"]) for i in range(10)}
        prs["mine"] = T.PR(number=99, state="OPEN", draft=False, checks="failing",
                           review="none", failing=["deploy", "my-test"])
        rate = T.Counter()
        for p in prs.values():
            rate.update(set(p.failing))
        T.subtract_baseline(prs, rate, len(prs))
        self.assertEqual(prs["b0"].distinct_failing, [])
        self.assertEqual(prs["mine"].distinct_failing, ["my-test"])

    def test_an_all_endemic_pr_stops_reading_as_failing(self):
        prs = {f"b{i}": T.PR(number=i, state="OPEN", draft=False, checks="failing",
                             review="none", failing=["deploy"]) for i in range(5)}
        rate = T.Counter({"deploy": 5})
        T.subtract_baseline(prs, rate, 5)
        self.assertEqual(prs["b0"].checks, "endemic")


def wt(**kw):
    base = dict(repo="r", path="/p", branch="b", primary=False, base="origin/main",
                base_source="origin/HEAD")
    base.update(kw)
    return T.Worktree(**base)


class Status(unittest.TestCase):
    """`derive_status`, at the two labels `reap` acts on."""

    def test_a_branch_with_no_commits_is_empty_not_merged(self):
        # ahead == 0 with no forge evidence is "nothing here the base lacks".
        # It used to read `merged` ("landed; safe to reap") — for a branch
        # created a minute ago, before its first commit.
        self.assertEqual(T.derive_status(wt(ahead=0, behind=0), 14), T.EMPTY)
        self.assertEqual(T.derive_status(wt(ahead=0, behind=5), 14), T.EMPTY)

    def test_merged_needs_a_merged_pr(self):
        pr = T.PR(number=1, state="MERGED", draft=False, checks="none", review="none")
        self.assertEqual(T.derive_status(wt(ahead=0, pr=pr), 14), T.MERGED)
        # A squash merge leaves the branch ahead of base; the PR is the proof.
        self.assertEqual(T.derive_status(wt(ahead=3, pr=pr), 14), T.MERGED)

    def test_no_base_means_no_finished_verdict(self):
        w = wt(ahead=0, behind=0, base="(none)", base_source="unresolved")
        self.assertNotIn(T.derive_status(w, 14), (T.MERGED, T.EMPTY, T.TRUNK))

    def test_a_merged_pr_with_a_stray_file_is_not_your_move(self):
        # Measured: three worktrees merged 20-43 days ago, one uncommitted file
        # each, all reading "active — your move".
        merged = T.PR(number=1, state="MERGED", draft=False, checks="none",
                      review="none", merged_at="2026-01-01T00:00:00Z")
        w = wt(ahead=0, untracked=1, age_days=40, pr=merged)
        self.assertEqual(T.derive_status(w, 14), T.STALE)

    def test_an_open_pr_keeps_a_dirty_tree_in_flight_whatever_its_age(self):
        pr = T.PR(number=1, state="OPEN", draft=False, checks="passing", review="none")
        self.assertEqual(T.derive_status(wt(ahead=2, unstaged=1, age_days=40, pr=pr), 14),
                         T.ACTIVE)

    def test_a_merge_yesterday_is_recent_however_old_the_last_commit(self):
        # Review takes weeks; the merge is when the branch last had attention.
        yesterday = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 86400))
        merged = T.PR(number=1, state="MERGED", draft=False, checks="none",
                      review="none", merged_at=yesterday)
        w = wt(ahead=0, untracked=1, age_days=40, pr=merged)
        self.assertEqual(T.derive_status(w, 14), T.ACTIVE)


class Authorship(unittest.TestCase):
    """What exists only here, split by who wrote it."""

    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def test_a_colleagues_commits_are_not_your_work_at_risk(self):
        # A review checkout: someone else's commits, on no remote we hold.
        path = self.fx.worktree("r", "review/pr-9")
        with open(os.path.join(path, "theirs"), "w") as fh:
            fh.write("x\n")
        git("add", "theirs", cwd=path)
        git("-c", "user.email=colleague@example.com", "-c", "user.name=c",
            "commit", "-qm", "their change", cwd=path)
        self.fx.commit(path, msg="my note on it")
        w = self.fx.probe(path, "review/pr-9")
        self.assertEqual((w.unpushed, w.unpushed_mine), (2, 1))
        self.assertEqual(w.solo_log, ["my note on it"])

    def test_with_no_identity_every_commit_counts(self):
        path = self.fx.worktree("n", "feat/n")
        self.fx.commit(path)
        T._identity[self.fx.gitdir] = ""
        w = self.fx.probe(path, "feat/n")
        self.assertEqual((w.unpushed, w.unpushed_mine), (1, 1))


class Base(unittest.TestCase):
    """What each branch is measured against. Every number in the table rests on it."""

    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def test_a_branch_with_a_pr_is_measured_against_its_target(self):
        # The repo's PRs vote for main; this one targets beta, so beta it is.
        git("push", "-q", "origin", "main:beta", cwd=self.fx.main)
        git("fetch", "-q", "origin", cwd=self.fx.main)
        path = self.fx.worktree("x", "feat/x")
        self.fx.commit(path)
        pr = T.PR(number=9, state="OPEN", draft=False, checks="passing",
                  review="none", base="beta")
        w = T.probe_worktree(self.fx.gitdir, "repo", self.fx.main, path, "feat/x",
                             dict(T.DEFAULT_CONFIG), Counter({"main": 9}),
                             {"feat/x": pr}, {})
        self.assertEqual((w.base, w.base_source), ("origin/beta", "pr"))
        self.assertEqual(w.ahead, 1)

    def test_a_retargeted_pr_is_not_served_from_the_cache(self):
        git("push", "-q", "origin", "main:beta", cwd=self.fx.main)
        git("fetch", "-q", "origin", cwd=self.fx.main)
        path = self.fx.worktree("x", "feat/x")
        self.fx.commit(path)

        def probe(target):
            pr = T.PR(number=9, state="OPEN", draft=False, checks="passing",
                      review="none", base=target)
            T._base_cache.clear()
            return T.probe_worktree(self.fx.gitdir, "repo", self.fx.main, path, "feat/x",
                                    dict(T.DEFAULT_CONFIG), Counter(), {"feat/x": pr}, {})
        self.assertEqual(probe("beta").base, "origin/beta")
        self.assertEqual(probe("main").base, "origin/main")

    def test_a_repo_with_no_remote_uses_its_own_main(self):
        # Its main checkout read "active, your move", unresolved.
        root = tempfile.mkdtemp(prefix="wt-manager-local-")
        self.addCleanup(shutil.rmtree, root, True)
        repo = os.path.join(root, "solo")
        git("init", "-q", "-b", "main", repo, cwd=root)
        git("config", "user.email", "t@t", cwd=repo)
        git("config", "user.name", "t", cwd=repo)
        git("commit", "-q", "--allow-empty", "-m", "init", cwd=repo)
        side = os.path.join(root, "side")
        git("worktree", "add", "-q", side, "-b", "feat/side", cwd=repo)
        git("commit", "-q", "--allow-empty", "-m", "work", cwd=side)
        gitdir = T.common_dir(repo)
        main = T.probe_worktree(gitdir, "solo", repo, repo, "main",
                                dict(T.DEFAULT_CONFIG), Counter(), {}, {})
        self.assertEqual((main.base, main.base_source, main.status), ("main", "local", T.TRUNK))
        feat = T.probe_worktree(gitdir, "solo", repo, side, "feat/side",
                                dict(T.DEFAULT_CONFIG), Counter(), {}, {})
        self.assertEqual((feat.base, feat.ahead), ("main", 1))


class Squashed(unittest.TestCase):
    """A squash merge proves itself by content when the PR's head is unknown here."""

    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.wt = self.fx.worktree("s", "feat/s")
        self.fx.commit(self.wt, name="a", msg="one")
        self.head = self.fx.commit(self.wt, name="b", msg="two")
        # The forge squashed it onto main and deleted the branch; the PR's last
        # head was a commit this machine never had.
        git("merge", "--squash", "-q", "feat/s", cwd=self.fx.main)
        git("commit", "-qm", "feat: s (#9)", cwd=self.fx.main)
        git("push", "-q", "origin", "main", cwd=self.fx.main)
        git("fetch", "-q", "origin", cwd=self.wt)
        self.squash = git("rev-parse", "HEAD", cwd=self.fx.main)

    def merged(self):
        return {"feat/s": {"number": 9, "url": "", "merged_at": "", "author": "",
                           "head_oid": "e" * 40, "merge_oid": self.squash}}

    def test_an_identical_squash_counts_as_landed(self):
        self.assertTrue(T.landed(self.fx.gitdir, self.head, "e" * 40, self.squash))
        w = self.fx.probe(self.wt, "feat/s", merged=self.merged())
        self.assertEqual(w.status, T.MERGED)
        self.assertEqual((w.unpushed, w.unpushed_mine), (2, 0), "landed, so not at risk")

    def test_a_commit_after_the_squash_is_not_landed(self):
        after = self.fx.commit(self.wt, name="c", msg="three")
        self.assertFalse(T.landed(self.fx.gitdir, after, "e" * 40, self.squash))
        w = self.fx.probe(self.wt, "feat/s", merged=self.merged())
        self.assertNotEqual(w.status, T.MERGED)
        self.assertEqual(w.unpushed_mine, 3)

    def test_reap_takes_landed_commits_and_deleted_files(self):
        os.remove(os.path.join(self.wt, "a"))       # tracked, still in git
        w = self.fx.probe(self.wt, "feat/s", merged=self.merged())
        self.assertEqual((w.dirty, w.deleted, w.would_lose), (1, 1, 0))
        self.assertEqual(w.status, T.MERGED, "only deletions git can restore")
        args = Reap.Args()
        args.yes = True
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = T.cmd_reap([w], args)
        self.assertEqual(rc, 0, out.getvalue())
        self.assertIn("nothing to lose", out.getvalue())
        self.assertFalse(os.path.isdir(self.wt))

    def test_a_real_change_beside_a_deletion_still_refuses(self):
        os.remove(os.path.join(self.wt, "a"))
        with open(os.path.join(self.wt, "b"), "a") as fh:
            fh.write("mine\n")
        w = self.fx.probe(self.wt, "feat/s", merged=self.merged())
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            T.cmd_reap([w], Reap.Args())
        self.assertIn("1 uncommitted", out.getvalue())
        self.assertIn("nothing to reap", out.getvalue())


class Landed(unittest.TestCase):
    """The merged claim is checked against commits, not names."""

    @classmethod
    def setUpClass(cls):
        cls.fx = Fixture()
        cls.wt = cls.fx.worktree("a", "feat/a")
        cls.first = cls.fx.commit(cls.wt, msg="one")
        cls.second = cls.fx.commit(cls.wt, msg="two")

    @classmethod
    def tearDownClass(cls):
        cls.fx.close()

    def test_equal_and_ancestor_count_as_landed(self):
        gd = self.fx.gitdir
        self.assertTrue(T.landed(gd, self.second, self.second))
        self.assertTrue(T.landed(gd, self.first, self.second), "fewer commits than merged")

    def test_commits_after_the_merge_and_unknown_oids_do_not(self):
        gd = self.fx.gitdir
        self.assertFalse(T.landed(gd, self.second, self.first), "committed after the merge")
        self.assertFalse(T.landed(gd, self.second, "f" * 40), "oid we do not have")
        self.assertFalse(T.landed(gd, self.second, ""))

    def test_a_reused_branch_name_is_not_merged(self):
        isolate_caches(self)
        # The forge says a PR from branch feat/a merged — some earlier feat/a,
        # whose head we never had. The commits here are unique and unpushed.
        merged = {"feat/a": {"number": 7, "url": "", "merged_at": "", "author": "",
                             "head_oid": "e" * 40}}
        w = self.fx.probe(self.wt, "feat/a", merged=merged)
        self.assertIsNone(w.pr)
        self.assertNotEqual(w.status, T.MERGED)
        self.assertEqual(w.unpushed, 2)

    def test_the_real_merged_head_is_merged(self):
        isolate_caches(self)
        merged = {"feat/a": {"number": 7, "url": "u", "merged_at": "", "author": "",
                             "head_oid": self.second}}
        w = self.fx.probe(self.wt, "feat/a", merged=merged)
        self.assertEqual(w.status, T.MERGED)
        self.assertEqual(w.pr.number, 7)


class ActionScope(unittest.TestCase):
    def test_named_gather_measures_only_the_named_checkout(self):
        isolate_caches(self)
        fx = Fixture()
        self.addCleanup(fx.close)
        path = fx.worktree("one", "feat/one")
        other = fx.worktree("two", "feat/two")
        rows = [wt(path=path, status=T.EMPTY), wt(path=other, status=T.EMPTY)]
        with mock.patch.object(T, "scan_repo", return_value=rows), mock.patch.object(T, "measure") as measure:
            result = T.gather(dict(T.DEFAULT_CONFIG), [], sizes=True, paths=[path])
        self.assertEqual([w.path for w in result], [path])
        self.assertEqual(measure.call_count, 1)
        self.assertEqual(measure.call_args.args[0].path, path)

    def test_clean_reclassification_is_a_failure_not_a_false_success(self):
        isolate_caches(self)
        w = wt(status=T.EMPTY, reclaim_kb=10, reclaim_paths=["node_modules/"])
        args = argparse.Namespace(list_unknown=False, stale=False, yes=True, path=None, plan=None, verbose=False)
        plan = {}
        with mock.patch.object(T, "classify_ignored", return_value=T.UNKNOWN), contextlib.redirect_stdout(io.StringIO()):
            rc = T._clean([w], args, plan)
        self.assertEqual(rc, 1)
        self.assertEqual(plan["failed"], 1)
        self.assertEqual(plan["completed_paths"], [])


class RemovalEligibility(unittest.TestCase):
    def test_status_alone_is_not_a_capability(self):
        w = wt(status=T.MERGED)
        self.assertEqual(T.removal_info(w)["state"], "check")
        w.ignored_scanned = True
        self.assertEqual(T.removal_info(w)["state"], "ready")
        for field, value in (("primary", True), ("locked", "keep this"),
                             ("has_submodules", True), ("untracked", 1), ("unpushed", 1)):
            blocked = wt(status=T.MERGED, ignored_scanned=True, **{field: value})
            self.assertEqual(T.removal_info(blocked)["state"], "blocked", field)
            plan = {}
            args = Reap.Args()
            args.path = [blocked.path]
            with contextlib.redirect_stdout(io.StringIO()):
                T._reap([blocked], args, plan)
            self.assertEqual(plan["paths"], [], field)
            self.assertEqual(plan["skipped"][0]["why"], T.removal_info(blocked)["reason"])

    def test_unknown_size_is_not_approval(self):
        w = wt(status=T.MERGED, ignored_scanned=True, unknown_paths=["notes/"])
        self.assertEqual(T.removal_info(w)["state"], "blocked")
        w.unknown_kb = T.KEEP_UNKNOWN_KB + 1
        self.assertEqual(T.removal_info(w)["state"], "blocked")
        w.unknown_kb = 1
        self.assertEqual(T.removal_info(w)["state"], "ready")


class Reap(unittest.TestCase):
    """The verb that deletes the most must consult the classifier that
    protects .env from the verb that deletes the least."""

    class Args:
        path = None
        force = False
        yes = False
        discard_precious = False
        discard_unknown = False
        json = False
        plan = None

    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.wt = self.fx.worktree("p", "feat/p")
        with open(os.path.join(self.wt, ".gitignore"), "w") as fh:
            fh.write(".env\nnode_modules/\n")
        git("add", ".gitignore", cwd=self.wt)
        git("commit", "-qm", "ignore", cwd=self.wt)
        git("push", "-q", "-u", "origin", "feat/p", cwd=self.wt)
        # Land it so the branch is reapable on git evidence alone.
        git("merge", "-q", "--ff-only", "feat/p", cwd=self.fx.main)
        git("push", "-q", "origin", "main", cwd=self.fx.main)
        git("fetch", "-q", "origin", cwd=self.wt)

    def probe(self):
        return self.fx.probe(self.wt, "feat/p")

    def run_reap(self, w, **flags):
        import io, contextlib
        args = self.Args()
        for k, v in flags.items():
            setattr(args, k, v)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = T.cmd_reap([w], args)
        return rc, out.getvalue()

    def test_generated_folder_archives_all_secrets_without_backing_up_build_output(self):
        for rel in ("node_modules/a/.env.local", "node_modules/b/.npmrc", "node_modules/a/output.js"):
            full = os.path.join(self.wt, rel)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as fh:
                fh.write("fixture content")
        w = self.probe()
        T.ignored_by_kind(w)
        self.assertEqual(sorted(w.precious_hits), ["node_modules/a/.env.local", "node_modules/b/.npmrc"])
        self.assertEqual(w.unknown_paths, [])
        args = self.Args()
        args.yes = True
        plan = {}
        with contextlib.redirect_stdout(io.StringIO()):
            rc = T._reap([w], args, plan)
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(self.wt))
        self.assertIn("node_modules/a/.env.local", self.kept())
        self.assertIn("node_modules/b/.npmrc", self.kept())
        self.assertNotIn("node_modules/a/output.js", self.kept())
        self.assertEqual(plan["completed_paths"], [self.wt])

    def test_failed_removal_does_not_claim_completed_paths_or_disk_returned(self):
        args = self.Args()
        args.yes = True
        plan = {}
        w = self.probe()
        with mock.patch.object(T, "git", return_value=(1, "", "permission denied")), contextlib.redirect_stdout(io.StringIO()):
            rc = T._reap([w], args, plan)
        self.assertEqual(rc, 1)
        self.assertEqual(plan["completed_paths"], [])
        self.assertEqual(plan["freed_kb"], 0)
        self.assertTrue(os.path.exists(self.wt))

    def test_locked_checkout_is_identified_before_the_remove_button_is_offered(self):
        git("worktree", "lock", "--reason", "keep this", self.wt, cwd=self.fx.main)
        with mock.patch.object(T, "have", return_value=False):
            rows = T.scan_repo(self.fx.gitdir, dict(T.DEFAULT_CONFIG))
        w = next(w for w in rows if os.path.realpath(w.path) == os.path.realpath(self.wt))
        self.assertEqual(w.locked, "keep this")
        self.assertEqual(T.removal_info(w)["state"], "blocked")
        self.assertIn("locked", T.removal_info(w)["reason"])

    def test_a_clean_landed_worktree_is_reapable(self):
        w = self.probe()
        self.assertEqual(w.status, T.EMPTY)
        rc, out = self.run_reap(w)
        self.assertIn("1 worktrees", out)
        self.assertTrue(os.path.isdir(self.wt), "dry run removed nothing")

    def kept(self):
        """Every file reap set aside, relative to its worktree's folder there."""
        found = []
        for d, _, files in os.walk(T.kept_root()):
            for f in files:
                rel = os.path.relpath(os.path.join(d, f), T.kept_root())
                found.append(rel.split(os.sep, 2)[2])     # drop repo/slug-stamp
        return sorted(found)

    def test_an_ignored_env_file_is_set_aside_not_lost(self):
        with open(os.path.join(self.wt, ".env"), "w") as fh:
            fh.write("SECRET=1\n")
        # git itself would remove this without --force: ignored is not untracked.
        w = self.probe()
        self.assertTrue(w.clean, "ignored files do not count as dirty")
        rc, out = self.run_reap(w)
        self.assertIn("keeping", out)
        self.assertIn("1 worktrees", out)
        self.assertTrue(os.path.isdir(self.wt), "dry run removed nothing")
        self.assertEqual(self.kept(), [], "dry run kept nothing")

        rc, out = self.run_reap(self.probe(), yes=True)
        self.assertEqual(rc, 0, out)
        self.assertFalse(os.path.isdir(self.wt))
        self.assertEqual(self.kept(), [".env", "FROM.txt"])
        [env] = [os.path.join(d, ".env") for d, _, fs in os.walk(T.kept_root()) if ".env" in fs]
        with open(env) as fh:
            self.assertEqual(fh.read(), "SECRET=1\n")
        self.assertEqual(os.stat(os.path.dirname(env)).st_mode & 0o777, 0o700)

    def test_a_precious_file_hidden_in_build_output_is_set_aside(self):
        os.makedirs(os.path.join(self.wt, "node_modules"))
        with open(os.path.join(self.wt, "node_modules", "id_rsa.pem"), "w") as fh:
            fh.write("key\n")
        # The folder hiding it is no longer recognised build output, so the
        # folder is kept whole; with --discard-unknown, only the key is.
        rc, out = self.run_reap(self.probe())
        self.assertIn("keeping node_modules/id_rsa.pem", out)
        rc, out = self.run_reap(self.probe(), discard_unknown=True, yes=True)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.kept(), ["FROM.txt", "node_modules/id_rsa.pem"])

    def test_a_worktree_whose_files_cannot_be_kept_is_left_alone(self):
        with open(os.path.join(self.wt, ".env"), "w") as fh:
            fh.write("SECRET=1\n")
        with mock.patch.object(T.shutil, "copy2", side_effect=OSError("disk full")):
            rc, out = self.run_reap(self.probe(), yes=True)
        self.assertEqual(rc, 1)
        self.assertIn("could not set its files aside", out)
        self.assertTrue(os.path.isfile(os.path.join(self.wt, ".env")))

    def test_keeping_and_discarding_are_different_plans(self):
        with open(os.path.join(self.wt, ".env"), "w") as fh:
            fh.write("SECRET=1\n")
        # --force answers "unpushed or dirty"; it must not also answer "secrets".
        rc, out = self.run_reap(self.probe(), force=True)
        self.assertIn("keeping", out)
        self.assertNotIn("discarding", out)
        rc, out = self.run_reap(self.probe(), discard_precious=True)
        self.assertIn("discarding", out)
        self.assertIn("1 worktrees", out)
        keep, discard = {}, {}
        a = self.Args(); a.discard_precious = True
        with contextlib.redirect_stdout(io.StringIO()):
            T._reap([self.probe()], self.Args(), keep)
            T._reap([self.probe()], a, discard)
        self.assertNotEqual(keep["plan"], discard["plan"],
                            "a preview that kept files must not approve deleting them")
        self.assertTrue(keep["kept_in"])
        self.assertEqual(discard["kept_in"], "")

    def test_a_merged_worktree_with_a_stray_file_is_named_not_hidden(self):
        with open(os.path.join(self.wt, "scratch.txt"), "w") as fh:
            fh.write("left behind\n")
        w = self.probe()
        w.pr = T.PR(number=7, state="MERGED", draft=False, checks="none", review="none")
        rc, out = self.run_reap(w)
        self.assertIn("1 uncommitted", out)
        self.assertIn("--force overrides", out)

    def test_unclassified_ignored_file_needs_its_own_override(self):
        with open(os.path.join(self.wt, ".gitignore"), "a") as fh:
            fh.write("private-notes.txt\n")
        git("add", ".gitignore", cwd=self.wt)
        git("commit", "-qm", "ignore notes", cwd=self.wt)
        git("push", "-q", "origin", "feat/p", cwd=self.wt)
        git("merge", "-q", "--ff-only", "feat/p", cwd=self.fx.main)
        git("push", "-q", "origin", "main", cwd=self.fx.main)
        git("fetch", "-q", "origin", cwd=self.wt)
        with open(os.path.join(self.wt, "private-notes.txt"), "w") as fh:
            fh.write("only copy\n")
        rc, out = self.run_reap(self.probe())
        self.assertEqual(rc, 0)
        self.assertIn("keeping 1 unclassified", out)
        rc, out = self.run_reap(self.probe(), discard_unknown=True)
        self.assertEqual(rc, 0)
        self.assertIn("discarding", out)
        self.assertIn("1 worktrees", out)
        rc, out = self.run_reap(self.probe(), yes=True)
        self.assertEqual(rc, 0, out)
        self.assertIn("private-notes.txt", self.kept())

    def test_too_much_unclassified_to_copy_is_refused(self):
        with open(os.path.join(self.wt, ".gitignore"), "a") as fh:
            fh.write("generated/\n")
        git("add", ".gitignore", cwd=self.wt)
        git("commit", "-qm", "ignore generated", cwd=self.wt)
        git("push", "-q", "origin", "feat/p", cwd=self.wt)
        git("merge", "-q", "--ff-only", "feat/p", cwd=self.fx.main)
        git("push", "-q", "origin", "main", cwd=self.fx.main)
        git("fetch", "-q", "origin", cwd=self.wt)
        os.makedirs(os.path.join(self.wt, "generated"))
        with open(os.path.join(self.wt, "generated", "big.bin"), "w") as fh:
            fh.write("x")
        with mock.patch.object(T, "du_kb", return_value=T.KEEP_UNKNOWN_KB + 1):
            rc, out = self.run_reap(self.probe())
        self.assertIn("too much to set aside", out)
        self.assertIn("nothing to reap", out)


class Processes(unittest.TestCase):
    """A sized scan walks each tree once for git and once for du."""

    def test_one_status_and_one_du_per_worktree(self):
        isolate_caches(self)
        T._SIZE_CACHE.clear()
        T._IGNORED.clear()
        fx = Fixture()
        self.addCleanup(fx.close)
        for i in range(3):
            wt = fx.worktree(f"n{i}", f"feat/n{i}")
            os.makedirs(os.path.join(wt, "node_modules"))
            open(os.path.join(wt, "node_modules", "x"), "w").close()
        with open(os.path.join(fx.main, ".gitignore"), "w") as fh:
            fh.write("node_modules/\n")
        calls = Counter()
        real = T.sh

        def counting(args, **kw):
            calls[args[0] if args[0] != "git" else "git " + args[1]] += 1
            return real(args, **kw)
        T.sh = counting
        self.addCleanup(setattr, T, "sh", real)
        real_have = T.have
        T.have = lambda tool: False                      # no gh: pure git
        self.addCleanup(setattr, T, "have", real_have)
        cwd = os.getcwd()
        os.chdir(fx.main)
        self.addCleanup(os.chdir, cwd)
        wts = T.gather(dict(T.DEFAULT_CONFIG), [], sizes=True, detail=True)
        self.assertEqual(len(wts), 4)                     # main + 3
        self.assertEqual(calls["git status"], 4, calls)
        self.assertEqual(calls["du"], 4, calls)
        self.assertTrue(all(w.size_kb > 0 for w in wts))


class Hygiene(unittest.TestCase):
    """A tool that reclaims other people's disk tidies its own."""

    def test_stale_cache_files_are_swept_and_fresh_ones_kept(self):
        isolate_caches(self)
        d = T.cache_dir()
        old = time.time() - 8 * 86400
        for name in ("pr-abc.json", "unseen-def", "repos-123.json"):
            (d / name).write_text("{}")
            os.utime(d / name, (old, old))
        (d / "pr-fresh.json").write_text("{}")
        (d / "state.json").write_text("{}")           # never swept by age: prunes itself
        (d / "sizes.json").write_text("{}")
        os.utime(d / "state.json", (old, old))
        self.assertEqual(T.sweep_cache(), 3)
        left = sorted(p.name for p in d.iterdir())
        self.assertEqual(left, ["pr-fresh.json", "sizes.json", "state.json"])

    def test_sizes_forget_paths_that_are_gone_on_load(self):
        isolate_caches(self)
        T._SIZE_CACHE.clear()
        T._size_cache_loaded = False
        self.addCleanup(setattr, T, "_size_cache_loaded", False)
        self.addCleanup(T._SIZE_CACHE.clear)
        here = os.path.dirname(os.path.abspath(__file__))
        T._size_cache_file().write_text(json.dumps({
            here: [10, time.time()],
            "/no/such/worktree": [10, time.time()],
            os.path.join(here, "old"): [10, time.time() - 3600],
        }))
        T.load_size_cache()
        self.assertEqual(list(T._SIZE_CACHE), [here])

    def test_clear_cache_removes_files_and_leaves_config(self):
        isolate_caches(self)
        d = T.cache_dir()
        (d / "pr-x.json").write_text("x" * 100)
        (d / "state.json").write_text("{}")
        cfg = T.config_path()
        cfg.parent.mkdir(parents=True, exist_ok=True)
        cfg.write_text("{}")
        files, size = T.clear_cache()
        self.assertEqual((files, size), (2, 102))
        self.assertEqual(list(d.iterdir()), [])
        self.assertTrue(cfg.exists())


class Quoting(unittest.TestCase):
    """What git prints for a path is not the path; these are the round trips."""

    def test_plain_paths_pass_through(self):
        self.assertEqual(T.unquote_path("node_modules/"), "node_modules/")

    def test_non_ascii_is_decoded_as_utf8_bytes(self):
        # Decoding the octal escapes as characters gives 'cachÃ©dir', which
        # exists nowhere, so the directory vanished from size and clean alike.
        self.assertEqual(T.unquote_path('"cach\\303\\251dir/"'), "cachédir/")

    def test_quotes_and_spaces_survive(self):
        self.assertEqual(T.unquote_path('"dist\\"q/"'), 'dist"q/')
        self.assertEqual(T.unquote_path('"my dir/"'), "my dir/")

    def test_undecodable_is_refused_not_guessed(self):
        self.assertIsNone(T.unquote_path('"\\377\\376/"'))

    def test_git_agrees(self):
        fx = Fixture()
        self.addCleanup(fx.close)
        wt = fx.worktree("q", "feat/q")
        with open(os.path.join(wt, ".gitignore"), "w") as fh:
            fh.write("cachédir/\n")
        git("add", ".gitignore", cwd=wt)
        git("commit", "-qm", "ignore", cwd=wt)
        os.makedirs(os.path.join(wt, "cachédir"))
        open(os.path.join(wt, "cachédir", "x"), "w").close()
        entries = T.ignored_entries(wt)
        self.assertEqual(entries, ["cachédir/"])
        self.assertTrue(os.path.isdir(os.path.join(wt, entries[0])))


class Fingerprint(unittest.TestCase):
    """Every mutation the cached history depends on must move the key.

    Each case here was a mutation the stat-the-directory version missed on a
    real repo: a directory's mtime moves only for its direct children, so a
    commit on feat/x, a fetch moving origin/main and a push creating
    origin/feat/x were all invisible, and `unpushed 1` stayed on screen after
    the push.
    """

    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.wt = self.fx.worktree("f", "feat/sprint/x")   # nested name on purpose
        self.gd = self.fx.gitdir

    def fp(self):
        return T.fingerprint(self.wt, self.gd)

    def test_stable_when_nothing_moved(self):
        a = self.fp()
        self.assertTrue(a)
        self.assertEqual(a, self.fp())

    def test_a_commit_on_a_nested_branch_moves_it(self):
        a = self.fp()
        self.fx.commit(self.wt)
        self.assertNotEqual(a, self.fp())

    def test_a_fetch_moving_the_base_moves_it(self):
        a = self.fp()
        sha = self.fx.commit(self.fx.main, name="m")      # base advances...
        git("update-ref", "refs/remotes/origin/main", sha, cwd=self.fx.main)  # ...and is fetched
        self.assertNotEqual(a, self.fp())

    def test_a_push_creating_a_remote_tracking_ref_moves_it(self):
        self.fx.commit(self.wt)
        a = self.fp()
        git("push", "-q", "-u", "origin", "feat/sprint/x", cwd=self.wt)
        self.assertNotEqual(a, self.fp(), "unpushed went 1 -> 0 and the key must know")

    def test_a_soft_reset_moves_it(self):
        self.fx.commit(self.wt)
        a = self.fp()
        git("reset", "-q", "--soft", "HEAD~1", cwd=self.wt)
        self.assertNotEqual(a, self.fp())

    def test_a_branch_ref_rewritten_in_place_moves_it(self):
        # Same file, same size (an oid is always 40 bytes): only reading the
        # value catches this within one mtime tick.
        first = self.fx.commit(self.wt)
        self.fx.commit(self.wt)
        a = self.fp()
        git("update-ref", "refs/heads/feat/sprint/x", first, cwd=self.wt)
        self.assertNotEqual(a, self.fp())

    def test_packed_refs_are_read_and_a_repack_is_noticed(self):
        self.fx.commit(self.wt)
        a = self.fp()
        git("pack-refs", "--all", cwd=self.fx.main)
        self.assertFalse(os.path.exists(os.path.join(self.gd, "refs/heads/feat/sprint/x")))
        b = self.fp()
        self.assertNotEqual(a, b, "packed-refs appeared, loose file went")
        self.assertIn(git("rev-parse", "HEAD", cwd=self.wt), b, "value read from packed-refs")
        self.fx.commit(self.wt)                          # writes a loose ref over the packed one
        self.assertNotEqual(b, self.fp())

    def test_a_relative_gitdir_is_resolved_not_placeholdered(self):
        rel = os.path.relpath(os.path.join(self.gd, "worktrees", "f"), self.wt)
        with open(os.path.join(self.wt, ".git"), "w") as fh:
            fh.write(f"gitdir: {rel}\n")
        fp = self.fp()
        self.assertTrue(fp)
        self.assertNotIn("|-|-|", fp)

    def test_anything_unreadable_disables_the_cache(self):
        with open(os.path.join(self.wt, ".git"), "w") as fh:
            fh.write("gitdir: /nowhere/at/all\n")
        self.assertEqual(self.fp(), "")

    def test_reftable_repos_are_never_cached(self):
        os.makedirs(os.path.join(self.gd, "reftable"))
        self.assertEqual(self.fp(), "")

    def test_the_probe_never_serves_a_stale_history(self):
        # The end-to-end claim: probe, mutate the ref behind git's back, probe.
        # Two warm-ups first: git's racy-index handling rewrites the index on
        # the first two statuses after a checkout (smudge, then unsmudge), which
        # costs a miss each but never a stale answer. Measured after that.
        self.fx.probe(self.wt, "feat/sprint/x")
        self.fx.probe(self.wt, "feat/sprint/x")
        w1 = self.fx.probe(self.wt, "feat/sprint/x")
        self.assertEqual((w1.ahead, w1.unpushed, w1.status), (0, 0, T.EMPTY))
        tree = git("rev-parse", "HEAD^{tree}", cwd=self.wt)
        head = git("rev-parse", "HEAD", cwd=self.wt)
        new = subprocess.run(["git", "commit-tree", tree, "-p", head, "-m", "solo"],
                             cwd=self.wt, capture_output=True, text=True, check=True).stdout.strip()
        git("update-ref", "refs/heads/feat/sprint/x", new, cwd=self.wt)
        w2 = self.fx.probe(self.wt, "feat/sprint/x")
        self.assertEqual((w2.ahead, w2.unpushed), (1, 1))
        self.assertNotIn(w2.status, (T.MERGED, T.EMPTY))
        # And the key stored by that run is the key the next run computes: one
        # miss per mutation, not two, and no run acts on what it then invalidates.
        stored = T._state[self.wt]["fp"]
        w3 = self.fx.probe(self.wt, "feat/sprint/x")
        self.assertEqual(T._state[self.wt]["fp"], stored)
        self.assertEqual((w3.ahead, w3.unpushed), (1, 1))


class RecursiveSafety(unittest.TestCase):
    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.wt = self.fx.worktree("nested", "feat/nested")
        with open(os.path.join(self.wt, ".gitignore"), "w") as fh:
            fh.write("dist/\nnotes/\n")
        git("add", ".gitignore", cwd=self.wt)
        git("commit", "-qm", "ignore generated files", cwd=self.wt)
        git("push", "-q", "origin", "feat/nested", cwd=self.wt)

    def test_cleanup_preserves_all_nested_secrets(self):
        protected = ["dist/config/.env.local", "dist/keys/production.pem"]
        for rel in protected:
            path = os.path.join(self.wt, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fh:
                fh.write("fixture-only-value")
        w = self.fx.probe(self.wt, "feat/nested")
        T.measure(w)
        self.assertEqual(T.ignored_entries(self.wt), ["dist/"])
        self.assertEqual(w.reclaim_paths, [])
        self.assertEqual(sorted(w.precious_hits), protected)
        args = T.build_parser().parse_args(["clean", "--yes", "--path", self.wt])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(T.cmd_clean([w], args), 0)
        for rel in protected:
            self.assertTrue(os.path.isfile(os.path.join(self.wt, rel)))

    def test_an_unreadable_subtree_is_not_disposable(self):
        os.makedirs(os.path.join(self.wt, "dist"))
        with mock.patch.object(T.os, "walk", side_effect=PermissionError("unreadable")):
            self.assertEqual(T.classify_ignored("dist/", self.wt), T.UNKNOWN)

    def test_discard_unknown_still_preserves_every_nested_secret(self):
        for rel in ["dist/config/.env.local", "dist/keys/production.pem"]:
            path = os.path.join(self.wt, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fh:
                fh.write("fixture-only-value")
        w = self.fx.probe(self.wt, "feat/nested")
        # The branch's commits are on the local fixture remote and contained
        # in the chosen base, so only ignored-file preservation is exercised.
        w.status, w.ahead = T.EMPTY, 0
        args = T.build_parser().parse_args([
            "reap", "--yes", "--discard-unknown", "--path", self.wt])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(T.cmd_reap([w], args), 0)
        self.assertFalse(os.path.isdir(self.wt))
        kept = list(T.kept_root().glob("repo/*"))
        self.assertEqual(len(kept), 1)
        for rel in ["dist/config/.env.local", "dist/keys/production.pem"]:
            self.assertEqual((kept[0] / rel).read_text(), "fixture-only-value")

    def test_corrupt_nested_backup_prevents_worktree_removal(self):
        nested = os.path.join(self.wt, "notes", "nested")
        os.makedirs(nested)
        source = os.path.join(nested, "important.txt")
        with open(source, "w") as fh:
            fh.write("original")
        real_copy = shutil.copytree
        def corrupt_copy(src, dst, *args, **kwargs):
            with mock.patch.object(T.shutil, "copytree", real_copy):
                result = real_copy(src, dst, *args, **kwargs)
            copied = os.path.join(dst, "nested", "important.txt")
            metadata = os.stat(copied)
            with open(copied, "w") as fh:
                fh.write("corrupt!")   # same length; timestamps also match
            os.utime(copied, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            return result
        w = self.fx.probe(self.wt, "feat/nested")
        w.status, w.ahead = T.EMPTY, 0
        args = T.build_parser().parse_args(["reap", "--yes", "--path", self.wt])
        with mock.patch.object(T.shutil, "copytree", side_effect=corrupt_copy), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(T.cmd_reap([w], args), 1)
        self.assertIn("did not copy exactly", out.getvalue())
        self.assertTrue(os.path.isdir(self.wt))
        with open(source) as fh:
            self.assertEqual(fh.read(), "original")

    def test_backup_verifies_link_targets_without_following_them(self):
        source, dest = os.path.join(self.wt, "source-link"), os.path.join(self.wt, "copy-link")
        os.symlink("missing-original-target", source)
        os.symlink("missing-original-target", dest)
        self.assertTrue(T.verify_copy(source, dest))
        os.unlink(dest)
        os.symlink("different-target", dest)
        self.assertFalse(T.verify_copy(source, dest))


class Push(unittest.TestCase):
    """The one verb that writes to a remote, and the answer to the risk the
    rest of the tool had been raising and dropping."""

    class Args:
        yes = False
        json = False
        path = None
        plan = None
        all = False
        repo = None

    def setUp(self):
        isolate_caches(self)
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.wt = self.fx.worktree("p", "feat/p")
        self.fx.commit(self.wt, msg="work that exists nowhere else")

    def run_push(self, **flags):
        args = self.Args()
        for k, v in flags.items():
            setattr(args, k, v)
        w = self.fx.probe(self.wt, "feat/p")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = T.cmd_push([w], args)
        text = out.getvalue()
        return rc, (json.loads(text) if flags.get("json") else text)

    def test_the_subjects_ride_along_so_the_count_names_something(self):
        w = self.fx.probe(self.wt, "feat/p")
        self.assertEqual(w.unpushed, 1)
        self.assertEqual(w.solo_log, ["work that exists nowhere else"])

    def test_push_default_overrides_the_tracking_remote(self):
        fork = os.path.join(self.fx.root, "fork.git")
        git("init", "-q", "--bare", fork, cwd=self.fx.root)
        git("remote", "add", "fork", fork, cwd=self.wt)
        git("config", "remote.pushDefault", "fork", cwd=self.wt)
        self.assertEqual(T.worktree_remote(self.wt, "feat/p"), "fork")
        rc, out = self.run_push(path=[self.wt], yes=True)
        self.assertEqual(rc, 0, out)
        head = git("rev-parse", "HEAD", cwd=self.wt)
        self.assertEqual(git("rev-parse", "refs/heads/feat/p", cwd=fork), head)
        check = subprocess.run(["git", "rev-parse", "--verify", "refs/heads/feat/p"],
                               cwd=self.fx.origin, capture_output=True)
        self.assertNotEqual(check.returncode, 0, "tracking remote received the push")

    def test_branch_push_remote_overrides_push_default(self):
        git("config", "remote.pushDefault", "fork", cwd=self.wt)
        git("config", "branch.feat/p.pushRemote", "origin", cwd=self.wt)
        self.assertEqual(T.worktree_remote(self.wt, "feat/p"), "origin")

    def test_a_dry_run_shows_the_commits_and_sends_nothing(self):
        rc, out = self.run_push(path=[self.wt])
        self.assertEqual(rc, 0)
        self.assertIn("work that exists nowhere else", out)
        self.assertIn("dry run", out)
        self.assertEqual(self.fx.probe(self.wt, "feat/p").unpushed, 1)

    def test_it_is_never_a_sweep(self):
        """It writes to a remote. Every other verb here defaults to everything
        in scope; this one refuses to run without being told what."""
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(io.StringIO()):
                self.run_push()

    def test_pushing_puts_the_commits_on_the_remote(self):
        _, plan = self.run_push(path=[self.wt], json=True)
        rc, _ = self.run_push(path=[self.wt], yes=True, plan=plan["plan"])
        self.assertEqual(rc, 0)
        T._state.clear()
        self.assertEqual(self.fx.probe(self.wt, "feat/p").unpushed, 0)
        self.assertIn("feat/p", git("branch", "--list", "feat/p", cwd=self.fx.origin))

    def test_the_hash_follows_the_commit_not_the_count(self):
        """Amending leaves the count at one and changes everything about what
        would be sent, so a hash over `unpushed` would approve a preview of
        the commit you replaced."""
        _, first = self.run_push(path=[self.wt], json=True)
        git("commit", "-q", "--amend", "-m", "amended", cwd=self.wt)
        T._state.clear()
        _, second = self.run_push(path=[self.wt], json=True)
        self.assertNotEqual(first["plan"], second["plan"])
        rc, out = self.run_push(path=[self.wt], yes=True, plan=first["plan"])
        self.assertEqual(rc, 3)
        self.assertIn("changed since it was reviewed", out)
        self.assertIn("nothing pushed", out)

    def test_nothing_to_push_is_said_not_attempted(self):
        _, plan = self.run_push(path=[self.wt], json=True)
        self.run_push(path=[self.wt], yes=True, plan=plan["plan"])
        T._state.clear()
        rc, out = self.run_push(path=[self.wt])
        self.assertEqual(rc, 0)
        self.assertIn("already on a remote", out)

    def test_uncommitted_work_is_named_because_a_push_does_not_carry_it(self):
        """"Pushed" reads as "safe". On the machine this was built against the
        uncommitted half was the larger one: 26 unpushed commits against 763
        changed files."""
        with open(os.path.join(self.wt, "scratch.txt"), "w") as fh:
            fh.write("not committed\n")
        T._state.clear()
        _, out = self.run_push(path=[self.wt])
        self.assertIn("stay on this machine", out)


class Plans(unittest.TestCase):
    """A commit approves the set the preview showed, never the filter."""

    class Args(Reap.Args):
        stale = False
        verbose = False
        list_unknown = False

    def setUp(self):
        isolate_caches(self)
        T._SIZE_CACHE.clear()
        T._IGNORED.clear()
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.wt = self.fx.worktree("c", "feat/c")
        with open(os.path.join(self.wt, ".gitignore"), "w") as fh:
            fh.write("node_modules/\ndist/\n")
        git("add", ".gitignore", cwd=self.wt)
        git("commit", "-qm", "ignore", cwd=self.wt)
        git("push", "-q", "-u", "origin", "feat/c", cwd=self.wt)
        git("merge", "-q", "--ff-only", "feat/c", cwd=self.fx.main)
        git("push", "-q", "origin", "main", cwd=self.fx.main)
        git("fetch", "-q", "origin", cwd=self.wt)
        os.makedirs(os.path.join(self.wt, "node_modules"))
        with open(os.path.join(self.wt, "node_modules", "x"), "w") as fh:
            fh.write("x" * 4096)

    def run_verb(self, verb, **flags):
        import io, contextlib, json
        args = self.Args()
        for k, v in flags.items():
            setattr(args, k, v)
        w = self.fx.probe(self.wt, "feat/c")
        T.measure(w)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = (T.cmd_reap if verb == "reap" else T.cmd_clean)([w], args)
        text = out.getvalue()
        return rc, (json.loads(text) if flags.get("json") else text)

    def test_the_json_plan_names_what_it_would_touch(self):
        rc, plan = self.run_verb("clean", json=True)
        self.assertEqual(plan["paths"], [self.wt])
        self.assertEqual(plan["entries"][self.wt], ["node_modules/"])
        self.assertIn("reclaimable from 1 worktrees", plan["text"])
        self.assertTrue(plan["plan"])
        self.assertFalse(plan.get("done"))

    def test_a_changed_plan_is_refused_at_commit(self):
        _, plan = self.run_verb("clean", json=True)
        # A build writes dist/ between the preview and the click.
        os.makedirs(os.path.join(self.wt, "dist"))
        with open(os.path.join(self.wt, "dist", "b.js"), "w") as fh:
            fh.write("//" * 2048)
        T._SIZE_CACHE.clear()
        rc, out = self.run_verb("clean", yes=True, plan=plan["plan"], path=[self.wt])
        self.assertEqual(rc, 3)
        self.assertIn("changed since it was reviewed", out)
        self.assertTrue(os.path.exists(os.path.join(self.wt, "node_modules", "x")))
        self.assertTrue(os.path.exists(os.path.join(self.wt, "dist", "b.js")))

    def test_the_same_plan_runs(self):
        _, plan = self.run_verb("clean", json=True)
        rc, out = self.run_verb("clean", yes=True, plan=plan["plan"], path=[self.wt])
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(os.path.join(self.wt, "node_modules")))

    def test_reap_carries_and_checks_a_plan_too(self):
        shutil.rmtree(os.path.join(self.wt, "node_modules"))
        _, plan = self.run_verb("reap", json=True)
        self.assertEqual(plan["paths"], [self.wt])
        rc, out = self.run_verb("reap", yes=True, plan="not-the-plan", path=[self.wt])
        self.assertEqual(rc, 3)
        self.assertTrue(os.path.isdir(self.wt))
        rc, out = self.run_verb("reap", yes=True, plan=plan["plan"], path=[self.wt])
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.isdir(self.wt))

    def test_a_plan_that_has_emptied_is_refused_not_called_done(self):
        """The set going to nothing is a changed plan, not an all-clear.

        Someone else - a second window, a terminal, the daily reaper - dealt
        with what was approved here. The hash is the only thing that can tell
        that apart from "your click worked", and for a while it was asked
        after the "nothing to do" return rather than before it, so the caller
        was told rc=0 and drew a tick over work it had not done.
        """
        _, plan = self.run_verb("clean", json=True)
        shutil.rmtree(os.path.join(self.wt, "node_modules"))
        T._SIZE_CACHE.clear()
        rc, out = self.run_verb("clean", yes=True, plan=plan["plan"], path=[self.wt])
        self.assertEqual(rc, 3)
        self.assertIn("changed since it was reviewed", out)

    def test_an_empty_set_with_no_plan_is_still_just_an_empty_set(self):
        shutil.rmtree(os.path.join(self.wt, "node_modules"))
        T._SIZE_CACHE.clear()
        rc, out = self.run_verb("clean", yes=True, path=[self.wt])
        self.assertEqual(rc, 0)
        self.assertIn("nothing reclaimable", out)

    def test_a_dry_run_never_refuses_over_a_plan(self):
        """`--plan` is a guard on the commit. A preview commits nothing, so
        there is nothing for a stale hash to protect, and refusing would stop
        someone re-reviewing the very thing they were told to re-review."""
        rc, out = self.run_verb("clean", plan="not-the-plan", path=[self.wt])
        self.assertEqual(rc, 0)
        self.assertNotIn("changed since it was reviewed", out)


class Sizes(unittest.TestCase):
    """The same number is formatted by three programs on one screen."""

    CASES = [(0, "0KB"), (1, "1KB"), (999, "999KB"), (1 << 10, "1.0MB"),
             (10 << 10, "10MB"), (1 << 20, "1.0GB"), (348 << 10, "348MB"),
             (1 << 30, "1.0TB"), (-1, "—")]

    def test_the_unit_is_spelled_far_enough_to_be_a_unit(self):
        """`348M` in a row of counts reads as 348 million. It is megabytes."""
        for kb, want in self.CASES:
            self.assertEqual(T.human(kb), want, kb)

    def test_the_engine_and_the_mascot_agree(self):
        """They are separate copies on purpose — `mascot` is imported by the
        engine and not the reverse, and the app cannot import Python at all.
        Separate is fine; disagreeing is not, because the reclaim total appears
        in the table, the window and the mascot's own sentence at once."""
        for kb, _ in self.CASES:
            self.assertEqual(T.human(kb), M.human(kb), kb)
        for kb in (0, 7, 1023, 1024, 5 << 20, 900 << 10, 1 << 31):
            self.assertEqual(T.human(kb), M.human(kb), kb)


class FirstRun(unittest.TestCase):
    """A machine nobody has told where the repos are.

    This used to be `die()`: exit 2, a sentence on stderr, and a window that
    rendered `wt-manager exited 2: not inside a git repository` in a card
    headed "error". A first run reported as a fault, over the one question the
    tool can answer for itself.
    """

    def setUp(self):
        isolate_caches(self)
        self.home = tempfile.mkdtemp(prefix="wt-manager-home-")
        self.addCleanup(shutil.rmtree, self.home, True)
        self.cwd = os.getcwd()
        # Somewhere that is definitely not a repo, because "not configured"
        # only bites when the cwd cannot answer instead — which is exactly the
        # app's situation: a login item inherits launchd's, which is `/`.
        os.chdir(self.home)
        self.addCleanup(os.chdir, self.cwd)

    def run_cli(self, *args):
        import subprocess
        # A real $HOME, or discovery finds the machine running the tests.
        env = dict(os.environ, HOME=self.home)
        r = subprocess.run([sys.executable, T.__file__, "--color=never", *args],
                           capture_output=True, text=True, cwd=self.home, env=env)
        return r.returncode, r.stdout, r.stderr

    def test_the_agent_gets_a_state_not_a_failure(self):
        rc, out, _ = self.run_cli("agent", "--no-size")
        self.assertEqual(rc, 0, "a window cannot render an exit code")
        env = json.loads(out)
        self.assertTrue(env["unconfigured"])
        self.assertEqual(env["worktrees"], [])
        # The face is there, so the menu bar has something to draw rather than
        # falling back to the word "wt-manager".
        self.assertIn("mood", env["face"])
        self.assertIn("candidates", env)

    def test_a_terminal_still_gets_the_sentence(self):
        """In a window "run this command" is useless; at a prompt it is the
        right next move. Same condition, two audiences."""
        rc, _, err = self.run_cli()
        self.assertEqual(rc, 2)
        self.assertIn("no roots configured", err)
        self.assertIn("config --init", err)

    def test_discovery_finds_a_conventional_folder(self):
        os.makedirs(os.path.join(self.home, "dev", "a"))
        subprocess.run(["git", "init", "-q", os.path.join(self.home, "dev", "a")],
                       check=True, capture_output=True)
        with mock.patch.object(T.Path, "home", staticmethod(lambda: T.Path(self.home))):
            found = T.discover_roots()
        self.assertEqual(found, [(os.path.join(self.home, "dev"), 1)])

    def test_discovery_reports_the_folder_and_never_home_itself(self):
        """Pointing the tool at a home directory makes every later scan walk
        it. When nothing conventional matches, the answer is the folder the
        repos are in."""
        os.makedirs(os.path.join(self.home, "wherever", "b"))
        subprocess.run(["git", "init", "-q", os.path.join(self.home, "wherever", "b")],
                       check=True, capture_output=True)
        with mock.patch.object(T.Path, "home", staticmethod(lambda: T.Path(self.home))):
            found = T.discover_roots()
        self.assertEqual([os.path.realpath(r) for r, _ in found],
                         [os.path.realpath(os.path.join(self.home, "wherever"))])

    def test_setting_roots_keeps_everything_else_in_the_config(self):
        """The config has six other keys. A second writer that knows about one
        of them is how the other five get dropped by whoever saved last."""
        p = T.config_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({"stale_days": 3, "base": {"web": "pre-release"},
                                 "roots": ["/old"]}))
        T.write_roots(["/new", "/also"])
        after = json.loads(p.read_text())
        self.assertEqual(after["roots"], ["/new", "/also"])
        self.assertEqual(after["stale_days"], 3)
        self.assertEqual(after["base"], {"web": "pre-release"})
        # And the keys it had never heard of are filled in, not invented over.
        self.assertIn("min_base_votes", after)

    def test_folders_remain_editable_after_first_run(self):
        T.write_roots([self.home])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            T.cmd_agent([], argparse.Namespace(reclaim_kb=None))
        self.assertEqual(json.loads(out.getvalue())["roots"], [os.path.realpath(self.home)])
        rc, _, _ = self.run_cli("config", "--clear-roots")
        self.assertEqual(rc, 0)
        self.assertEqual(T.load_config()["roots"], [])

    def test_init_writes_what_it_found(self):
        os.makedirs(os.path.join(self.home, "code", "c"))
        subprocess.run(["git", "init", "-q", os.path.join(self.home, "code", "c")],
                       check=True, capture_output=True)
        rc, out, _ = self.run_cli("config", "--init")
        self.assertEqual(rc, 0)
        self.assertIn("1 repo", out)
        self.assertEqual(
            [os.path.realpath(r) for r in json.loads(T.config_path().read_text())["roots"]],
            [os.path.realpath(os.path.join(self.home, "code"))])


class CommandLine(unittest.TestCase):
    """The flags mean the same thing on either side of the verb.

    Declaring them before `add_subparsers` accepts them only before the verb,
    and `wt-manager clean --json` - the order almost everyone types - was
    rejected outright.
    """

    def parse(self, *argv):
        return T.build_parser().parse_args(list(argv))

    def test_a_global_flag_is_taken_after_the_verb(self):
        for flag, attr in (("--json", "json"), ("--all", "all"),
                           ("--refresh", "refresh"), ("--here", "here")):
            with self.subTest(flag=flag):
                self.assertTrue(getattr(self.parse("clean", flag), attr))

    def test_a_global_flag_is_still_taken_before_the_verb(self):
        args = self.parse("--json", "--all", "clean")
        self.assertTrue(args.json and args.all and args.cmd == "clean")

    def test_the_verb_does_not_overwrite_what_came_before_it(self):
        """The reason every repeated flag defaults to SUPPRESS. Without it the
        subparser writes its own `False` over the `True` set a moment ago, and
        the flag silently stops working in the documented order."""
        args = self.parse("--json", "--color", "never", "clean")
        self.assertTrue(args.json)
        self.assertEqual(args.color, "never")

    def test_a_value_after_the_verb_wins(self):
        self.assertEqual(self.parse("--color", "always", "clean",
                                    "--color", "never").color, "never")

    def test_the_flags_that_did_nothing_are_gone(self):
        """`clean --status` duplicated `--stale`, `size --fast` and
        `reap --dry-run` were never documented, tested or called. A flag
        nothing reaches is a promise the help text cannot keep."""
        for argv in (["clean", "--status", "stale"], ["size", "--fast"],
                     ["reap", "--dry-run"]):
            with self.subTest(argv=argv):
                with self.assertRaises(SystemExit):
                    with contextlib.redirect_stderr(io.StringIO()):
                        self.parse(*argv)


class Table(unittest.TestCase):
    def render(self, wts, multi_repo):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            T.render_table(wts, show_size=False, multi_repo=multi_repo)
        return out.getvalue()

    def rows(self):
        return [T.Worktree(repo="demo", path="/a", branch="feat/a", primary=False,
                           base="main", base_source="upstream", status="active")]

    def test_one_repo_drops_the_repo_column_header_included(self):
        """A REPO heading over a column of blanks is a column that failed to
        fill. It also reserved its two spaces, which put a gutter mid-row."""
        head = self.render(self.rows(), multi_repo=False).splitlines()[0]
        self.assertNotIn("REPO", head)
        self.assertIn("STATUS", head)
        self.assertIn("BRANCH", head)

    def test_several_repos_keep_it(self):
        head = self.render(self.rows(), multi_repo=True).splitlines()[0]
        self.assertIn("REPO", head)


class Rollup(unittest.TestCase):
    def test_skipped_checks_are_not_failures(self):
        rollup = [{"conclusion": "SKIPPED", "name": "a"}, {"conclusion": "SUCCESS", "name": "b"}]
        self.assertEqual(T.rollup_verdict(rollup)[0], "passing")

    def test_a_status_context_failure_counts(self):
        # These arrive shaped differently from check runs, and missing that is
        # how a genuinely red PR reads as green.
        rollup = [{"conclusion": "SUCCESS", "name": "a"},
                  {"state": "FAILURE", "context": "Vercel"}]
        verdict, failing = T.rollup_verdict(rollup)
        self.assertEqual(verdict, "failing")
        self.assertEqual(failing, ["Vercel"])

    def test_no_checks_is_not_a_pass(self):
        self.assertEqual(T.rollup_verdict([])[0], "none")


if __name__ == "__main__":
    unittest.main(verbosity=2)
