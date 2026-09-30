import os
from PIL import Image

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
pts = [(60, 300), (640, 400), (200, 300), (640, 89), (1100, 700)]
for f in sorted(os.listdir(OUT)):
    if f.startswith("restyle_") and f.endswith(".png"):
        im = Image.open(os.path.join(OUT, f)).convert("RGB")
        w, h = im.size
        px = [im.getpixel(p) for p in pts if p[0] < w and p[1] < h]
        print(f"{f:42s} {w}x{h} {px}")
