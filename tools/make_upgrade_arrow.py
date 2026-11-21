# Draws Media/UpgradeArrow.tga: white double up-arrow with a black outline (tinted green in game).
# Usage: python tools/make_upgrade_arrow.py Media/UpgradeArrow.tga
import struct, sys
from PIL import Image, ImageDraw
S = 256  # draw at 4x, downsample to 64x64
im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
chevrons = [[(44, 118), (128, 34), (212, 118)], [(44, 214), (128, 130), (212, 214)]]
def stroke(pts, w, col):
    d.line(pts, fill=col, width=w, joint='curve')
    r = w // 2
    for x, y in pts:
        d.ellipse((x - r, y - r, x + r, y + r), fill=col)
for c in chevrons: stroke(c, 64, (0, 0, 0, 255))
for c in chevrons: stroke(c, 36, (255, 255, 255, 255))
im = im.resize((64, 64), Image.LANCZOS)
out = sys.argv[1]
# uncompressed 32-bit TGA, bottom-left origin, 8 alpha bits (descriptor 8)
hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, 64, 64, 32, 8)
px = im.load()
data = bytearray()
for y in range(63, -1, -1):
    for x in range(64):
        r, g, b, a = px[x, y]
        data += bytes((b, g, r, a))
open(out, 'wb').write(hdr + data)
