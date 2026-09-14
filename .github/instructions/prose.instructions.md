---
applyTo: "**/*.md"
excludeAgent: "cloud-agent"
---

# Review scope for prose

Markdown files in this repository (SKILL.md selection contracts, authoring guides, references) are specifications consumed by AI agents, not essays for human readers. Judge wording by what it selects, not by how it reads.

- Flag a wording issue only with a quoted failing case: one concrete input or reading that selects the wrong skill, permits the wrong behavior, or contradicts another file. Name every description or rule it wrongly matches.
- Without such a case, do not raise the issue. "Could read ambiguously", "more parallel phrasing", and "clearer" are not findings on their own.
- Do not propose adding a word no selection or behavior depends on. If removing the proposed word changes no outcome, the proposal fails.
