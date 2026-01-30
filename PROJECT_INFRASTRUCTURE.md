# Project Infrastructure Contract

## Target OS
- Primary: Ubuntu 24.04 LTS (noble)
- Best-effort: Ubuntu 22.04 LTS (jammy)

## Assumptions (Phase 0)
- `sudo` works
- outbound internet works
- GPU drivers are already configured if running with `--gpu` (WSL counts as preconfigured)

## Bootstrap (Phase 1)
Run from repo root:

```bash
./bootstrap_env.sh --with-ollama --with-docker --gpu --model qwen2.5-coder:7b-instruct
