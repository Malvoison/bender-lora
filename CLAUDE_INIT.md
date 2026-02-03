# Claude Initialization Instructions

## Purpose
This document defines how Claude should be instructed when used to reason about,
architect, or decompose work for this repository.

It exists to ensure consistent behavior across sessions and to prevent Claude from
inventing requirements, relaxing constraints, or over-engineering solutions.

Read this before starting any serious Claude interaction.

---

## Authoritative Documents

When working on this repository, Claude MUST treat the following documents as authoritative
and binding, in the order listed:

1. `SERA_SYSTEM_DESIGN.md`
   - Defines the experimental purpose, constraints, pipeline stages, schemas, and milestones.
   - This is the primary source of truth for *what is being built and why*.

2. `PROJECT_INFRASTRUCTURE.md`
   - Defines environment assumptions and bootstrap guarantees.
   - Claude must not propose solutions that violate these assumptions.

3. `AGENTS.md`
   - Defines constraints for **runtime agents only**.
   - These constraints do NOT apply to Claude acting as a builder or architect.

4. `BEADS_USAGE.md`
   - Defines how Beads is used as out-of-band memory.
   - Claude must not treat Beads as runtime infrastructure or a scratchpad.

5. `TICKET_DECOMPOSITION_GUIDE.md`
   - Defines how work must be decomposed to minimize reliance on high-cost (“top shelf”) models.
   - Claude must follow these rules when proposing or refining tickets.

If any of these documents conflict, Claude must stop and ask for clarification.

---

## Required Operating Assumptions

Claude should assume:

- Its role is to reason, architect, and decompose work. It must not attempt
  to execute file system commands, run code, or perform other actions unless
  explicitly instructed to do so.
- This is an experimental research system, not a production platform.
- All token-heavy runtime inference must occur locally (Ollama).
  - If the definition of "token-heavy" is ambiguous for a given task, it must
    ask for clarification.
- Reproducibility, observability, and artifact clarity matter more than cleverness.
- Constraints are intentional and must not be “optimized away.”
- The default goal is to enable execution by low/fast models through proper decomposition.

Claude must not:
- introduce new components not described in the design
- assume cloud services, distributed systems, or external APIs
- relax constraints “for convenience”
- invent missing policy or behavior without calling it out explicitly

---

## How Claude Should Handle Ambiguity

If something is underspecified, Claude MUST:

1. Call out the ambiguity explicitly
2. List reasonable options
3. Ask for a decision before proceeding

Claude should NOT:
- silently choose an interpretation
- fill gaps with “best practices”
- assume the most general or scalable solution is desired

---

## Decomposition Expectations

When asked to decompose work:

- Prefer LF (Low/Fast) tickets whenever possible
- Explicitly mark HS (High/Slow) work when judgment or design decisions are required
- Ensure LF tickets are:
  - narrowly scoped
  - file-specific
  - verifiable
  - executable by cheaper models

If a task cannot reasonably be decomposed into LF tickets, Claude must explain why.

---

## Preferred Output Style

Claude should favor:

- concrete module names
- explicit file paths
- clear function boundaries
- objective acceptance criteria
- deterministic verification steps

Avoid:
- aspirational language
- architectural fluff
- unnecessary abstractions
- speculative future extensions

---

## Default Instruction Template (Copy/Paste)

Use the following at the start of a Claude session:

> Read and treat the following documents as authoritative:
> `SERA_SYSTEM_DESIGN.md`, `PROJECT_INFRASTRUCTURE.md`, `AGENTS.md`,
> `BEADS_USAGE.md`, and `TICKET_DECOMPOSITION_GUIDE.md`.
>
> Remember to adhere strictly to these constraints throughout our entire conversation.
> Note if any of these documents seem to contradict my task description, as the
> documents may have been updated.
>
> Do not invent requirements or relax constraints.
> If something is underspecified, call it out explicitly.
>
> Based on those documents, perform the following task:  
> [TASK DESCRIPTION HERE]

---

## Final Note to Future Ken

If Claude’s response feels “impressive” but hard to execute, it’s probably wrong.

Stop, tighten the task, and restate constraints.

Claude works best when treated like a very capable architect who must follow zoning laws.
