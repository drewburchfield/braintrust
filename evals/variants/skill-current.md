# Variant: skill-current

Manifest for eval injection of the **shipping always-on skill body**.

**Injection package:**

1. `skills/braintrust/SKILL.md` only (as of v1.16.0: Opus 5.5 1M via `braintrust:peer`, strongest Gemini High (Gemini 4 Neon) with Flash High fallback, xAI via read-only Cursor CLI (Grok 4.7), GPT-6.2 Astra with gpt-6.2-sol fallback)

This is what most hosts inject when the skill loads (references are optional/on-demand).

Note: `skill-hybrid.md` remains an eval fixture for A/B. Keep hybrid/lean Codex snippets in sync with Astra (`gpt-6.2-astra`) and the isolation knobs.
