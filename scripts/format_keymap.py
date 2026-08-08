#!/usr/bin/env python3
"""Format ZMK_*LAYER macro invocations, aligning binding cells to a grid.

Rewrites each `ZMK_<NAME>LAYER(...)` invocation found at column 0 so that:
- every binding cell is padded to the same width (per file);
- the box-drawing comment grid is regenerated to match the cell widths;
- everything outside the invocations is left untouched.

Safety: the script refuses to write a file whose formatted output is not
token-identical (ignoring comments/whitespace) to the input.

Usage:
    format_keymap.py [--check] FILE [FILE...]

--check exits non-zero if any file would change, without writing.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

INDENT = 4  # leading spaces before the first cell of a row
HALF_GAP = 3  # spaces between the `,` ending the left half and the right half
BOX_CHARS = set("╭╮╰╯├┤┬┴┼─│ ")

LAYER_RE = re.compile(r"^ZMK_\w*LAYER\(")
DEFINE_RE = re.compile(r"^#define\s+(\w+)\s+(&\S.*?)\s*$")


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def tokens(text: str) -> list[str]:
    # Commas are standalone punctuators for cpp regardless of spacing.
    return strip_comments(text).replace(",", " , ").split()


def find_aliases(text: str) -> set[str]:
    """Names defined as `#define NAME &...` — they start a cell on their own."""
    aliases = set()
    for line in text.splitlines():
        m = DEFINE_RE.match(line.strip())
        if m:
            aliases.add(m.group(1))
    return aliases


class Block:
    """One ZMK_*LAYER(...) invocation."""

    def __init__(self, start: int, end: int, lines: list[str]):
        self.start = start  # line index of the opening line
        self.end = end  # line index of the line holding the closing paren
        self.lines = lines  # original lines, inclusive

    def parse(self, aliases: set[str]):
        raw = "\n".join(self.lines)
        open_idx = raw.index("(")
        self.macro = raw[:open_idx]

        # First line may carry a comment that belongs to the header
        # (e.g. `ZMK_BASE_LAYER(Alpha, // Gallium v1 (colstag)`).
        first = self.lines[0]
        m = re.search(r"//.*$", first)
        self.header_comment = m.group(0) if m else ""

        body = strip_comments(raw[open_idx + 1 :])
        # Any non-grid comment inside the body would be lost — bail out.
        for line in self.lines[1:]:
            m = re.search(r"//(.*)$", line)
            if m and not set(m.group(1)) <= BOX_CHARS:
                raise ValueError(f"unexpected comment inside layer block: {m.group(0)!r}")

        depth = 0
        args: list[str] = []
        current: list[str] = []
        for ch in body:
            if ch == "(":
                depth += 1
            elif ch == ")":
                if depth == 0:
                    break
                depth -= 1
            if ch == "," and depth == 0:
                args.append("".join(current))
                current = []
            else:
                current.append(ch)
        if "".join(current).strip():
            args.append("".join(current))

        self.name = args[0].strip()
        self.rows = [self._cells(arg, aliases) for arg in args[1:]]
        if len(self.rows) % 2 != 0:
            raise ValueError(f"layer {self.name}: odd number of row arguments")

    @staticmethod
    def _cells(arg: str, aliases: set[str]) -> list[str]:
        cells: list[list[str]] = []
        for tok in arg.split():
            if tok.startswith("&") or tok in aliases:
                cells.append([tok])
            elif cells:
                cells[-1].append(tok)
            else:
                raise ValueError(f"cannot tell which cell starts with token {tok!r}")
        return [" ".join(c) for c in cells]


def find_blocks(lines: list[str]) -> list[Block]:
    blocks = []
    i = 0
    while i < len(lines):
        prev_cont = i > 0 and lines[i - 1].rstrip().endswith("\\")
        if LAYER_RE.match(lines[i]) and not prev_cont:
            depth = 0
            for j in range(i, len(lines)):
                depth += strip_comments(lines[j]).count("(")
                depth -= strip_comments(lines[j]).count(")")
                if depth == 0:
                    blocks.append(Block(i, j, lines[i : j + 1]))
                    i = j
                    break
            else:
                raise ValueError(f"unbalanced parens in block at line {i + 1}")
        i += 1
    return blocks


def border(width: int, ncols: list[int], kind: str, nthumb: int = 0) -> str:
    """One box-drawing line. ncols = [left_cols, right_cols]."""
    seg = "─" * width

    def half(n: int, open_c: str, sep_c: str, close_c: str) -> str:
        return open_c + seg + (sep_c + seg) * (n - 1) + close_c

    if kind == "top":
        return "//" + half(ncols[0], "╭", "┬", "╮") + " " + half(ncols[1], "╭", "┬", "╮")
    if kind == "mid":
        return "//" + half(ncols[0], "├", "┼", "┤") + " " + half(ncols[1], "├", "┼", "┤")
    if kind == "pre_thumb":
        # Verticals continue only under the columns that have thumb keys:
        # the last `nthumb` of the left half, the first `nthumb` of the right.
        left = "╰" + seg
        for i in range(1, ncols[0]):
            left += ("┼" if i >= ncols[0] - nthumb else "┴") + seg
        left += "┤"
        right = "├" + seg
        for i in range(1, ncols[1]):
            right += ("┼" if i <= nthumb - 1 else "┴") + seg
        right += "╯"
        return "//" + left + " " + right
    raise ValueError(kind)


def render(block: Block, width: int) -> list[str]:
    main_rows = block.rows[:-2]
    thumb_rows = block.rows[-2:]
    n_left = len(block.rows[0])
    n_right = len(block.rows[1])
    n_thumb = len(thumb_rows[0])

    def half_text(row: list[str], last: bool) -> str:
        # The trailing comma takes the final pad column, so it sits exactly
        # under the half's closing border vertical (original grid style).
        cells = [c.ljust(width) for c in row[:-1]]
        cells.append(row[-1] if last else row[-1].ljust(width - 1) + ",")
        text = " ".join(cells)
        return text.rstrip() if last else text

    def row_line(indent: int, lrow: list[str], rrow: list[str], last: bool) -> str:
        return (" " * indent + half_text(lrow, last=False)
                + " " * HALF_GAP + half_text(rrow, last=last))

    out = [f"{block.macro}({block.name},"
           + (f" {block.header_comment}" if block.header_comment else "")]
    out.append(border(width, [n_left, n_right], "top"))

    pairs = [main_rows[i : i + 2] for i in range(0, len(main_rows), 2)]
    for k, (lrow, rrow) in enumerate(pairs):
        out.append(row_line(INDENT, lrow, rrow, last=False))
        if k < len(pairs) - 1:
            out.append(border(width, [n_left, n_right], "mid"))

    out.append(border(width, [n_left, n_right], "pre_thumb", n_thumb))

    thumb_indent = INDENT + (n_left - n_thumb) * (width + 1)
    out.append(row_line(thumb_indent, thumb_rows[0], thumb_rows[1], last=True))

    seg = "─" * width
    underline = "╰" + seg + ("┴" + seg) * (n_thumb - 1) + "╯"
    out.append("//" + " " * (thumb_indent - 4) + underline + " " + underline)
    out.append(")")
    return out


def format_text(text: str) -> str:
    lines = text.split("\n")
    aliases = find_aliases(text)
    blocks = find_blocks(lines)
    if not blocks:
        return text

    for b in blocks:
        b.parse(aliases)

    width = max(len(c) for b in blocks for row in b.rows for c in row)

    out: list[str] = []
    pos = 0
    for b in blocks:
        out.extend(lines[pos : b.start])
        out.extend(render(b, width))
        pos = b.end + 1
    out.extend(lines[pos:])
    return "\n".join(out)


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    files = [Path(a) for a in args if a != "--check"]
    if not files:
        print(__doc__)
        return 2

    changed = []
    for path in files:
        original = path.read_text()
        try:
            formatted = format_text(original)
        except ValueError as err:
            print(f"✗ {path}: skipped ({err})")
            return 1

        if tokens(original) != tokens(formatted):
            print(f"✗ {path}: refusing to write — formatted output is not "
                  "token-identical to the input (formatter bug, file untouched)")
            return 1

        if formatted != original:
            changed.append(path)
            if not check:
                path.write_text(formatted)
                print(f"✎ {path}: formatted")
        else:
            print(f"✓ {path}: already formatted")

    if check and changed:
        for path in changed:
            print(f"✗ {path}: needs formatting")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
