# Fixture: contract-quiz (stable, public, no private data)

## Goal
Score how well a peer answers from the **skill text only** (variant injected below). Do not invent flags not present in the skill text.

## Questions (answer all, short bullets)

1. List the braintrust member CLIs. Is Gemini CLI a member?
2. How do you call Codex for a clean-slate second opinion? Name the isolation env var and two required flags/practices.
3. How do you call OpenCode? When do you pass `-m`?
4. How do you call Grok headless? What default model id is documented?
5. How do you call agy headless? What must you never fall back to if agy fails?
6. When running inside Claude Code, how do you get a Claude peer voice?
7. What are the two separate knobs: identity isolation vs workspace access? One sentence each.
8. What is Mode A vs Mode C in capability packaging (if present in skill text)?
9. Where does the model probe write its cache file?
10. End with: **GROUNDED** if your answers are only from the skill text, else **NOT GROUNDED** and list guesses.

## Scoring rubric (host applies after collect)

| ID | Correct if answer includes | Points |
|----|---------------------------|--------|
| Q1 | claude, agy, codex, grok, opencode; Gemini CLI not a member | 1 |
| Q2 | CODEX_HOME isolated; --ignore-user-config or ephemeral+read-only; stdin closed /dev/null | 1 |
| Q3 | opencode run --format json --auto --pure; -m only if bt_opencode_model set | 1 |
| Q4 | grok -p; grok-4.5; output-format json | 1 |
| Q5 | agy --print; no gemini fallback | 1 |
| Q6 | Task tool / subagent (not claude -p nested) | 1 |
| Q7 | identity=profile/memories/MCP; workspace=files/cwd | 1 |
| Q8 | A=text-only package; C=repo walker (if skill has modes) | 1 |
| Q9 | /tmp/bt_models.env | 1 |
| Q10 | GROUNDED only if no invention | 1 |
| **Max** | | **10** |
