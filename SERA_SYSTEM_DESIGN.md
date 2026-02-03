# SERA System Design (Experiment)

## Purpose

This project builds a local-only experimental system to answer a specific question:

Can a SERA-style synthetic trajectory pipeline, operating entirely on local inference,
produce a LoRA adapter that measurably improves an agent’s ability to navigate,
modify, and validate changes within a code repository it has not previously seen?

The system is designed to:
- generate synthetic code-editing trajectories using a constrained agent tool loop
- filter those trajectories via soft verification rather than strict test oracles
- convert accepted trajectories into supervised fine-tuning data
- train a LoRA adapter against a fixed base model
- evaluate whether the adapted model exhibits improved, repo-specific agent behavior

This is an experiment, not a production system.

The primary success criteria are:
- the system can autonomously generate, verify, and persist training data
- a trained LoRA adapter demonstrably changes agent behavior relative to the base model
- improvements are observable on a fixed set of repo-local “golden” tasks
- all results are reproducible from recorded artifacts (config, manifests, transcripts)

Non-goals include:
- maximizing benchmark scores
- supporting arbitrary repositories or languages
- optimizing for scale or throughput
- achieving state-of-the-art performance

The emphasis is on correctness of process, clarity of artifacts, and experimental control.


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

## 10. Interfaces and Schemas v1

This section defines the concrete v1 interfaces required to implement the system without ambiguity. These interfaces are intentionally minimal and may evolve, but must be versioned when they do.

### 10.1 Configuration file (`config.yaml`)

Location:

* Repo root: `config.yaml`

Purpose:

* Provide a single source of truth for runtime defaults (model, sandbox, thresholds, caps, paths).
* Allow CLI flags to override config values.

Example `config.yaml`:

```yaml
schema_version: 1

paths:
  runs_dir: "runs"

model:
  teacher:
    provider: "ollama"
    name: "qwen2.5-coder:7b-instruct"
    # Optional: if your Ollama endpoint is not default
    base_url: "http://localhost:11434"
    # Generation defaults (tune later)
    temperature: 0.3
    top_p: 0.9
    max_tokens: 2048

runtime:
  seed: 1337
  max_steps: 20
  # Caps to prevent giant context/tool dumps
  max_file_read_lines: 400
  max_tool_output_kb: 64
  max_total_transcript_chars: 300000

sandbox:
  enabled: true
  engine: "docker"
  docker_image: "python:3.12-slim"
  network: "none"
  timeout_seconds: 120
  cpu_limit: "2"
  mem_limit: "4g"
  # Explicit allowlist of exact argv prefixes (no shell metacharacters)
  run_allowlist:
    - ["python", "-m", "pytest", "-q"]
    - ["python", "-m", "compileall", "-q", "src"]

verification:
  soft_verify_threshold: 0.35
  max_files_changed: 3
  max_changed_lines: 200
  require_pytest_pass: true
  forbidden_path_globs:
    - "**/.git/**"
    - "**/.venv/**"
    - "**/__pycache__/**"
    - "**/*.env"
    - "**/.env*"

dataset:
  format: "tool_transcript_jsonl"
  include_tool_results: true
  # If truncation occurs, keep the tail (where edits happen) unless otherwise configured
  truncation_strategy: "keep_tail"

training:
  enabled: false
  # Placeholder for future training params
  adapter_id_prefix: "lora"
```

Rules:

* `schema_version` must be present.
* When the schema changes incompatibly, increment `schema_version`.

### 10.2 CLI contract (v1)

This section defines the required CLI surface and its minimal behavior. Implementation can use `argparse`.

All commands are invoked as:

* `python -m sera_lab <command> [args...]`

Commands:

1. `check`

* Verifies prerequisites for running the experiment.
* Must confirm:

  * Python environment is active
  * Docker is available (if sandbox enabled)
  * Ollama is reachable
  * Teacher model is present (or can be pulled if allowed by the operator)

2. `generate`

* Generates synthetic samples into a run directory.
* Required args:

  * `--run-id <string>` (required)
  * `--count <int>` (default 1)
* Optional args:

  * `--config <path>` (default `config.yaml` if exists)
  * `--seed <int>` override
* Output:

  * Creates `runs/<run-id>/samples/<sample-id>/` folders
  * Writes placeholder artifacts for each sample (even if later steps fail)
  * Appends a row to `runs/<run-id>/manifest.jsonl` per sample

3. `verify`

* Recomputes soft verification for samples in a run (or a single sample).
* Args:

  * `--run-id <string>` required
  * `--sample-id <string>` optional (if omitted, verify all)
* Output:

  * Writes/updates `verify.json` for each processed sample
  * Updates `manifest.jsonl` row fields (`accepted`, `reject_reason`, `r`)

4. `build-dataset`

* Builds training JSONL from accepted samples.
* Args:

  * `--run-id <string>` required
* Output:

  * Writes `runs/<run-id>/train.jsonl`
  * Writes `runs/<run-id>/dataset_report.json` (counts, truncation stats)

5. `train` (future-facing; may be stubbed initially)

* Trains a LoRA adapter from `train.jsonl`.
* Args:

  * `--run-id <string>` required
  * `--adapter-id <string>` required
* Output:

  * Writes adapter artifacts under `runs/<run-id>/adapters/<adapter-id>/`

6. `eval` (future-facing; may be stubbed initially)

* Runs golden-task evaluation comparing base vs base+adapter.
* Args:

  * `--adapter-id <string>` required


### 10.3 Run and sample directory layout (v1)

All experiment artifacts live under:

* `runs/<run-id>/`

Structure:

```
runs/<run-id>/
  config.snapshot.yaml
  manifest.jsonl
  dataset_report.json            # optional, produced by build-dataset
  train.jsonl                    # produced by build-dataset
  samples/
    <sample-id>/
      meta.json
      rollout1.json
      patch1.diff
      pr.txt
      rollout2.json
      patch2.diff
      verify.json
      sandbox/
        rollout1.stdout.txt
        rollout1.stderr.txt
        rollout2.stdout.txt
        rollout2.stderr.txt
```

Rules:

* `<sample-id>` is a zero-padded numeric string: `000001`, `000002`, …
* `config.snapshot.yaml` is copied from the resolved config at run start (after CLI overrides) to make runs reproducible.
* Every sample folder must be created even if rollout fails; failure details go in `meta.json` and `verify.json`.


### 10.4 Manifest row schema (`manifest.jsonl`) (v1)

`manifest.jsonl` is append-only, one JSON object per line.

Required fields:

* `schema_version` (int) — manifest row schema version (start at 1)
* `run_id` (string)
* `sample_id` (string, zero-padded numeric)
* `seed` (int)
* `created_at` (ISO-8601 string)
* `repo` (object):

  * `path` (string) — repo root path used for generation (may be absolute)
  * `commit_sha` (string or null)
* `artifacts` (object):

  * `sample_dir` (string)
  * `rollout1` (string path)
  * `patch1` (string path)
  * `pr` (string path)
  * `rollout2` (string path)
  * `patch2` (string path)
  * `verify` (string path)
* `verification` (object):

  * `r` (number or null) — soft verification recall score
  * `accepted` (bool)
  * `reject_reason` (string or null)
* `stats` (object):

  * `steps_rollout1` (int or null)
  * `steps_rollout2` (int or null)
  * `tool_calls_rollout1` (int or null)
  * `tool_calls_rollout2` (int or null)
  * `elapsed_ms_rollout1` (int or null)
  * `elapsed_ms_rollout2` (int or null)

Example row:

```json
{
  "schema_version": 1,
  "run_id": "devrun",
  "sample_id": "000001",
  "seed": 14599423,
  "created_at": "2026-02-02T21:15:30Z",
  "repo": {
    "path": "/home/ken/src/sera-lab",
    "commit_sha": "abc123def4567890"
  },
  "artifacts": {
    "sample_dir": "runs/devrun/samples/000001",
    "rollout1": "runs/devrun/samples/000001/rollout1.json",
    "patch1": "runs/devrun/samples/000001/patch1.diff",
    "pr": "runs/devrun/samples/000001/pr.txt",
    "rollout2": "runs/devrun/samples/000001/rollout2.json",
    "patch2": "runs/devrun/samples/000001/patch2.diff",
    "verify": "runs/devrun/samples/000001/verify.json"
  },
  "verification": {
    "r": null,
    "accepted": false,
    "reject_reason": "placeholder"
  },
  "stats": {
    "steps_rollout1": null,
    "steps_rollout2": null,
    "tool_calls_rollout1": null,
    "tool_calls_rollout2": null,
    "elapsed_ms_rollout1": null,
    "elapsed_ms_rollout2": null
  }
}
```

Notes:

* For early milestones, `commit_sha` may be null if git is unavailable.
* `reject_reason` should be a stable short token (e.g., `tool_invalid`, `timeout`, `patch_too_large`, `soft_verify_low`, `forbidden_path`, `pytest_failed`, `placeholder`).

### 10.5 Transcript schema (`rollout*.json`) (v1)

Each rollout file is a single JSON document (not JSONL). It records the full interaction: prompts, model outputs, tool calls, tool results, and termination reason.

Top-level fields:

* `schema_version` (int) — transcript schema version (start at 1)
* `rollout_id` (string) — `rollout1` or `rollout2`
* `run_id` (string)
* `sample_id` (string)
* `seed` (int)
* `started_at` / `ended_at` (ISO-8601 strings)
* `model` (object):

  * `provider` (string) — `ollama`
  * `name` (string)
  * `base_url` (string)
  * `temperature` (number)
  * `top_p` (number)
  * `max_tokens` (int)
* `messages` (array) — chronological
* `termination` (object):

  * `reason` (string) — `completed`, `max_steps`, `invalid_tool_call`, `sandbox_error`, `model_error`
  * `details` (string or null)

Message objects:

* `role` (string): `system` | `user` | `assistant` | `tool`
* `content` (string) — natural language or tool output (truncated if needed)
* Optional `tool_call` (object) when `role=assistant` and calling a tool:

  * `name` (string): `read_file` | `search` | `apply_patch` | `run`
  * `arguments` (object) — tool input arguments
* Optional `tool_result` (object) when `role=tool`:

  * `name` (string)
  * `output` (string) — tool output (truncated if needed)
  * `exit_code` (int or null)
  * `truncated` (bool)

Rules:

* Tool calls MUST be represented explicitly via `tool_call`.
* Tool results MUST be represented explicitly via `tool_result`.
* Truncation must set `truncated=true` and indicate the applied cap in `termination.details` or a dedicated `truncation` field if preferred.

### 10.6 Verification output schema (`verify.json`) (v1)

A single JSON document per sample capturing soft verification and gating decisions.

Fields:

* `schema_version` (int) — start at 1
* `run_id` (string)
* `sample_id` (string)
* `soft_verify` (object):

  * `r` (number) — recall score
  * `threshold` (number)
  * `passed` (bool)
* `patch_stats` (object):

  * `files_changed_p1` (int)
  * `files_changed_p2` (int)
  * `changed_lines_p1` (int)
  * `changed_lines_p2` (int)
* `policy` (object):

  * `max_files_changed` (int)
  * `max_changed_lines` (int)
  * `require_pytest_pass` (bool)
* `gates` (array of objects), each:

  * `name` (string) — e.g., `forbidden_path`, `patch_size`, `pytest`
  * `passed` (bool)
  * `details` (string or null)
* `accepted` (bool)
* `reject_reason` (string or null)

### 10.7 Tool contract enforcement (v1)

Tool contract is defined in `AGENTS.md` and must be loaded into runtime agent prompts.

Runtime enforcement rules:

* Only the declared tools may be invoked.
* `run(cmd)` must be executed only in the sandbox and must match an allowlisted argv prefix.
* Any use of disallowed shell metacharacters invalidates the tool call.
* Violations terminate the rollout with `termination.reason=invalid_tool_call` and reject the sample.

Tool schema versioning:

* Set `tool_schema_version: 1` in prompts and transcripts.
* If tool call JSON changes incompatibly, increment version and ensure the trainer/eval code supports it.

---

## 11. Synthetic Task and Training Data Generation Policy (v1)

This section defines **how synthetic training data is automatically generated**.
This policy is normative: implementations MUST follow it unless explicitly versioned and updated.

### 11.1 Scope

This policy governs:

* how targets are selected
* how tasks are formulated
* how rollouts are executed
* when samples are accepted or rejected
* which samples become training data

It does **not** define model internals or infrastructure mechanics.

---

### 11.1 Target Selection (Sampling Policy v1)

* Unit of sampling: **file-level**
* Exactly **one target file per sample**
* Targets are selected uniformly at random from:

  * `runtime.sampling.include_globs`
* Targets matching any `exclude_globs` are never selected
* Selection MUST be deterministic given:

  * `runtime.seed`
  * sample index
* Target file path is recorded in `meta.json` and in the rollout transcript

Rationale:

* File-level sampling is simple, reproducible, and sufficient for early experiments
* Function-level sampling may be introduced in a later version

---

### 11.3 Task Prompt Generation (Prompt Families v1)

For each sample, exactly **one prompt** is generated by selecting uniformly from the following families and interpolating the target file path:

Prompt families:

1. “There may be a bug or edge case in `<target>`. Improve correctness.”
2. “Refactor `<target>` to improve robustness or clarity without changing external behavior.”
3. “Update `<target>` so its behavior better matches its docstring or existing tests.”
4. “Add defensive checks in `<target>` where appropriate.”
5. “Simplify or clean up `<target>` while preserving semantics.”

Rules:

* Prompt text MUST be persisted verbatim in `rollout1.json`
* Prompts MUST be vague by design
* Prompts MUST NOT reference specific fixes
* Prompts MUST NOT instruct the agent to add new dependencies
* Prompts MUST NOT instruct the agent to delete tests

Rationale:

* Diversity comes from vague prompts + repo context, not handcrafted instructions

---

### 11.4 Rollout Execution Policy

Each sample consists of **two rollouts**:

* Rollout 1: initial agent attempt
* Rollout 2: reproduction from PR text

For both rollouts:

* `max_steps` is enforced strictly
* Only tools defined in the Tool Contract may be used
* Any invalid tool call immediately terminates the rollout

Failure handling:

* No retries in v1
* A failed rollout produces a rejected sample
* Failure reason MUST be recorded

Termination reasons include:

* `completed`
* `max_steps`
* `invalid_tool_call`
* `sandbox_error`
* `model_error`

Termination reason is recorded in the transcript and `meta.json`.

---

### 11.5 PR Synthesis Policy

After Rollout 1 completes:

* A synthetic PR description is generated using the same teacher model
* PR text MUST include:

  * intent
  * affected files
  * high-level approach
* PR text MUST NOT include:

  * diffs
  * code blocks
  * explicit patch instructions
* PR length MUST be capped (recommended: 300–600 words)
* PR text is persisted verbatim in `pr.txt`

Rationale:

* Rollout 2 should require real navigation and reasoning, not mechanical replay

---

### 11.6 Soft Verification and Gating Policy

After Rollout 2:

* Compute soft verification score `r` as line-level recall(P2 vs P1)
* Apply gates in order:

  1. Forbidden path check
  2. Patch size limits
  3. Pytest pass (if enabled)
  4. Soft verification threshold

Acceptance criteria:

* All gates pass
* `r >= soft_verify_threshold`
* Termination reason for both rollouts is `completed`

Rejected samples:

* Remain on disk
* Remain in `manifest.jsonl`
* MUST NOT be included in training data

---

### 11.7 Training Data Inclusion Policy

A sample is included in training data **if and only if**:

* `accepted == true`
* Verification gates all passed
* Transcripts are non-empty and valid
* Tool calls and results are well-formed per schema

Dataset construction:

* Uses accepted samples only
* Preserves chronological message order
* Applies truncation only if required by configured caps
* Records truncation statistics in dataset report

Rejected samples are retained for audit and analysis but excluded from training.

---

### 11.8 Determinism and Reproducibility

Given:

* identical repo state
* identical config
* identical seed

The following MUST be reproducible:

* target selection
* prompt selection
* artifact layout
* acceptance decisions (excluding nondeterminism from the model)

All randomness MUST be derived from the configured seed.

---

### 11.9 Policy Versioning

This policy is versioned implicitly as **v1**.

Any incompatible change to:

* sampling unit
* prompt families
* retry behavior
* acceptance criteria

MUST:

* be documented as a new policy version
* be recorded in run metadata
* not silently replace v1 behavior

---

## 12. Milestone Plan (Vertical Slices)

This project will be built as a sequence of runnable vertical slices. Each milestone must produce a working CLI command and persisted artifacts on disk. No milestone may require manual editing of generated artifacts.

### Milestone 0 — Repo + Environment Baseline (Complete)
Definition of done:
- `bootstrap_env.sh` completes successfully on Ubuntu 24.04 (WSL acceptable)
- `.venv` exists and `python -m pytest -q` passes
- Ollama is installed and the teacher model is pulled

### Milestone 1 — Run/Artifact Skeleton (No LLM Yet)
Goal:
- Implement the CLI skeleton and create on-disk run/sample artifacts with placeholders.

Definition of done:
- `python -m sera_lab generate --run-id <id> --count 1` creates:
  - `runs/<id>/config.snapshot.yaml`
  - `runs/<id>/samples/000001/` with placeholder files:
    - `meta.json`, `rollout1.json`, `patch1.diff`, `pr.txt`, `rollout2.json`, `patch2.diff`, `verify.json`
  - `runs/<id>/manifest.jsonl` with one row following the Manifest Row Schema v1
- Unit tests assert the folder structure and manifest row creation.

### Milestone 2 — Verifier v1 (Diff Parsing + Soft Verification)
Goal:
- Implement diff parsing and soft verification scoring.

Definition of done:
- `python -m sera_lab verify --run-id <id>`:
  - reads P1 and P2 diffs from each sample folder
  - computes recall score r
  - writes `verify.json` (Verification Output Schema v1)
  - updates the corresponding manifest row fields (`accepted`, `reject_reason`, `verification.r`)
- Unit tests validate diff parsing and score calculation with known synthetic diffs.

### Milestone 3 — Sandbox Runner v1 (Docker, Allowlist)
Goal:
- Implement `run(cmd)` execution inside a Docker sandbox with strict allowlist and no network.

Definition of done:
- A Python API exists that runs allowlisted commands in Docker with:
  - `--network=none`
  - configured timeouts
  - stdout/stderr capture with output caps
- The runner rejects any command not matching an allowlisted argv prefix.
- Unit tests cover:
  - allowlisted command succeeds
  - disallowed command is rejected
  - timeout is enforced

### Milestone 4 — Ollama Client v1 (Structured Tool Calls)
Goal:
- Implement the teacher model client to call Ollama locally and obtain structured outputs suitable for a tool loop.

Definition of done:
- A Python API exists to send messages to Ollama and receive assistant responses.
- The runtime prompt includes the tool contract and requires tool calls in a strict JSON schema.
- The client validates tool-call JSON and can request a format correction retry once.
- Unit tests cover:
  - basic Ollama request succeeds (can be skipped/marked integration if needed)
  - tool-call JSON validation works on canned samples

### Milestone 5 — Runtime Agent Loop v1 (Rollout 1 Only)
Goal:
- Implement a bounded tool loop for rollout 1 that produces transcript + patch.

Definition of done:
- `python -m sera_lab generate --run-id <id> --count 1` now performs rollout 1:
  - selects a file target (v1 sampling)
  - runs an agent loop using tools: read_file/search/apply_patch/run
  - persists `rollout1.json` and `patch1.diff`
  - runs sandboxed pytest if configured
  - writes sample `meta.json` with step stats and termination reason
- At this milestone, PR synthesis and rollout 2 may remain placeholders.

### Milestone 6 — PR Synthesis + Rollout 2 (Full SVG Loop)
Goal:
- Complete the SVG loop: rollout 1 -> PR text -> rollout 2 -> soft verify -> accept/reject.

Definition of done:
- `python -m sera_lab generate --run-id <id> --count N` produces complete sample folders with:
  - rollout1, patch1, pr, rollout2, patch2, verify
- `verify.json` is written during generation (and recomputable via `verify` command)
- Manifest rows record acceptance decisions with stable reject reasons

### Milestone 7 — Dataset Builder v1
Goal:
- Build training JSONL from accepted samples.

Definition of done:
- `python -m sera_lab build-dataset --run-id <id>` creates:
  - `runs/<id>/train.jsonl` using Transcript Schema v1
  - `runs/<id>/dataset_report.json` with counts and truncation stats
- Unit tests validate that only accepted samples are included and schemas match.

### Milestone 8 — Training Stub + Wiring (Training Optional)
Goal:
- Add the CLI and code wiring for LoRA training without requiring it to run by default.

Definition of done:
- `python -m sera_lab train --run-id <id> --adapter-id <name>` exists and:
  - validates inputs
  - checks presence of `train.jsonl`
  - writes a placeholder `runs/<id>/adapters/<name>/train_report.json`
- Actual QLoRA training implementation can be done next, after sample quality is validated.

### Milestone 9 — LoRA Training v1 (QLoRA)
Goal:
- Implement QLoRA training for the selected base model.

Definition of done:
- A training run emits adapter weights and config under:
  - `runs/<id>/adapters/<adapter-id>/`
- A minimal report includes:
  - dataset size
  - epochs, LR, rank
  - wall time
  - final loss (or equivalent)
- Training must be reproducible from a frozen manifest + config snapshot.

### Milestone 10 — Evaluation v1 (Golden Tasks)
Goal:
- Define and run golden tasks comparing base vs base+adapter.

Definition of done:
- `python -m sera_lab eval --adapter-id <name>` runs the golden suite and outputs:
  - success rate
  - average steps
  - tool validity rate
  - pytest pass rate
- Results are written to a JSON report file under `runs/<id>/`.
