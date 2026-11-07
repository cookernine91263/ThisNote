"""Subset the bundled CJK fonts to the common Chinese charset.

The full source fonts live in tools/font-src (gitignored). Regenerate with:

    uv run --with fonttools --with brotli python tools/subset_fonts.py

The app keeps the same family names; rare characters fall back to the system
CJK font at runtime. The generated charset file is bundled so PDF export can
warn when a character is not covered by the subset.
"""

from __future__ import annotations

import shutil
import sys
import time
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "font-src"
OUT = ROOT / "app" / "assets" / "fonts"
RAW = ROOT / "tools" / "charset" / "cjk8105_raw.txt"

FONTS = [
    "NotoSansSC-Light.ttf",
    "NotoSansSC-Regular.ttf",
    "NotoSansSC-Bold.ttf",
    "LXGWWenKai-Regular.ttf",
    "SourceHanMonoSC-Regular.otf",
    "NotoSerifSC-Regular.otf",
    "SmileySans-Oblique.otf",
    "MaShanZheng-Regular.ttf",
    "ZCOOLXiaoWei-Regular.ttf",
]

# Display / monospace faces only keep the GB2312 common set; rare glyphs fall
# back to Noto Sans SC. Body and heading faces keep the full 8105 set.
BASIC_FONTS = {
    "SourceHanMonoSC-Regular.otf",
}

# Decorative / serif display faces use the 3755 level-1 common characters.
COMMON_FONTS = {
    "NotoSerifSC-Regular.otf",
    "SmileySans-Oblique.otf",
    "MaShanZheng-Regular.ttf",
    "ZCOOLXiaoWei-Regular.ttf",
}

RANGES = [
    (0x2000, 0x206F),  # general punctuation
    (0x20A0, 0x20CF),  # currency
    (0x2100, 0x214F),  # letterlike
    (0x2190, 0x21FF),  # arrows
    (0x2200, 0x22FF),  # math
    (0x2460, 0x24FF),  # enclosed alphanumerics
    (0x2500, 0x257F),  # box drawing
    (0x25A0, 0x25FF),  # geometric shapes
    (0x2600, 0x26FF),  # misc symbols
    (0x3000, 0x303F),  # CJK punctuation
    (0xFE10, 0xFE1F),  # vertical forms
    (0xFE30, 0xFE4F),  # CJK compatibility forms
    (0xFF00, 0xFFEF),  # half/full width forms
]


def _app_chars() -> set[str]:
    chars: set[str] = set()
    for path in (ROOT / "app" / "lib").rglob("*.dart"):
        try:
            chars.update(path.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            pass
    ignored = {"\u200b", "\u200c", "\u200d", "\ufeff", "\r", "\n", "\t"}
    return {c for c in chars if ord(c) >= 0x20 and c not in ignored}


def _base_chars() -> set[str]:
    chars: set[str] = set()
    for cp in range(0x20, 0x7F):
        chars.add(chr(cp))
    for cp in range(0xA0, 0x100):
        chars.add(chr(cp))
    for start, end in RANGES:
        for cp in range(start, end + 1):
            chars.add(chr(cp))
    return chars


def build_charset() -> set[str]:
    chars: set[str] = set(RAW.read_text(encoding="utf-8"))
    chars.update(_base_chars())
    chars.update(_app_chars())
    return {c for c in chars if ord(c) >= 0x20}


def build_basic_charset() -> set[str]:
    chars = _base_chars() | _app_chars()
    for lead in range(0xB0, 0xF8):
        for trail in range(0xA1, 0xFF):
            try:
                chars.add(bytes([lead, trail]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return {c for c in chars if ord(c) >= 0x20}


def build_common_charset() -> set[str]:
    # GB2312 level 1 (3755 most common hanzi) + UI punctuation / app labels.
    chars = _base_chars() | _app_chars()
    for lead in range(0xB0, 0xD8):
        for trail in range(0xA1, 0xFF):
            try:
                chars.add(bytes([lead, trail]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return {c for c in chars if ord(c) >= 0x20}


def subset_font(name: str, codepoints: list[int]) -> None:
    src = SRC / name
    dst = OUT / name
    if not src.exists():
        print(f"skip (missing source): {name}")
        return
    font = TTFont(src)
    options = subset.Options()
    options.layout_features = [
        "kern",
        "liga",
        "vert",
        "locl",
        "ccmp",
        "mark",
        "mkmk",
    ]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.recalc_bounds = True
    options.hinting = False
    options.desubroutinize = False
    options.drop_tables = ["DSIG"]
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)
    font.flavor = None
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    font.save(tmp)
    # Verify the result still opens before replacing the bundled file.
    check = TTFont(tmp)
    if "cmap" not in check:
        raise RuntimeError(f"{name}: subset lost cmap")
    check.close()
    font.close()
    for attempt in range(20):
        try:
            shutil.move(tmp, dst)
            break
        except OSError:
            if attempt == 19:
                raise
            time.sleep(0.5)
    before = src.stat().st_size / 1024 / 1024
    after = dst.stat().st_size / 1024 / 1024
    print(f"{name:34s} {before:6.2f} MB -> {after:5.2f} MB")


def main() -> int:
    if not SRC.exists():
        print(f"missing {SRC}; copy the original fonts there first", file=sys.stderr)
        return 1
    chars = build_charset()
    basic = build_basic_charset()
    common = build_common_charset()
    codepoints = sorted({ord(c) for c in chars})
    basic_points = sorted({ord(c) for c in basic})
    common_points = sorted({ord(c) for c in common})
    (OUT / "cjk-charset.txt").write_text(
        "".join(chr(cp) for cp in codepoints), encoding="utf-8"
    )
    print(
        f"charset: {len(codepoints)} full / {len(basic_points)} basic / "
        f"{len(common_points)} common"
    )
    for name in FONTS:
        if name in COMMON_FONTS:
            points = common_points
        elif name in BASIC_FONTS:
            points = basic_points
        else:
            points = codepoints
        subset_font(name, points)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())