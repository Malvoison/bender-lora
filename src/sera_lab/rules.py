"""Rule definitions.

A rule transforms a Record in some way.

We keep rules data-driven but intentionally underpowered:
- only a handful of operations
- no dynamic imports
- no eval
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Callable, Iterable, Optional

from .errors import RuleError
from .records import Record


Transform = Callable[[Record], Record]


@dataclass(frozen=True)
class Rule:
    """A single normalization rule.

    If `kind` is set, the rule only applies to matching record kinds.
    """
    name: str
    op: str
    arg: str
    kind: Optional[str] = None


def compile_rule(rule: Rule) -> Transform:
    """Compile a Rule into a callable transform.

    Supported ops (tiny on purpose):
    - "lower_payload": arg ignored
    - "upper_payload": arg ignored
    - "strip_payload": arg ignored
    - "prefix_payload": arg is prefix text
    - "suffix_payload": arg is suffix text
    """
    op = rule.op.strip()

    def _guard(r: Record) -> bool:
        return rule.kind is None or r.kind == rule.kind

    if op == "lower_payload":
        def xform(r: Record) -> Record:
            if not _guard(r):
                return r
            return Record(r.kind, r.rec_id, r.payload.lower())
        return xform

    if op == "upper_payload":
        def xform(r: Record) -> Record:
            if not _guard(r):
                return r
            return Record(r.kind, r.rec_id, r.payload.upper())
        return xform

    if op == "strip_payload":
        def xform(r: Record) -> Record:
            if not _guard(r):
                return r
            return Record(r.kind, r.rec_id, r.payload.strip())
        return xform

    if op == "prefix_payload":
        def xform(r: Record) -> Record:
            if not _guard(r):
                return r
            # TODO: weird bug later: double-prefixing if already present
            return Record(r.kind, r.rec_id, rule.arg + r.payload)
        return xform

    if op == "suffix_payload":
        def xform(r: Record) -> Record:
            if not _guard(r):
                return r
            return Record(r.kind, r.rec_id, r.payload + rule.arg)
        return xform

    raise RuleError(f"unknown op: {rule.op!r}")


def compile_rules(rules: Iterable[Rule]) -> list[Transform]:
    """Compile many rules into transforms."""
    return [compile_rule(r) for r in rules]
