#!/usr/bin/env python3
"""Neo Geo sprite scenes for the video bench, and a MAME-style reference
renderer (with or without the 96 sprites per line limit).

VRAM word map: SCB1 0000-6FFF (64 words per sprite), fix map 7000-7FFF,
SCB2 8000, SCB3 8200, SCB4 8400 (fast VRAM = 8000-87FF).
"""
import os, random, sys

NSPR = 381
CROM_WORDS = 1 << 20          # 2MB
NTILES = CROM_WORDS * 2 // 128

class Scene:
    def __init__(self, seed=0):
        self.rng = random.Random(seed)
        self.svram = [0] * 32768
        self.fvram = [0] * 2048
        rng = random.Random(1234)          # LO ROM and C ROM fixed across scenes
        self.lorom = [rng.randrange(256) for _ in range(65536)]
        self.crom = [rng.randrange(65536) for _ in range(CROM_WORDS)]
        for i in range(64):             # tile 0 is transparent (used by sprite 0)
            self.crom[i] = 0
        # SCB3 default: sprite height 0 (not displayed)
        for n in range(512):
            self.fvram[0x200 + n] = 0

    def set_sprite(self, n, x=None, y=None, size=None, sticky=False, hz=15, vz=255, tiles=None):
        """y: screen line of the top (MAME y = 0x200 - (scb3 >> 7))"""
        if sticky:
            self.fvram[0x200 + n] = 0x40
        else:
            ystore = (0x200 - y) & 0x1ff
            self.fvram[0x200 + n] = (ystore << 7) | (size & 0x3f)
            self.fvram[0x400 + n] = (x & 0x1ff) << 7
        self.fvram[0x000 + n] = ((hz & 15) << 8) | (vz & 255)
        rng = self.rng
        for t in range(32):
            if tiles is not None:
                code, pal, flags = tiles[t % len(tiles)]
            else:
                code = rng.randrange(1, NTILES)
                pal = rng.randrange(1, 256)
                flags = rng.randrange(16)
            self.svram[n * 64 + 2 * t] = code & 0xffff
            self.svram[n * 64 + 2 * t + 1] = (pal << 8) | (((code >> 16) & 15) << 4) | flags

    def write(self, d):
        os.makedirs(d, exist_ok=True)
        def wr(name, data, fmt):
            with open(os.path.join(d, name), "w") as f:
                f.write("\n".join(fmt % v for v in data) + "\n")
        wr("svram.hex", self.svram, "%04x")
        wr("fvram.hex", self.fvram, "%04x")
        wr("lorom.hex", self.lorom, "%02x")
        wr("crom.hex", self.crom, "%04x")


# ------------------------------------------------------------ reference
# h-shrink: source pixels drawn for each value (measured on the core)
_ZX_ORDER = [8, 4, 12, 2, 14, 6, 10, 0, 9, 3, 15, 7, 13, 1, 11, 5]
ZOOM_X = [[1 if k in _ZX_ORDER[:n + 1] else 0 for k in range(16)] for n in range(16)]

def on_line(line, y, rows):
    if rows == 0:
        return False
    if rows >= 32:
        return True
    max_y = (y + rows * 16 - 1) & 0x1ff
    return ((max_y >= y and y <= line <= max_y) or
            (max_y < y and (line >= y or line <= max_y)))

def decode_line(sc, code, sy, half_order=1):
    """16 colour indexes, screen order for an unflipped sprite"""
    base = ((code << 7) | (sy << 3)) & (CROM_WORDS * 2 - 1)
    w = [sc.crom[(base >> 1) + i] for i in range(4)]
    d64 = (w[0] << 48) | (w[1] << 32) | (w[2] << 16) | w[3]
    halves = [d64 & 0xffffffff, d64 >> 32]
    if half_order:
        halves.reverse()
    px = []
    for h in halves:
        b = [(h >> (8 * k)) & 0xff for k in range(4)]   # b[0] = bits 7:0
        for k in range(8):
            px.append(((b[3] >> k) & 1) << 3 | ((b[2] >> k) & 1) << 2 | ((b[1] >> k) & 1) << 1 | ((b[0] >> k) & 1))
    return px

def render_line(sc, line, aa, limit=96, half_order=1, skip=0, quirk95=True):
    """Palette address per x (0..511), None where no sprite. Sprites in the
    active list order; the last drawn wins. skip: drop the first N actives."""
    # parse
    act = []
    y = rows = 0
    for n in range(NSPR):
        yc = sc.fvram[0x200 + n]
        if not (yc & 0x40):
            y = (0x200 - (yc >> 7)) & 0x1ff
            rows = yc & 0x3f
        if on_line(line, y, rows):
            act.append(n)
            if limit and len(act) == limit:
                break
    out = [None] * 512
    x = zx = zy = y = rows = 0
    for i, n in enumerate(act):
        yc = sc.fvram[0x200 + n]
        zc = sc.fvram[0x000 + n]
        if yc & 0x40:
            x = (x + zx + 1) & 0x1ff
            zx = (zc >> 8) & 15
        else:
            y = (0x200 - (yc >> 7)) & 0x1ff
            x = sc.fvram[0x400 + n] >> 7
            zy = zc & 0xff
            zx = (zc >> 8) & 15
            rows = yc & 0x3f
        if i < skip:
            continue
        sl = (line - y) & 0x1ff
        # core quirk: the 96th list entry, on the line just above the top of
        # a sprite (sprite line 511), is drawn as the sprite's first line
        if i == 95 and sl == 511 and quirk95:
            sl = 0
        zl = sl & 0xff
        inv = bool(sl & 0x100)
        if inv:
            zl ^= 0xff
        # "continuous" sprites (odd sizes from 33): mirrored repeat below the
        # shrunk height, as the LSPC computes it (SPR_CONTINUOUS / LO_LINE_B)
        if (rows & 0x21) == 0x21 and zl > zy:
            zl = 255 - ((zl + 2 * (127 - (zy & 127))) & 255)
            inv = not inv
        yt = sc.lorom[(zy << 8) | zl]
        sy = yt & 15
        tile = yt >> 4
        if inv:
            sy ^= 15
            tile ^= 0x1f
        attr = sc.svram[(n << 6) | (tile << 1) | 1]
        code = ((attr << 12) & 0xf0000) | sc.svram[(n << 6) | (tile << 1)]
        if attr & 8:
            code = (code & ~7) | (aa & 7)
        elif attr & 4:
            code = (code & ~3) | (aa & 3)
        if attr & 2:
            sy ^= 15
        px = decode_line(sc, code, sy, half_order)
        if attr & 1:
            px = px[::-1]
        pal = attr >> 8
        xx = x
        for k in range(16):
            if ZOOM_X[zx][k]:
                c = px[k]
                if c:
                    out[xx & 0x1ff] = (pal << 4) | c
                xx += 1
    return out

def encode_line(sc, code, sy, px, half_order=1):
    """write 16 pixels (screen order, unflipped) into C ROM"""
    halves = [0, 0]
    for hi in range(2):
        b = [0, 0, 0, 0]
        for k in range(8):
            c = px[hi * 8 + k]
            for p in range(4):
                b[p] |= ((c >> p) & 1) << k
        halves[hi] = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)
    if half_order:
        halves.reverse()
    d64 = halves[0] | (halves[1] << 32)
    base = ((code << 7) | (sy << 3)) & (CROM_WORDS * 2 - 1)
    for i in range(4):
        sc.crom[(base >> 1) + i] = (d64 >> (48 - 16 * i)) & 0xffff
