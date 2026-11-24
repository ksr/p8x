# Author: Claude (Anthropic) for Ken Rother, 2026
"""Make the home page's lead picture, website/p8x-collage.jpg: the three assembled-machine renders
(hardware/assembly/build.sh) and the memory card's 3D render, its connector at the bottom. Run it after either is
rendered again:  website/venv/bin/python website/make_collage.py"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
HW = os.path.join(os.path.dirname(HERE), "hardware")
W, H, GAP = 800, 600, 10


def cover(path):
    """The picture scaled to fill a tile, the overhang cut off evenly."""
    im = Image.open(path).convert("RGB")
    k = max(W / im.width, H / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    x, y = (im.width - W) // 2, (im.height - H) // 2
    return im.crop((x, y, x + W, y + H))


def whole(path):
    """The whole picture in a tile, its own background (which only changes downwards) carried out to the sides."""
    im = Image.open(path).convert("RGB").resize((round(H * Image.open(path).width / Image.open(path).height), H), Image.LANCZOS)
    bg = im.crop((0, 0, 1, H)).resize((W, H))
    bg.paste(im, ((W - im.width) // 2, 0))
    return bg


def card(path):
    """A card render on the assembly renders' background, connector down."""
    top, bottom = (201, 201, 229), (102, 102, 133)
    bg = Image.new("RGB", (1, H))
    for y in range(H): bg.putpixel((0, y), tuple(round(a + (b - a) * y / (H - 1)) for a, b in zip(top, bottom)))
    bg = bg.resize((W, H))
    im = Image.open(path).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 128 else 0).getbbox()).rotate(90, expand=True)
    im.thumbnail((W - 40, H - 30), Image.LANCZOS)
    bg.paste(im, ((W - im.width) // 2, (H - im.height) // 2), im)
    return bg


tiles = [cover(os.path.join(HW, "assembly", "p8x-assembly-render.png")),
         card(os.path.join(HW, "memory-card", "kicad", "p8x-memory-card-render-3d.png")),
         cover(os.path.join(HW, "assembly", "p8x-assembly-render-low.png")),
         whole(os.path.join(HW, "assembly", "p8x-assembly-render-side.png"))]
out = Image.new("RGB", (2 * W + 3 * GAP, 2 * H + 3 * GAP), "white")
for i, t in enumerate(tiles): out.paste(t, (GAP + (i % 2) * (W + GAP), GAP + (i // 2) * (H + GAP)))
out.save(os.path.join(HERE, "p8x-collage.jpg"), quality=88, optimize=True)
print("wrote website/p8x-collage.jpg")
