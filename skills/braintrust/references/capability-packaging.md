# Capability Packaging (what peers may touch)

Derived from real braintrust history (2026-02 → 2026-07). Goal Cards fix *what success is*. This page fixes *what each peer is allowed and able to use* while scoring that success.

Two knobs people collapse and should not:

| Knob | Question | Default for braintrust |
|------|----------|------------------------|
| **Identity isolation** | Whose memories, AGENTS.md, MCP servers, skills load? | **Clean / isolated** (especially Codex) |
| **Workspace access** | Which files, tools, images, local services may this peer use? | **Task-shaped**, never "whatever the host has open" |

You can (and often should) give a peer **rich workspace access** while keeping **identity isolation**. Isolation is about bias. Access is about evidence.

---

## History that forced these rules

Examples are anonymized. Patterns only; no client or personal identifiers.

| Pattern | What happened | Rule |
|---------|---------------|------|
| Contaminated PR review | Codex first run answered an **unrelated** prior-session topic (memories/global AGENTS). Isolated `CODEX_HOME` + `-C /tmp` fixed it. | Isolate **identity**; pass the diff **inline** for pure review. |
| Multi-file claim verify | One peer as file-capable verifier (dozens of files). Codex timed out reinventing binary tooling in sandbox; **retry on host pre-extracted dumps** worked. Other peers logic/red-team only. | Assign **roles** per peer. Host pre-extracts when sandboxes cannot install tools. |
| Diagram validation | Text peers got a **node transcription**; one vision-capable peer alone got the **PNG**. Goal Card said so. | Split **modality**. Tell each peer what they can and cannot see. |
| MCP tool thrash | Grok **FAILED**: spent the turn on a broken MCP `read_file`, never answered. | Default **no ambient MCP** for peers. If tools are allowed, name the allowlist and a text-only fallback. |
| MCP spawn death | Grok **MCP server spawn errors**, 0 bytes. | Heavy/dead MCP in the peer's global profile kills headless consults. Isolation or tool-deny. |
| Docx surgical edit | Best peer **unpacked** the real `.docx` under `/tmp`. | When fidelity is file-grounded, give a **real path** (or unpack for them) instead of prose about the file. |
| Evidence-only Goal Card | Explicit: evidence files only; screenshots are **transcribed**; images not available to text peers. | Put **access limits** in the Goal Card / capability block, not only in the host's head. |
| Codex with `-C /tmp` alone | Still loaded memories + MCP until `CODEX_HOME` was clean. | `-C` is **not** identity isolation. |

---

## Capability modes (pick one primary per peer)

Do not give every peer the same package. History's best consults **specialized**.

| Mode | Peer gets | Best for | Pattern examples |
|------|-----------|----------|------------------|
| **A. Text-only adjudicator** | Goal Card + curated excerpts only. No tools, no MCP, no repo walk. | Pricing, framing, voice, sequencing, "send or not" | Commercial letter stress-test |
| **B. Inline-evidence reviewer** | Card + full prompt package (diffs, dumps, claim lists) in `$QUERY`. Tools off or read-only on given paths only. | PR review when isolation matters | Isolated Codex + prompt file under `/tmp` |
| **C. Repo walker** | Card + **cwd = repo** (or `--add-dir`). Read tools allowed. Identity still isolated. | Architecture, multi-file security, "does the tree match the claim" | API surface / tool-shape review |
| **D. File-capable verifier** | Explicit file list/paths; instruction to **re-derive** not trust host narrative. | Claim confirmation, forensic teardown | Full-tree claim sweep |
| **E. Vision / media** | Image/PDF path via host that supports it (Claude Task, OpenCode `-f`, Codex `-i`). Others get a **transcription** and must flag vision-dependent claims. | Diagrams, decks, screenshots | Flow diagram + vision peer |
| **F. Red-team / steel-man** | Same text package as A/B; role = attack assumptions, not expand scope into tooling. | Risk, memo safety | Adversarial claim review |
| **G. MCP-assisted** (rare) | Named local MCP tools only; auth requirements stated; hard timeout; text fallback if MCP fails. | Live systems (tickets, local notes) when the ask is literally "check the ticket" | Prefer host does this **before** consult and pastes results |

Default multi-voice layout that worked repeatedly:

1. **At least one** file/repo capable verifier (often Claude Task or agy with `--add-dir` / cwd)
2. **At least one** isolated text adjudicator (often Codex clean-slate)
3. Optional red-team (Grok) on the **same text package**
4. Host synthesis owns cross-checks

---

## Identity isolation vs workspace access (per CLI)

### Codex

| Need | How |
|------|-----|
| Clean identity (default) | `CODEX_HOME=$bt_codex_home` (auth only) + `--ignore-user-config` + no MCP in that home |
| No repo bleed | `-C "${TMPDIR:-/tmp}"` **and** put evidence in `$QUERY` or a prompt file |
| **Must** read the live repo | Drop `-C` (cwd = repo) or `codex exec -C /path/to/repo ...` but **keep** isolated `CODEX_HOME` |
| Diff review of working tree | `CODEX_HOME=... codex review --uncommitted` from the repo (identity still isolated) |
| Images | `-i path` |
| Structured answer | `--output-schema` |
| Sandbox | Braintrust default `-s read-only`. Only widen if user asked the peer to write. |

Never: global `~/.codex` with memories + MCP for a "neutral peer." That is how off-topic reviews happened.

### Claude (Task tool / `claude -p`)

| Need | How |
|------|-----|
| File/repo walk | Task in the project (Claude Code) already has tools; **tell it the paths and the verification mandate** |
| Vision | Attach/read image in Task prompt; other peers get transcription |
| Headless from other hosts | `claude -p --model opus` with enough inline context; avoid `--bare` (auth dies) |
| Nested | Never `claude -p` from inside Claude Code |

Claude is usually your **best file-capable verifier** when the host is Claude Code. Use it that way deliberately; do not waste it on pure prose-only tasks if another peer can adjudicate text.

### agy

| Need | How |
|------|-----|
| Headless answer | `--print` + `--output-format json` + `--dangerously-skip-permissions`; parse `.response` |
| Extra roots | `--add-dir` (repeatable) when files live outside cwd |
| Model pin | `--model gemini-3.7-flash-high` (probe default). Slugs from `agy models` |
| No `@path` | **Inline** or ensure cwd/`--add-dir` and tell it relative paths |
| Artifacts | It may write under its brain dir; host should copy useful drafts back into the repo |

### Grok

| Need | How |
|------|-----|
| Clean headless | `--no-auto-update -p` + `--output-format json` + model `grok-4.6` |
| Avoid repo litter | `--cwd` scratch optional |
| Tools / MCP | **Prefer off.** History: MCP spawn failures and thrashing on broken `read_file` produced empty consults. |
| If tools needed | Prefer `--disable-web-search` unless research is the point; put file contents in the prompt; permission mode stay non-write for opinions |

### OpenCode

| Need | How |
|------|-----|
| Fast unbiased consult | `run --format json --auto --pure` (+ `-m` only if probe set user's default model; `--variant` when `bt_opencode_variant` is set) |
| Attach files | `--file` / `-f` (repeatable) |
| Repo cwd | `--dir` path |
| MCP | `--pure` skips external plugins (good default). Drop `--pure` only when a **named** local MCP is required and already healthy. |
| Permissions | `--auto` for headless tool use; still keep the task read-only in the prompt |

---

## MCP: when peers should see it

**Default: peers do not inherit the host's MCP graph.** Host MCP is for the orchestrator. Peers get conclusions or excerpts.

Allow MCP into a peer only when all of these are true:

1. The Goal Card requires **live** state the host did not (or cannot cheaply) fetch.
2. The server is **local or no-auth** (or auth is known-good for that binary), e.g. local filesystem notes, docker gateway already up, not an expired cloud OAuth MCP.
3. You name an **allowlist** of tools in the prompt (not "use whatever MCP you have").
4. You give a **text-only fallback**: "If MCP fails or times out, answer from the packaged context and mark LIVE_STATE_UNKNOWN."
5. You set a hard timeout and treat MCP thrash as peer failure, not as a reason to block other voices.

### Prompt fragment for local MCP (example)

```text
## CAPABILITY BLOCK
mode: G (MCP-assisted) + A (text fallback)
identity: isolated (no host memories)
workspace:
  - evidence paths: [list]
mcp:
  allowed: ["local-notes.search", "local-notes.read"]   # exact names
  forbidden: ["*send*", "*write*", "slack.*", "email.*"]
  auth: none required (local)
  if_unavailable: answer from CURATED CONTEXT only; verdict may be NOT GROUNDED on live-state claims
tools_policy: read-only; do not install packages; do not mutate files
```

### Prompt fragment for no tools (default)

```text
## CAPABILITY BLOCK
mode: A (text-only adjudicator)
identity: isolated
workspace: only what is pasted under CURATED CONTEXT
tools: none — do not call MCP, do not search the web, do not open files outside this prompt
if you lack evidence for a claim: say UNKNOWN, do not invent
```

### Prompt fragment for repo walker

```text
## CAPABILITY BLOCK
mode: C (repo walker)
identity: isolated (clean profile; no host AGENTS/memories)
workspace:
  cwd: /path/to/repo
  read: allowed under repo
  write: forbidden
mandate: re-open files yourself; cite path:line; do not trust host summaries without verification
```

---

## Host responsibilities (before launch)

1. **Decide the mode per peer** (table above). Write it in the capability block.
2. **Pre-extract** when sandboxes cannot do the job (VBA dumps, unzipped docx, `rg` results, image transcriptions).
3. **Do not** send peers into binary forensics without extracted text unless that peer has proven tools for it.
4. **Vision**: one peer with eyes; everyone else gets a transcription + "flag if claim needs the image."
5. **Secrets**: never paste tokens into peer prompts. MCP auth stays in the peer's own credential store; prefer host-side fetch.
6. **Untracked files**: `codex review --uncommitted` may miss them; stage or inline.
7. **Record the package** in the session file: which peer was file-capable vs text-only vs vision. Synthesis depends on it.

---

## Goal Card optional section (recommended)

Add when access is non-obvious:

```markdown
## Access / Capability Map
| Peer role | Mode | May use | Must not |
|-----------|------|---------|----------|
| Claude verifier | D file-capable | paths under `src/`, evidence/* | network write |
| Codex adjudicator | B inline | prompt package only | MCP, global memories |
| Grok red-team | F | same package as Codex | tools |
| agy | C repo walker | `--add-dir` project root | invent surnames / client facts not in files |
```

---

## Anti-patterns

1. **Same max tools for every peer** — wastes voices and multiplies MCP failure surface.
2. **Isolation without evidence** — clean Codex with empty prompt produces vague philosophy.
3. **Evidence without isolation** — contaminated second opinions (off-topic memories).
4. **"Just use MCP"** with no allowlist — Grok-style tool thrash, empty answer.
5. **Assuming peer sees host MCP** — they do not, unless their own profile loads it (often badly).
6. **Asking text models to "look at the screenshot"** without a transcription or vision-capable peer.
7. **Expecting Codex sandbox to `pip install`** mid-consult for forensics.

---

## Quick decision tree

```
Is this a pure judgment / pricing / voice question?
  yes → Mode A all peers; max isolation; rich Goal Card
  no  →
    Do claims depend on files in a repo?
      yes → at least one Mode C or D; others Mode B on excerpts
    Do claims depend on an image/PDF?
      yes → one Mode E; others get transcription
    Do claims depend on live external state?
      prefer → host fetches, paste into package (Mode B)
      only if needed → Mode G with allowlist + fallback
    Is unbiased review the point?
      always → keep identity isolation even when cwd is the repo
```
