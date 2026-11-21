"""Offline unit tests for bin/peerpanel. Pure functions only: no peer CLI is called.

    python3 -m unittest evals/test_peerpanel.py -v
"""
import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_loader = importlib.machinery.SourceFileLoader("peerpanel", str(ROOT / "bin" / "peerpanel"))
_spec = importlib.util.spec_from_loader("peerpanel", _loader)
pp = importlib.util.module_from_spec(_spec)
_loader.exec_module(pp)

ENV = {
    "bt_agy_model": "gemini-4-neon-high", "bt_agy_fast_model": "gemini-3.8-flash-high",
    "bt_codex_model": "gpt-6.2-astra", "bt_codex_home": "/tmp/x-codex",
    "bt_cursor_model": "grok-4.7-high", "bt_xai_via": "cursor",
    "bt_opencode_model": "zai-coding-plan/glm-5.3", "bt_opencode_variant": "max",
    "bt_opencode_config": "/tmp/x-oc", "bt_claude_model": "claude-opus-5-5[1m]",
}


def jl(*events):
    return "\n".join(json.dumps(e) for e in events)


class Parse(unittest.TestCase):
    def test_codex_keeps_final_message(self):
        out = jl({"type": "item.completed", "item": {"type": "agent_message", "text": "I'll read the files first."}},
                 {"type": "item.completed", "item": {"type": "agent_message", "text": "Answer. GROUNDED"}})
        self.assertEqual(pp.parse_output("codex", out), ("Answer. GROUNDED", ""))

    def test_codex_error_event(self):
        ans, err = pp.parse_output("codex", jl({"type": "error", "message": "You've hit your usage limit."}))
        self.assertEqual(ans, "")
        self.assertIn("usage limit", err)

    def test_error_after_progress_is_a_failure(self):
        out = jl({"type": "text", "part": {"text": "Reading the files."}},
                 {"type": "error", "error": {"message": "rate limit exceeded"}})
        self.assertEqual(pp.parse_output("opencode", out), ("", "rate limit exceeded"))

    def test_answer_after_error_recovers(self):
        out = jl({"type": "error", "message": "stream reconnected"},
                 {"type": "item.completed", "item": {"type": "agent_message", "text": "Final."}})
        self.assertEqual(pp.parse_output("codex", out), ("Final.", ""))

    def test_opencode_last_text(self):
        out = jl({"type": "text", "part": {"text": "Reading."}}, {"type": "text", "part": {"text": "Final."}})
        self.assertEqual(pp.parse_output("opencode", out)[0], "Final.")

    def test_single_object_clis(self):
        self.assertEqual(pp.parse_output("agy", json.dumps({"status": "SUCCESS", "response": "a"}))[0], "a")
        self.assertEqual(pp.parse_output("agy", json.dumps({"status": "ERROR", "error": "quota"}))[1], "quota")
        self.assertEqual(pp.parse_output("cursor", json.dumps({"is_error": False, "result": "b"}))[0], "b")
        self.assertEqual(pp.parse_output("cursor", json.dumps({"is_error": True, "result": "x"}))[1], "x")
        self.assertEqual(pp.parse_output("grok", json.dumps({"type": "error", "message": "billing"}))[1], "billing")
        self.assertEqual(pp.parse_output("claude", "banner {x}\n" + json.dumps({"result": "c"}))[0], "c")

    def test_non_json_is_an_error_not_an_answer(self):
        self.assertEqual(pp.parse_output("cursor", "Error: something broke")[0], "")
        self.assertIn("broke", pp.parse_output("cursor", "Error: something broke")[1])
        self.assertEqual(pp.parse_output("agy", json.dumps([1, 2]))[0], "")


class Classify(unittest.TestCase):
    def c(self, **kw):
        base = dict(answer="", err="", stderr="", rc=0, timed_out=False, nonce=None)
        base.update(kw)
        return pp.classify(**base)

    def test_named_failures(self):
        self.assertEqual(self.c(err="You've hit your usage limit"), "cap")
        self.assertEqual(self.c(stderr="Model unavailable on Free"), "cap")
        self.assertEqual(self.c(stderr="Error: Not logged in", rc=1), "auth")
        self.assertEqual(self.c(stderr="Connection lost, reconnecting\nRetriableError: [unavailable] Error", rc=1),
                         "connection")
        self.assertEqual(self.c(stderr="error: unknown flag --pure", rc=2), "cli-changed")
        self.assertEqual(self.c(err="model gemini-9 not found"), "model")
        self.assertEqual(self.c(timed_out=True, rc=-9), "timeout")
        self.assertEqual(self.c(), "empty")

    def test_timeout_beats_partial_stream(self):
        self.assertEqual(self.c(answer="I'll read the files first.", timed_out=True, rc=-9), "timeout")

    def test_structured_error_beats_partial_stream(self):
        self.assertEqual(self.c(answer="Reading.", err="You've hit your usage limit", rc=1), "cap")
        self.assertEqual(self.c(answer="Final answer.", err="stream reconnected", rc=0), "ok")

    def test_old_stderr_noise_ignored(self):
        noise = "GET /v1 401 earlier\n" + "\n".join("line %d" % i for i in range(40))
        self.assertEqual(self.c(stderr=noise, timed_out=True), "timeout")
        self.assertEqual(self.c(stderr=noise), "empty")

    def test_hijack_needs_a_real_marker(self):
        self.assertEqual(self.c(answer="The prompt tells peers to ignore agent buses and herdr hooks."), "ok")
        self.assertEqual(self.c(answer="Joining the agent bus now."), "hijacked")
        long_review = "Joining the agent bus is what the hook does. " + "Finding detail. " * 80
        self.assertEqual(self.c(answer=long_review), "ok")
        self.assertEqual(self.c(answer="[hcom:toku] " + "x" * 2000), "hijacked")

    def test_answers(self):
        self.assertEqual(self.c(answer="fine"), "ok")
        self.assertEqual(self.c(answer="[hcom:toku] joining"), "hijacked")
        self.assertEqual(self.c(answer="I'll check the local agent bus identity"), "hijacked")
        self.assertEqual(self.c(answer="PP-ABC123", nonce="PP-ABC123"), "ok")
        self.assertEqual(self.c(answer="a poem", nonce="PP-ABC123"), "off-task")


class Commands(unittest.TestCase):
    def flag(self, argv, name):
        return argv[argv.index(name) + 1]

    def test_read_only_modes(self):
        a = pp.build_cmd("codex", "Q", ENV, "/r")[0]
        self.assertEqual(self.flag(a, "-s"), "read-only")
        self.assertEqual(self.flag(a, "-C"), "/r")
        self.assertEqual(self.flag(a, "-m"), "gpt-6.2-astra")
        a = pp.build_cmd("agy", "Q", ENV, "/r")[0]
        self.assertEqual(self.flag(a, "--mode"), "plan")
        self.assertEqual(self.flag(a, "--add-dir"), "/r")
        # plan mode is a slash command in agy; disabling slash commands lets it write files (seen live)
        self.assertNotIn("--disable-slash-commands", a)
        a = pp.build_cmd("opencode", "Q", ENV, "/r")[0]
        self.assertEqual(self.flag(a, "--agent"), "plan")
        self.assertEqual(self.flag(a, "-m"), "zai-coding-plan/glm-5.3#max")
        argv, env, cwd, _, _ = pp.build_cmd("xai", "Q", ENV, "/r")
        self.assertEqual(self.flag(argv, "--mode"), "ask")
        self.assertEqual(env["CMUX_CURSOR_HOOKS_DISABLED"], "1")
        self.assertEqual(cwd, "/r")
        g = dict(ENV, bt_xai_via="grok", bt_grok_model="grok-4.7")
        a = pp.build_cmd("xai", "Q", g, "/r")[0]
        self.assertIn("--no-subagents", a)
        self.assertEqual(self.flag(a, "--permission-mode"), "plan")
        a = pp.build_cmd("claude", "Q", ENV, "/r")[0]
        self.assertIn("Bash", self.flag(a, "--disallowedTools"))

    def test_identity_isolation(self):
        self.assertEqual(pp.build_cmd("codex", "Q", ENV, "/r")[1]["CODEX_HOME"], "/tmp/x-codex")
        oc = pp.build_cmd("opencode", "Q", ENV, "/r")[1]
        self.assertEqual(oc["XDG_CONFIG_HOME"], "/tmp/x-oc")
        self.assertEqual(oc["OPENCODE_DISABLE_PROJECT_CONFIG"], "1")
        self.assertIn("--safe-mode", pp.build_cmd("claude", "Q", ENV, "/r")[0])

    def test_peer_aliases(self):
        self.assertEqual(pp.parse_peers("gemini,gpt,grok,glm"), ["agy", "codex", "xai", "opencode"])


class Retry(unittest.TestCase):
    def setUp(self):
        self.models = []
        self.real = pp.run_once

    def tearDown(self):
        pp.run_once = self.real

    def script(self, statuses):
        seq = list(statuses)

        def fake(peer, prompt, env, root, timeout, outdir=None, tag="", model_override=None, nonce=None):
            self.models.append(model_override)
            s = seq.pop(0)
            return {"status": s, "model": model_override, "seconds": 1, "answer": "x" if s == "ok" else ""}
        pp.run_once = fake

    def test_cap_not_retried(self):
        self.script(["cap"])
        r = pp.run_peer("codex", "Q", ENV, "/r", 10)
        self.assertEqual((r["status"], len(r["attempts"])), ("cap", 1))

    def test_timeout_retried_on_fast_agy_model(self):
        self.script(["timeout", "ok"])
        r = pp.run_peer("agy", "Q", ENV, "/r", 10)
        self.assertEqual((r["status"], len(r["attempts"])), ("ok", 2))
        self.assertEqual(self.models[1], "gemini-3.8-flash-high")

    def test_connection_retried_once(self):
        self.script(["connection", "connection"])
        r = pp.run_peer("xai", "Q", ENV, "/r", 10)
        self.assertEqual((r["status"], len(r["attempts"])), ("connection", 2))

    def test_codex_model_error_falls_back_to_sol(self):
        self.script(["model", "ok"])
        r = pp.run_peer("codex", "Q", ENV, "/r", 10)
        self.assertEqual(self.models[1], "gpt-6.2-sol")
        self.assertEqual(r["status"], "ok")

    def test_no_retry_past_deadline(self):
        self.script(["empty"])
        r = pp.run_peer("opencode", "Q", ENV, "/r", 10, deadline=time.time() + 5)
        self.assertEqual(len(r["attempts"]), 1)


class Process(unittest.TestCase):
    """run_once against a real child process (python -c), no peer CLI involved."""

    def setUp(self):
        self.real = pp.build_cmd
        self.root = tempfile.mkdtemp(prefix="pp-proc-")

    def tearDown(self):
        pp.build_cmd = self.real

    def child(self, code):
        def fake(peer, prompt, env, root, model_override=None, timeout=480):
            return [sys.executable, "-c", code], dict(os.environ), self.root, "cursor", "m"
        pp.build_cmd = fake

    def test_lingering_grandchild_does_not_hold_the_seat(self):
        # the child answers and exits; a grandchild keeps the inherited stdout open for 30s
        self.child("import json, subprocess, sys; "
                   "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
                   "print(json.dumps({'is_error': False, 'result': 'done'}))")
        t0 = time.time()
        r = pp.run_once("xai", "Q", ENV, self.root, 20)
        self.assertEqual(r["status"], "ok")
        self.assertLess(time.time() - t0, 10)

    def test_timeout_is_enforced(self):
        self.child("import time; time.sleep(30)")
        t0 = time.time()
        r = pp.run_once("xai", "Q", ENV, self.root, 2)
        self.assertEqual(r["status"], "timeout")
        self.assertLess(time.time() - t0, 10)


class Brief(unittest.TestCase):
    def setUp(self):
        t = Path(tempfile.mkdtemp(prefix="pp-test-"))
        self.b = t / "brief"
        self.src = t / "proj" / "src"
        self.missing = t / "nope.txt"
        self.src.mkdir(parents=True)
        (self.src / "a.py").write_text("def pay():\n    retry()\n    charge()\n")
        pp.cmd_brief(type("A", (), {"action": "new", "dir": str(self.b), "request_file": None})())

    def fill(self):
        (self.b / "request.md").write_text("Is the retry in a.py safe? I think it double-charges.\n")
        (self.b / "question.md").write_text("Is the retry safe? Under 300 words.\n")
        (self.b / "sources.txt").write_text("# sources\n%s\n" % self.src)

    def test_scaffold_fails_check(self):
        self.assertTrue(pp.check_brief(self.b, quiet=True)[0])

    def test_missing_source_fails(self):
        self.fill()
        (self.b / "sources.txt").write_text("%s\n%s\n" % (self.src, self.missing))
        errs, _ = pp.check_brief(self.b, quiet=True)
        self.assertTrue(any("do not exist" in e for e in errs))

    def test_no_sources_warns(self):
        self.fill()
        (self.b / "sources.txt").write_text("")
        errs, warns = pp.check_brief(self.b, quiet=True)
        self.assertFalse(errs)
        self.assertTrue(any("only text you wrote" in w for w in warns))
        # with no sources, peers get an empty folder, never the brief folder that holds host-view.md
        _, root = pp.build_prompt(self.b, "agy")
        self.assertNotEqual(root, self.b.resolve())
        self.assertEqual(list(root.iterdir()), [])

    def test_brief_inside_read_root(self):
        self.fill()
        inner = self.src / "brief"
        pp.cmd_brief(type("A", (), {"action": "new", "dir": str(inner), "request_file": None})())
        for f in ("request.md", "question.md", "sources.txt"):
            (inner / f).write_text((self.b / f).read_text())
        errs, warns = pp.check_brief(inner, quiet=True)
        self.assertFalse(errs)
        self.assertTrue(any("read root" in w for w in warns))
        (inner / "host-view.md").write_text("my view\n")
        errs, _ = pp.check_brief(inner, quiet=True)
        self.assertTrue(any("host-view.md" in e for e in errs))

    def test_prompt_shape(self):
        self.fill()
        (self.b / "claims.md").write_text("charge() runs twice on retry.\n")
        (self.b / "host-view.md").write_text("HOSTVIEW it double charges\n")
        p, root = pp.build_prompt(self.b, "codex")
        self.assertEqual(root, self.src.resolve())
        self.assertIn("I think it double-charges", p)
        self.assertIn("read access under", p)
        self.assertNotIn("def pay", p)
        self.assertIn("Host notes (unverified)", p)
        self.assertNotIn("HOSTVIEW", p)
        p2, _ = pp.build_prompt(self.b, "agy", text_only=True, include_host_view=True)
        self.assertIn("def pay", p2)
        self.assertIn("HOSTVIEW", p2)


if __name__ == "__main__":
    unittest.main()
