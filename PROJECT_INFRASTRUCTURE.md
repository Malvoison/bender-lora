# Project Infrastructure Contract

## Target OS
- Primary: Ubuntu 24.04 LTS (noble)
- Best-effort: Ubuntu 22.04 LTS (jammy)

## Optional AI Tool Inits (Local Convenience Only)
These are optional and are NOT required to run the project:
- codex init
- gemini init
- antigravity init
- beads init (memory)

Any files created by these tools are local developer state and should not be committed unless explicitly reviewed and deemed non-sensitive.

## Assumptions (Phase 0)
- `sudo` works
- outbound internet works
- GPU drivers are already configured if running with `--gpu` (WSL counts as preconfigured)

## Bootstrap (Phase 1)
Run from repo root:

```bash
./bootstrap_env.sh --with-ollama --with-docker --gpu --model qwen2.5-coder:7b-instruct
```
## Beads (Out-of-Band Memory)

This project uses Beads as a persistent, out-of-band memory store for durable decisions
and clarifications that should survive across sessions.

Beads usage rules are defined in `BEADS_USAGE.md`.
Beads is not part of the runtime agent execution environment.



