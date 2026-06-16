"""GB2312 character set utilities.

GB 2312-80 defines 6763 Chinese characters in two zones:
- Level 1 (一级字): 3755 characters, rows 16–55
- Level 2 (二级字): 3008 characters, rows 56–87

Each row spans 94 positions (columns 01–94).  The module generates the
complete list programmatically so no external data files are needed.
"""

from __future__ import annotations

from typing import Dict, List, Optional


# GB2312 row ranges for Level 1 and Level 2 characters
_LEVEL1_ROWS = range(16, 56)   # rows 16-55, 3755 chars
_LEVEL2_ROWS = range(56, 88)   # rows 56-87, 3008 chars
_COLUMN_RANGE = range(1, 95)    # columns 01-94


def _gb2312_code_to_bytes(row: int, col: int) -> bytes:
    """Convert GB2312 zone/position to raw two-byte encoding."""
    return bytes([row + 0xA0, col + 0xA0])


def get_gb2312_chars(level: Optional[int] = None) -> List[str]:
    """Return the list of GB2312 Chinese characters.

    Parameters
    ----------
    level : int or None
        - ``1`` → Level 1 characters only (3755).
        - ``2`` → Level 2 characters only (3008).
        - ``None`` → Both levels (6763).

    Returns
    -------
    list[str]
        Characters decoded as UTF-8 strings.
    """
    rows = []
    if level is None or level == 1:
        rows.extend(_LEVEL1_ROWS)
    if level is None or level == 2:
        rows.extend(_LEVEL2_ROWS)

    chars: List[str] = []
    for row in rows:
        for col in _COLUMN_RANGE:
            raw = _gb2312_code_to_bytes(row, col)
            try:
                ch = raw.decode("gb2312")
                # Some byte combos decode to non-char or replacement
                if ch and ch != "\ufffd":
                    chars.append(ch)
            except (UnicodeDecodeError, ValueError):
                continue
    return chars


def build_char_index() -> Dict[str, int]:
    """Build a character → index mapping for the full GB2312 set.

    Returns
    -------
    dict[str, int]
        Mapping from character to sequential index (0-based).
    """
    chars = get_gb2312_chars()
    return {ch: i for i, ch in enumerate(chars)}


def get_punctuation_chars() -> List[str]:
    """Return common Chinese punctuation and symbols (GB2312 rows 1-9)."""
    rows = range(1, 10)
    chars: List[str] = []
    for row in rows:
        for col in _COLUMN_RANGE:
            raw = _gb2312_code_to_bytes(row, col)
            try:
                ch = raw.decode("gb2312")
                if ch and ch != "\ufffd":
                    chars.append(ch)
            except (UnicodeDecodeError, ValueError):
                continue
    return chars


def get_ascii_chars() -> List[str]:
    """Return printable ASCII characters (space through tilde)."""
    return [chr(i) for i in range(32, 127)]


if __name__ == "__main__":
    chars = get_gb2312_chars()
    print(f"Total GB2312 characters: {len(chars)}")
    print(f"First 20: {''.join(chars[:20])}")
    print(f"Last 20:  {''.join(chars[-20:])}")
