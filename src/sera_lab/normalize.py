"""Normalization pipeline.

Pipeline shape:
- parse lines -> records
- apply compiled rule transforms
- render records -> lines

We keep it functional and explicit so agents can:
- refactor
- add caching
- add better error reporting
- add tests
"""

from __future__ import annotations
from typing import Iterable, Sequence

from .errors import ParseError, RuleError
from .records import Record, parse_line, render_record
from .rules import Rule, compile_rules


def normalize_record(r: Record, transforms) -> Record:
    """Apply transforms in order."""
    cur = r
    for t in transforms:
        cur = t(cur)
    return cur


def normalize_lines(lines: Iterable[str], rules: Sequence[Rule]) -> list[str]:
    """Normalize line-oriented records.

    Raises:
        ParseError, RuleError
    """
    transforms = compile_rules(rules)
    out: list[str] = []
    for line in lines:
        rec = parse_line(line)  # may raise
        norm = normalize_record(rec, transforms)
        out.append(render_record(norm))
    return out
