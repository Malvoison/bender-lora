# SERA System Design (Experiment)

## 1. Purpose
Build a local-only SERA-style pipeline that:
1) Generates synthetic agent trajectories against a repo (rollout 1)
2) Converts rollout 1 into a synthetic PR description (no diff)
3) Reproduces the change from the PR (rollout 2)
4) Soft-verifies by patch overlap
5) Produces a training dataset
6) Fine-tunes a LoRA adapter (QLoRA) for the chosen base model

This is an experiment, not production. Optimize for iteration speed, observability, and reproducibility.

## 2. Hard Constraints
- All token-heavy generation MUST use local inference via Ollama.
- Target environment: Ubuntu 24.04 LTS (WSL acceptable).
- Repo execution happens in Docker sandboxes (network disabled).
- Python + pytest for the initial training repo.
- Base model: Qwen2.5-Coder 7B Instruct
  - Teacher inference: Ollama model `qwen2.5-coder:7b-instruct`
  - Student LoRA base: matching HF weights

## 3. Pipeline Stages
### 3.1 Stage A — Workspace + Sampling
- Choose a target “unit of work” (initially: file-level sampling; later: function-level).
- Create a clean workspace (git worktree or copy).
- Record commit SHA and RNG seed per sample.

### 3.2 Stage B — Rollout 1 (Agent)
Inputs:
- Repo workspace
- Vague prompt referencing a file/area
Outputs:
- Tool transcript (messages + tool calls + tool results)
- Patch P1 (unified diff)
- Stats (steps, tool counts, elapsed time)

### 3.3 Stage C — PR Synthesis
- Convert rollout 1 into a PR description:
  - title, motivation, approach, testing notes, risks
- MUST NOT include the actual diff/patch.

### 3.4 Stage D — Rollout 2 (Reproduction)
Inputs:
- Same baseline repo workspace state as rollout 1
- PR description only
Outputs:
- Tool transcript
- Patch P2

### 3.5 Stage E — Soft Verification
Compute score r = line-level recall(P2 vs P1).

Default acceptance:
- accept if r >= 0.35
- reject if patch touches forbidden paths
- reject if patch too large (default caps: <= 3 files, <= 200 changed lines)
- reject if patch fails to apply cleanly
- if tests exist, require `pytest -q` passes (sandboxed)

### 3.6 Stage F — Dataset Construction
- Convert accepted samples into JSONL for SFT.
- Primary format: tool transcript training (agent behavior)
- Secondary format (optional): instruction+context -> patch

### 3.7 Stage G — Training (QLoRA)
- Train LoRA adapter on accepted samples.
- Emit adapter weights + config + training report.
- Keep tool schema stable and versioned.

### 3.8 Stage H — Evaluation
Minimum evaluation:
- Tool discipline metrics (valid tool calls %, runaway loops %)
- Golden task suite (fixed set of tasks in the fabricated repo)
- Compare base vs base+LoRA success rate, steps, and test pass rate

## 4. System Components
### 4.1 Orchestrator
- Coordinates stages B–G
- Parallelizes sample generation
- Writes artifacts and manifest
- Supports resume/replay

### 4.2 Ollama Teacher Client
- Calls Ollama chat endpoint
- Enforces tool-call JSON schema
- Retries with “format fix” prompt on invalid outputs

### 4.3 Agent Driver
- Runs a bounded tool loop (max_steps)
- Maintains transcript
- Produces final patch via apply_patch tool

### 4.4 Sandbox Runner
- Executes `run(cmd)` inside Docker
- No network
- Strict allowlist commands (pytest/compileall only)
- Timeouts and output caps

### 4.5 Verifier
- Parses diffs
- Computes soft verification score
- Applies acceptance/rejection rules

### 4.6 Dataset Builder
- Builds training JSONL and manifest from accepted samples
- Handles truncation safely (caps file reads/tool output)

### 4.7 Trainer
- QLoRA training job runner
- Saves adapter + metadata + report

## 5. Tool Contract (Schema v1)
Tools (logical):
- read_file(path, start_line, end_line)
- search(pattern, path_glob)
- apply_patch(unified_diff)
- run(cmd) — restricted allowlist, sandboxed

Command allowlist (Python/pytest repo):
- python -m pytest -q
- python -m pytest -q <path>
- python -m compileall -q src

Disallowed:
- installs (pip install, apt-get, etc.)
- network tools (curl/wget/git)
- shell metacharacters (; | > < &&)

## 6. Data Model and Artifacts
Per sample, persist:
- baseline commit SHA
- seed
- rollout1 transcript + patch P1
- PR description text
- rollout2 transcript + patch P2
- verification score and decision
- sandbox logs (stdout/stderr, exit codes)

On-disk layout:
- runs/<run_id>/samples/<sample_id>/{rollout1.json,patch1.diff,pr.txt,rollout2.json,patch2.diff,verify.json}
- runs/<run_id>/manifest.jsonl
- runs/<run_id>/train.jsonl
- runs/<run_id>/adapters/<adapter_id>/*

## 7. Reproducibility
For every run and sample, record:
- model name + quant (teacher)
- ollama version
- python version
- package lock (pip freeze or uv lock)
- tool schema version
- dataset schema version

Provide commands to:
- replay a single sample by ID
- rebuild dataset from manifest
- re-run training from a frozen manifest

## 8. CLI Surface (planned)
- `sera-lab check`
- `sera-lab generate --count N --run-id ...`
- `sera-lab verify --run-id ...`
- `sera-lab build-dataset --run-id ...`
- `sera-lab train --run-id ... --adapter-id ...`
- `sera-lab eval --adapter-id ...`

## 9. Out of Scope
- Production hardening
- GPU driver installation
- External model calls for teacher steps
- Full SWE-bench parity
