# Agent Execution Contract

## Purpose
This repository is used for experiments with agent-based code modification and model fine-tuning.
Agents must follow these rules strictly.

## Allowed Tools
Agents may only use the following tools:

- read_file(path, start_line, end_line)
- search(pattern, path_glob)
- apply_patch(unified_diff)
- run(cmd) — restricted (see below)

Agents must not invent new tools.

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
- Agents must not modify infrastructure or bootstrap files.

Violation of these rules invalidates the run.
