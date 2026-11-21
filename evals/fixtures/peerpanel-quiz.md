# Fixture: peerpanel-quiz (stable, public, no private data)

## Goal
Score how well a peer answers from the **skill text only** (variant injected below) about running a consult through `peerpanel`. Do not invent commands or flags that are not in the skill text.

## Questions (answer all, short bullets)

1. Which three commands take a consult from nothing to results, in order?
2. Name the two required brief files and what goes in each.
3. Where do the files and folders the answer depends on go, and how do peers see them by default?
4. Where does an inference the host drew (a link the user never stated) belong, and how do peers treat it?
5. Is the host's own conclusion sent to peers by default? How do you change that?
6. Inside Claude Code, how is the Claude seat filled?
7. A seat shows `cap`. What does that mean, and is it retried?
8. Which failures are retried, and how many times?
9. What should the host do with peer findings after synthesizing?
10. End with: **GROUNDED** if your answers are only from the skill text, else **NOT GROUNDED** and list guesses.

## Scoring rubric (heuristic)

| ID | Correct if answer includes | Points |
|----|---------------------------|--------|
| Q1 | brief new, brief check, consult | 1 |
| Q2 | request.md verbatim user words; question.md | 1 |
| Q3 | sources.txt; peers read the paths themselves (read access) | 1 |
| Q4 | claims.md; unverified / confirm or refute | 1 |
| Q5 | host-view.md withheld; --include-host-view | 1 |
| Q6 | braintrust:peer via Task tool, prompt-claude.md | 1 |
| Q7 | plan/usage limit; not retried | 1 |
| Q8 | timeout, empty, connection; once | 1 |
| Q9 | never auto-apply; present and stop | 1 |
| Q10 | GROUNDED only if no invention | 1 |
| **Max** | | **10** |
