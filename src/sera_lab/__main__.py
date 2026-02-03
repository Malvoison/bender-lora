import argparse
from sera_lab.core.bootstrap_check import run_bootstrap_checks

def main() -> int:
    p = argparse.ArgumentParser(prog="sera-lab")
    p.add_argument("--check", action="store_true", help="Verify local env and toolchain.")
    args = p.parse_args()

    if args.check:
        run_bootstrap_checks()
        return 0

    p.print_help()
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
