"""Command-line interface for sera_lab.

Intentionally simple:
- reads from stdin or a file
- applies a tiny built-in ruleset (for now)
- writes to stdout

Agents can later add:
- JSON/YAML rule loading (WITHOUT adding deps)
- better error messages
- exit codes / partial output behavior
"""

from __future__ import annotations
import argparse
import sys
from typing import Iterable

from .normalize import normalize_lines
from .rules import Rule


def _read_lines(path: str | None) -> Iterable[str]:
    if path is None or path == "-":
        return sys.stdin
    return open(path, "r", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="sera-lab", description="Normalize line-oriented records.")
    p.add_argument("path", nargs="?", default="-", help="Input file path or '-' for stdin")
    p.add_argument("--upper-note", action="store_true", help="Uppercase payload for NOTE records")
    p.add_argument("--strip", action="store_true", help="Strip payload whitespace for all records")
    args = p.parse_args(argv)

    rules: list[Rule] = []
    if args.strip:
        rules.append(Rule(name="strip", op="strip_payload", arg=""))
    if args.upper_note:
        rules.append(Rule(name="upper_note", op="upper_payload", arg="", kind="NOTE"))

    try:
        with _read_lines(args.path) as fh:  # type: ignore[assignment]
            out = normalize_lines(fh, rules)
    except Exception as ex:
        # TODO: later: distinguish ParseError vs RuleError
        sys.stderr.write(f"error: {ex}\n")
        return 2

    for line in out:
        sys.stdout.write(line + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
