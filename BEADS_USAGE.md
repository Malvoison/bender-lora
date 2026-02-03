# Beads Usage Contract

## Purpose
Beads is used as a persistent, out-of-band memory store for this project.
It records stable facts, decisions, and invariants that should survive across sessions.

Beads is NOT a log, transcript store, or scratchpad.

## Scope
This contract applies to:
- human developers
- builder agents operating under human supervision

It does NOT apply to:
- runtime agents executed by the SERA pipeline
- rollout agents whose behavior becomes training data

Runtime agents must never read from or write to Beads.

## What Goes Into Beads
Beads may contain:
- confirmed design decisions
- stable system invariants
- tool contracts and expectations
- clarifications that resolve ambiguity
- decisions that affect multiple files or modules
- rationale for non-obvious choices

Entries should be:
- concise
- factual
- written in declarative language
- durable (expected to remain true for some time)

## What Must NOT Go Into Beads
Beads must NOT contain:
- transcripts or logs
- temporary plans or TODOs
- speculative ideas
- generated code
- secrets, credentials, or tokens
- step-by-step instructions
- anything that could go stale quickly

If it belongs in a Markdown file or a commit message, it does not belong in Beads.

## Authority and Precedence
In case of conflict:
1. Repository files (design docs, contracts) are authoritative
2. Beads entries provide clarification, not override
3. Beads must never contradict committed documents

If a Beads entry becomes outdated, it must be explicitly revised or retired.

## Writing to Beads
Only humans or explicitly designated builder agents may write to Beads.
All writes must be intentional and reviewed.

Runtime agents are prohibited from Beads access.

## Relationship to the Repo
Beads complements the repository; it does not replace it.

- Source of truth for code and design: Git
- Source of truth for execution rules: AGENTS.md
- Source of truth for environment: PROJECT_INFRASTRUCTURE.md
- Source of truth for experimental intent: SERA_SYSTEM_DESIGN.md
- Source of durable memory and decisions: Beads
