# Agent Execution Contract (Runtime Agents Only)

## Scope
This contract applies **only** to agents executed by the SERA experimental pipeline
(e.g., rollout agents whose behavior is recorded for training or evaluation).

It does **not** apply to:
- human developers
- interactive assistant tools (Claude, Codex, Gemini) used to design or build the system
- one-off scaffolding or refactoring work performed under human supervision

Builder agents are not constrained by this document.

## Purpose
Runtime agents are intentionally restricted to ensure:
- reproducible trajectories
- safe sandboxed execution
- consistent training data

## Allowed Tools (Runtime Agents)
Runtime agents may only use the following tools:

- read_file(path, start_line, end_line)
- search(pattern, path_glob)
- apply_patch(unified_diff)
- run(cmd) — restricted (see below)

## Command Execution (`run(cmd)`)
Allowed commands:
- python -m pytest -q
- python -m pytest -q <path>
- python -m compileall -q src

Disallowed:
- package installation (pip install, uv, apt, etc.)
- network access (curl, wget, git)
- shell metacharacters (; | > < &&)
- modifying files outside the repo

## Behavioral Rules
- Agents must inspect code before editing.
- Agents must prefer minimal diffs.
- Agents must not delete tests to make them pass.
- Agents must stop after completing the task.

## Infrastructure
- Environment assumptions are defined in PROJECT_INFRASTRUCTURE.md.
- Runtime agents must not modify infrastructure or bootstrap files.

Violations invalidate the run and the sample is rejected.
