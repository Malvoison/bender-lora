
# Ticket Decomposition Guide

### Terminology: “Top Shelf” Models

In this document, “top shelf” refers to higher-cost, higher-capability models
(e.g., large frontier models with extended reasoning or context),
used sparingly for tasks that require genuine judgment or design decisions.

“Top shelf” does NOT imply:
- default usage
- better execution for well-specified tasks
- use for mechanical or repetitive work

The default expectation is that most tickets should be executable by low/fast,
lower-cost models once properly decomposed.

## Purpose

This guide defines how to decompose work into tickets that can be executed by “low/fast” agents with minimal reliance on “top shelf” models.

The goal is not perfect decomposition. The goal is **repeatable execution**:

* small diffs
* clear acceptance criteria
* deterministic verification
* minimal ambiguity

## Core Principle

Prefer **many small, verifiable tickets** over one large “smart” ticket.

If a ticket cannot be executed by a low/fast agent without significant interpretation, it is either:

* insufficiently specified, or
* inherently “high/slow”

Both cases must be made explicit.

## Ticket Classes

### LF: Low/Fast (default)

Characteristics:

* bounded scope
* local changes
* clear acceptance criteria
* direct verification command(s)

LF tickets must specify:

* *exact files/paths*
* *what changes*
* *how to verify*
* *constraints* (what not to touch)

### HS: High/Slow (explicit escalation)

Use HS when:

* behavior is underspecified
* design choices must be made
* multiple approaches are plausible
* risk of architectural drift is high

HS tickets must produce artifacts:

* a short design note (markdown)
* explicit decision + rationale
* then decomposition into LF tickets

## Ticket Template (required fields)

### 1) Title

One sentence. Action verb. Concrete.

### 2) Type

LF or HS.

### 3) Context

What exists today. Include file paths and brief pointers.

### 4) Task

What to do. Use explicit bullets.

### 5) Acceptance Criteria

Objective conditions. Prefer checklists.

### 6) Verification

Exact commands to run (e.g., `python -m pytest -q`).
If verification is not possible, say so explicitly and explain why.

### 7) Constraints

What must not change:

* forbidden directories
* no new dependencies (unless explicitly allowed)
* no network calls
* don’t modify infra/contracts unless stated

### 8) Dependencies

List of ticket IDs this ticket depends on. State `None` if not applicable.

### 9) Output Artifacts

What files must be created/modified.

## Decomposition Rules (how to turn HS into LF)

### Rule A: One ticket = one primary effect

Examples of a primary effect:

* add a module
* implement a function
* add a CLI command
* add a schema + validator
* add a single gating rule

If there are two primary effects, split it. A primary effect generally includes the
core logic (e.g., a function or class) and its immediate, self-contained unit
tests. Tests for other existing logic, or integration tests, should be a separate
ticket.

### Rule B: Always name the files

A ticket that says “implement verifier” is vague.
A ticket that says “create `src/sera_lab/verify/diff_score.py` and implement `compute_recall(p1, p2)`” is executable.

### Rule C: Make “done” testable

Every LF ticket must specify at least one of:

* unit test added/updated
* CLI command output file exists and matches schema
* deterministic function output on a canned input

### Rule D: Avoid hidden dependencies

If a ticket requires a library, it must say so.
Default assumption: **no new deps**.

### Rule E: Prefer deterministic scaffolding first

Build skeletons that write placeholder artifacts before wiring in intelligence.
This reduces thrash and makes later steps plug-in.

### Rule F: State Dependencies Explicitly

If a ticket requires another ticket to be completed first, this dependency must be
explicitly stated in its `Dependencies` field.

## Low/Fast-Friendly Task Shapes

These shapes are ideal for cheap models:

* “Create a new module with these functions and docstrings; include unit tests for edge cases.”
* “Add a CLI command that creates this directory layout and writes placeholder JSON files.”
* “Implement schema validation for this JSON and add tests for valid/invalid samples.”
* “Implement diff parsing and compute metrics; verify using these canned diffs.”
* “Add a config loader with defaults; verify config snapshot is written.”

Avoid shapes like:

* “Make this better”
* “Refactor for maintainability”
* “Improve architecture”
  unless HS and producing a design note.

## Escalation Triggers (force HS)

If any of the following are true, classify as HS:

* multiple plausible designs
* changes span more than 3 modules/directories
* requires non-trivial judgement about policy/behavior
* unclear verification
* expected to exceed 200 changed lines

HS should end by producing LF tickets.

## Review Gate (human)

Before running any LF ticket through a low/fast model, confirm:

* files are named
* acceptance criteria are objective
* verification commands are present
* constraints are explicit
* expected diff size is bounded

If any are missing, rewrite the ticket.

## Handling Failures

If an LF ticket fails, do not simply ask the agent to "try again." The failure
itself is a signal. A human should briefly review the failure to determine if:

1. The ticket's instructions were flawed and need correction.
2. The task was deceptively complex and must be re-scoped or escalated to an HS ticket.
3. There was a transient environment or tool error.

This prevents agents from thrashing on a poorly defined problem.

Consistent failures in a series of LF tickets may also point to a flaw in the
parent HS design. In this case, pause execution and revisit the original design
note to see if it needs amending.

---

## How this reduces “top shelf” usage

Because you’re **moving intelligence to the front**:

* Top shelf models help with HS “decision + decomposition”
* Cheap models chew through LF “execution” tickets
* Your pipeline (pytest + schema checks + soft verify) acts as the backstop

That’s the whole economics of it.

---

## Minimal integration with Beads

Since you’re using Beads as memory, the workflow becomes:

* Beads ticket is created as **HS** when it’s fuzzy
* HS produces:

  * a committed design note (short)
  * 5–20 LF tickets
* LF tickets are executed by cheap models
* Results are merged and recorded

Beads stores the “why,” the repo stores the “what,” and the diffs store the “how.”

---
