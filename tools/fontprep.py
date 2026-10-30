"""Prepare static Noto Sans SC faces (incl. a true oblique) from the variable font."""
import os
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.recordingPen import DecomposingRecordingPen

SRC = r"F:\ThisNote\assets-tmp\NotoSansSC-VF.ttf"
OUT = r"F:\ThisNote\app\assets\fonts"
os.makedirs(OUT, exist_ok=True)


def instantiate(weight, name):
    f = TTFont(SRC)
    inst = instantiateVariableFont(f, {"wght": weight}, inplace=True)
    path = os.path.join(OUT, name)
    inst.save(path)
    print(name, round(os.path.getsize(path) / 1024 / 1024, 2), "MB")


def make_oblique(src, dst, factor=-0.21):
    f = TTFont(src)
    glyf = f["glyf"]
    glyph_set = f.getGlyphSet()
    order = f.getGlyphOrder()
    new_glyphs = {}
    for name in order:
        rec = DecomposingRecordingPen(glyph_set)
        glyph_set[name].draw(rec)
        pen = TTGlyphPen(None)
        rec.replay(TransformPen(pen, (1, 0, factor, 1, 0, 0)))
        new_glyphs[name] = pen.glyph()
    for name, glyph in new_glyphs.items():
        glyf[name] = glyph
        glyph.recalcBounds(glyf)
    f["post"].italicAngle = 12.0
    f["OS/2"].fsSelection = f["OS/2"].fsSelection | 1
    f["head"].macStyle = f["head"].macStyle | 2
    f.save(dst)
    print(os.path.basename(dst), round(os.path.getsize(dst) / 1024 / 1024, 2), "MB")


if __name__ == "__main__":
    instantiate(300, "NotoSansSC-Light.ttf")
    instantiate(400, "NotoSansSC-Regular.ttf")
    instantiate(700, "NotoSansSC-Bold.ttf")
    make_oblique(os.path.join(OUT, "NotoSansSC-Regular.ttf"), os.path.join(OUT, "NotoSansSC-Oblique.ttf"))
    print("DONE")
