# Portable method bundle

Copy this whole folder into a new project, then tell the agent:

> Read `METHOD.md` and follow it. Start at Phase 0.

Three files:

- `METHOD.md` — the sequence and the guardrails. The only file you have to read.
- `verify_numbers.py` — the verification harness template. Adapt the `build_claims`
  block and the paths at the top; leave the rest.
- `FACTS_template.md` — start your project's fact file from this.

Field-agnostic and language-agnostic. It assumes only that some code produces results and
some document reports them.
