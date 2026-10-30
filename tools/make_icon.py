import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = r"F:\ThisNote\app\assets\brand"
os.makedirs(OUT, exist_ok=True)
FONT = r"F:\ThisNote\app\assets\fonts\LXGWWenKai-Regular.ttf"
S = 1024

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# soft shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle((92, 104, 932, 944), radius=210, fill=(74, 56, 38, 80))
shadow = shadow.filter(ImageFilter.GaussianBlur(26))
img.alpha_composite(shadow)

d = ImageDraw.Draw(img)
# paper
d.rounded_rectangle((78, 78, 946, 946), radius=210, fill=(247, 242, 231, 255))
# inner hairline
d.rounded_rectangle((104, 104, 920, 920), radius=190, outline=(227, 218, 200, 255), width=3)
# seal
d.rounded_rectangle((268, 268, 756, 756), radius=168, fill=(168, 70, 55, 255))
d.rounded_rectangle((300, 300, 724, 724), radius=138, outline=(255, 249, 242, 90), width=6)
# glyph
font = ImageFont.truetype(FONT, 330)
text = "记"
bbox = d.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
d.text(((S - tw) / 2 - bbox[0], (S - th) / 2 - bbox[1] - 8), text, font=font, fill=(255, 249, 242, 255))
# tiny gold dot at the bottom of the seal
d.ellipse((498, 790, 526, 818), fill=(201, 164, 108, 255))

img.save(os.path.join(OUT, "icon.png"))
img.save(os.path.join(OUT, "icon_256.png"), sizes=[(256, 256)])
img.save(
    os.path.join(OUT, "app_icon.ico"),
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

android = r"F:\ThisNote\app\android\app\src\main\res"
sizes = {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96, "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}
for folder, size in sizes.items():
    path = os.path.join(android, folder)
    os.makedirs(path, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(os.path.join(path, "ic_launcher.png"))

win = r"F:\ThisNote\app\windows\runner\resources"
os.makedirs(win, exist_ok=True)
img.save(os.path.join(win, "app_icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("ICON_DONE")
