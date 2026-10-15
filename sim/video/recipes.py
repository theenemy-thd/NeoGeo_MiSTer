"""Scene recipes: recipe(seed) -> Scene. Deterministic for a given seed."""
import random
from scene import Scene, NSPR

def single(seed):
    sc = Scene(seed)
    sc.set_sprite(1, x=16, y=32, size=2, hz=15, vz=255)
    return sc

def rand_light(seed):
    """random sprites, mostly under the per-line limit"""
    sc = Scene(seed)
    r = random.Random(seed)
    n = 1
    while n < NSPR:
        chain = r.randrange(1, 5)
        x = r.randrange(512)
        y = r.randrange(512)
        size = r.choice([1, 2, 3, 4, 8, 16, 32, 33, r.randrange(64)])
        vz = r.choice([255, 255, r.randrange(256)])
        for k in range(chain):
            if n >= NSPR:
                break
            sc.set_sprite(n, x=x, y=y, size=size, sticky=(k > 0), hz=r.randrange(16), vz=vz)
            n += 1
        n += r.randrange(0, 3)      # gaps: unused sprites keep height 0
    # keep the load low: blank out most sprites
    for m in range(1, NSPR):
        if r.random() < 0.6 and not (sc.fvram[0x200 + m] & 0x40):
            sc.fvram[0x200 + m] &= ~0x3f
    return sc

def rand_heavy(seed):
    """many sprites crossing a band of lines: well over 96 per line there"""
    sc = Scene(seed)
    r = random.Random(seed)
    n = 1
    while n < NSPR:
        chain = r.randrange(1, 4)
        x = r.randrange(512)
        y = r.randrange(80, 160)
        size = r.choice([1, 2, 3, 4, 33, r.randrange(1, 40)])
        vz = r.choice([255, r.randrange(256)])
        for k in range(chain):
            if n >= NSPR:
                break
            sc.set_sprite(n, x=x, y=y, size=size, sticky=(k > 0), hz=r.randrange(16), vz=vz)
            n += 1
    return sc

def grid(seed, hz=None, vz=None, size=None, flags=None):
    """non-overlapping sprites in a grid, parameters from seed unless fixed"""
    sc = Scene(seed)
    r = random.Random(seed)
    n = 1
    for row in range(6):
        for col in range(18):
            h = r.randrange(16) if hz is None else hz
            v = r.randrange(256) if vz is None else vz
            s = r.choice([1, 2]) if size is None else size
            tiles = None
            if flags is not None:
                tiles = [(r.randrange(1, 4096), r.randrange(1, 256), flags) for _ in range(32)]
            sc.set_sprite(n, x=col * 18, y=16 + row * 36, size=s, hz=h, vz=v, tiles=tiles)
            n += 1
    return sc

def g_hz(seed):    return grid(seed, vz=255, size=1, flags=0)
def g_hzf(seed):   return grid(seed, vz=255, size=1)
def g_vz(seed):    return grid(seed, hz=15, size=2, flags=0)
def g_vzf(seed):   return grid(seed, hz=15, size=2)

def hzprobe(seed):
    """sprites with h-shrink 0..15; every line of tile 1 has pixel k = colour
    (k + seed) & 15, so the drawn colours show which source pixels are used"""
    from scene import encode_line
    sc = Scene(seed)
    for sy in range(16):
        encode_line(sc, 1, sy, [(k + seed) & 15 for k in range(16)])
    for hz in range(16):
        for f in range(2):
            sc.set_sprite(1 + hz * 2 + f, x=hz * 20, y=32 + f * 40, size=1, hz=hz, vz=255, tiles=[(1, 0x10, f)])
    return sc

def chains(seed):
    sc = Scene(seed)
    r = random.Random(seed)
    n = 1
    for row in range(6):
        x = 0
        while x < 300 and n < 300:
            k = r.randrange(1, 5)
            sc.set_sprite(n, x=x, y=16 + row * 36, size=r.choice([1, 2]), hz=r.randrange(16), vz=r.randrange(256)); n += 1
            for j in range(1, k):
                sc.set_sprite(n, sticky=True, hz=r.randrange(16), vz=r.randrange(256)); n += 1
            x += 16 * k + 4
    return sc

def tall(seed):
    """one column per size/zoom: sizes 16..63 at random y (wraps too)"""
    sc = Scene(seed)
    r = random.Random(seed)
    for c in range(19):
        size = r.choice([16, 31, 32, 33, 34, 40, 48, 63, r.randrange(1, 64)])
        sc.set_sprite(1 + c, x=c * 17, y=r.randrange(512), size=size, hz=15, vz=r.choice([255, r.randrange(256)]))
    return sc

def ywrap(seed):
    sc = Scene(seed)
    r = random.Random(seed)
    for c in range(19):
        sc.set_sprite(1 + c, x=c * 17, y=r.randrange(400, 512), size=r.randrange(1, 32), hz=15, vz=r.randrange(256))
    return sc

def xpar(seed):
    """same kind of sprite at x = 0..17 (one per row band), vz 255, hz 15"""
    sc = Scene(seed)
    r = random.Random(seed)
    for i in range(18):
        sc.set_sprite(1 + i, x=i * 17 + (i & 1) * 0, y=16 + (i % 6) * 36, size=[1, 2, 16, 32, 33, 40][i % 6], hz=15, vz=255)
    return sc
