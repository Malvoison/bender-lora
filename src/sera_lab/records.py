"""Line-oriented record parsing.

A "record" is a single line with a tiny schema:
    <kind>|<id>|<payload>

Example:
    NOTE|123|hello world

Design notes:
- Keep this intentionally strict (agents can later relax it).
- We will later add tests and deliberately inject edge-case bugs.

TODO ideas for later bugs:
- whitespace handling around separators
- empty payload behavior
- ids with leading zeros
"""

from __future__ import annotations
from dataclasses import dataclass

from .errors import ParseError


@dataclass(frozen=True)
class Record:
    kind: str
    rec_id: str
    payload: str


def parse_line(line: str) -> Record:
    """Parse one input line into a Record.

    Raises:
        ParseError: if the line is malformed.
    """
    raw = line.rstrip("\n")

    # Intentionally naive split: will misbehave if payload contains "|"
    parts = raw.split("|")
    if len(parts) != 3:
        raise ParseError(f"expected 3 fields separated by '|', got {len(parts)}: {raw!r}")

    kind, rec_id, payload = parts

    # Intentionally strict: empty fields are rejected (agents can change later)
    if not kind or not rec_id or payload is None:
        raise ParseError(f"empty field in line: {raw!r}")

    return Record(kind=kind, rec_id=rec_id, payload=payload)


def render_record(r: Record) -> str:
    """Render a Record back to its line form."""
    return f"{r.kind}|{r.rec_id}|{r.payload}"
