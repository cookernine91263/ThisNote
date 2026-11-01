import argparse
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = r"F:\ThisNote\app\assets\brand"
os.makedirs(OUT, exist_ok=True)
SS = 4
S = 1024

parser = argparse.ArgumentParser()
parser.add_argument(
    "--accent",
    default="A84637",
    help="印章底色（RRGGBB），与应用内强调色一致即可。",
)
args = parser.parse_args()
_hex = args.accent.strip().lstrip("#")
if len(_hex) != 6:
    raise SystemExit("--accent 需要 6 位十六进制颜色，例如 A84637")
ACCENT = tuple(int(_hex[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def pi(v):
    return int(round(v * S * SS))


def sc(v):
    return v * S * SS


def cubic(p0, p1, p2, p3, steps=90):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


img = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle(
    (sc(0.082), sc(0.092), sc(0.918), sc(0.938)),
    radius=pi(0.205),
    fill=(74, 56, 38, 90),
)
shadow = shadow.filter(ImageFilter.GaussianBlur(sc(0.026)))
img.alpha_composite(shadow)

d = ImageDraw.Draw(img)
# vermilion seal body
d.rounded_rectangle(
    (sc(0.078), sc(0.078), sc(0.922), sc(0.922)),
    radius=pi(0.205),
    fill=ACCENT,
)
# subtle inner hairline
d.rounded_rectangle(
    (sc(0.094), sc(0.094), sc(0.906), sc(0.906)),
    radius=pi(0.19),
    outline=(255, 249, 242, 70),
    width=pi(0.006),
)

# paper page with a folded corner
page = [
    (sc(0.245), sc(0.175)),
    (sc(0.635), sc(0.175)),
    (sc(0.775), sc(0.315)),
    (sc(0.775), sc(0.785)),
    (sc(0.775), sc(0.820)),
    (sc(0.740), sc(0.820)),
    (sc(0.275), sc(0.820)),
    (sc(0.240), sc(0.820)),
    (sc(0.240), sc(0.785)),
    (sc(0.240), sc(0.210)),
    (sc(0.240), sc(0.175)),
    (sc(0.275), sc(0.175)),
]
d.polygon(page, fill=(255, 248, 234, 255))
d.polygon(
    [(sc(0.635), sc(0.175)), (sc(0.775), sc(0.315)), (sc(0.635), sc(0.315))],
    fill=(232, 217, 194, 255),
)
d.line(
    [(sc(0.635), sc(0.175)), (sc(0.775), sc(0.315)), (sc(0.635), sc(0.315))],
    fill=(33, 30, 25, 50),
    width=pi(0.008),
)

# one tapered brush stroke, drawn as a filled ribbon
pts = cubic(
    (sc(0.30), sc(0.665)),
    (sc(0.40), sc(0.64)),
    (sc(0.47), sc(0.56)),
    (sc(0.55), sc(0.49)),
) + cubic(
    (sc(0.55), sc(0.49)),
    (sc(0.61), sc(0.44)),
    (sc(0.66), sc(0.38)),
    (sc(0.70), sc(0.31)),
)[1:]
left, right = [], []
for i, p in enumerate(pts):
    prev = pts[max(0, i - 1)]
    nxt = pts[min(len(pts) - 1, i + 1)]
    tx, ty = nxt[0] - prev[0], nxt[1] - prev[1]
    length = max(1.0, (tx * tx + ty * ty) ** 0.5)
    nx, ny = -ty / length, tx / length
    t = i / (len(pts) - 1)
    half = sc(0.045) * (1 - t) + sc(0.007) * t
    left.append((p[0] + nx * half, p[1] + ny * half))
    right.append((p[0] - nx * half, p[1] - ny * half))
d.polygon(left + list(reversed(right)), fill=(33, 30, 25, 255))
for p, r in ((pts[0], 0.045), (pts[-1], 0.007)):
    d.ellipse(
        (p[0] - sc(r), p[1] - sc(r), p[0] + sc(r), p[1] + sc(r)),
        fill=(33, 30, 25, 255),
    )
d.ellipse(
    (sc(0.263), sc(0.653), sc(0.307), sc(0.697)),
    fill=(33, 30, 25, 255),
)

# one small chop
d.rounded_rectangle(
    (sc(0.615), sc(0.615), sc(0.785), sc(0.785)),
    radius=pi(0.018),
    fill=(33, 30, 25, 255),
)
d.rounded_rectangle(
    (sc(0.637), sc(0.637), sc(0.763), sc(0.763)),
    radius=pi(0.008),
    outline=(255, 249, 242, 180),
    width=pi(0.009),
)
# a quiet seal mark
d.ellipse(
    (sc(0.678), sc(0.678), sc(0.722), sc(0.722)),
    fill=(255, 249, 242, 220),
)

img = img.resize((S, S), Image.LANCZOS)
img.save(os.path.join(OUT, "icon.png"))
img.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "icon_256.png"))
img.save(
    os.path.join(OUT, "app_icon.ico"),
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

android = r"F:\ThisNote\app\android\app\src\main\res"
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for folder, size in sizes.items():
    path = os.path.join(android, folder)
    os.makedirs(path, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(os.path.join(path, "ic_launcher.png"))

win = r"F:\ThisNote\app\windows\runner\resources"
os.makedirs(win, exist_ok=True)
img.save(
    os.path.join(win, "app_icon.ico"),
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print("ICON_DONE")

