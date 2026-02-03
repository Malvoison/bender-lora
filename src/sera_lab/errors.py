"""Errors used by the normalization pipeline."""

class SeraError(Exception):
    """Base error for this package."""


class RuleError(SeraError):
    """Raised when a rule is invalid or cannot be applied."""


class ParseError(SeraError):
    """Raised when an input line cannot be parsed into a record."""
