# Domain docs

## Layout and reading rules

This repo uses a single-context layout:

- `CONTEXT.md` at the repo root holds domain terminology.
- `docs/adr/` holds architecture decision records.

Before exploring the codebase, read `CONTEXT.md` and ADRs relevant
to the area being explored.

If these files do not exist, proceed silently. The domain-modeling
skill creates them when terms or decisions are resolved.

## Use the glossary's vocabulary

Use terms defined in `CONTEXT.md` when naming domain concepts in
issues, proposals, hypotheses, and tests.

If a needed concept is missing, reconsider whether it belongs to
the domain or note the gap for domain-modeling.

## Flag ADR conflicts

Explicitly identify any proposal that contradicts an existing ADR,
and explain why the decision should be reconsidered.
