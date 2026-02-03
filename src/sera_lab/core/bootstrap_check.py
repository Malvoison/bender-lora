import shutil
import subprocess

def _require(cmd: str) -> None:
    if shutil.which(cmd) is None:
        raise RuntimeError(f"Missing required command: {cmd}")

def run_bootstrap_checks() -> None:
    # Keep it simple: confirm the critical executables exist.
    _require("python")
    _require("git")
    _require("docker")
    _require("ollama")

    # Quick sanity checks (fast, no heavy calls)
    subprocess.run(["docker", "version"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ollama", "list"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
