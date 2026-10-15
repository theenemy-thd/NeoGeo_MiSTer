# Builds a tiny Neo Geo CD test disc (ISO9660, 2048-byte sectors) with the
# five file types the BIOS insists on (PRG, FIX, SPR, Z80, PCM) and IPL.TXT.
# The PRG's USER routine paints the backdrop red and loops at $000400, so
# "the 68000 is running at $0004xx" means the BIOS finished loading and
# started the game.
import struct, sys
SEC = 2048
def be16(v): return struct.pack('>H', v)
def be32(v): return struct.pack('>I', v)
def both16(v): return struct.pack('<H', v) + struct.pack('>H', v)
def both32(v): return struct.pack('<I', v) + struct.pack('>I', v)

# ---- 68000 program (big endian, loaded at $000000)
prg = bytearray(0x800)
# vectors: SSP, PC, then every exception -> RTE at $0300
prg[0:4] = be32(0x0010F300); prg[4:8] = be32(0x00000400)
for v in range(2, 64): prg[v*4:v*4+4] = be32(0x00000300)
prg[0x100:0x108] = b'NEO-GEO\x00'
prg[0x108:0x10A] = be16(0x0999)           # NGH
prg[0x10A:0x10E] = be32(0x00000800)       # program size
prg[0x10E:0x112] = be32(0x00100000)       # backup RAM pointer
prg[0x112:0x114] = be16(0x0000)           # backup RAM size
prg[0x114] = 2                            # no eye catcher
prg[0x115] = 0
for o in (0x116, 0x11A, 0x11E): prg[o:o+4] = be32(0x00000500)   # soft DIP tables
def jmp(a): return b'\x4e\xf9' + be32(a)
prg[0x122:0x128] = jmp(0x400)             # USER
prg[0x128:0x12E] = jmp(0x310)             # PLAYER_START
prg[0x12E:0x134] = jmp(0x310)             # DEMO_END
prg[0x134:0x13A] = jmp(0x310)             # COIN_SOUND
prg[0x300:0x302] = b'\x4e\x73'            # rte
# interrupts: acknowledge everything, kick the watchdog
prg[0x320:0x330] = bytes.fromhex('33fc0007003c000c13c0003000014e73')
for v in (25, 26, 27): prg[v*4:v*4+4] = be32(0x00000320)
prg[0x310:0x312] = b'\x4e\x75'            # rts
# USER: $400
code = bytes.fromhex(
    '13fc0000 00300001'      # move.b #0,$300001   (watchdog)
    '33fc0f00 00401ffe'      # move.w #$0F00,$401FFE (backdrop red)
    '13c0 00300001'          # loop: move.b d0,$300001
    '60f8'                   # bra loop
)
prg[0x400:0x400+len(code)] = code
prg[0x500:0x520] = b'TEST DISC       ' + bytes(16)

# ---- Z80 driver: echo each sound command back as the reply
z80 = bytearray(0x200)
z80[0x00:0x09] = bytes.fromhex('f3 31fcff ed56 c30001'.replace(' ', ''))
z80[0x38:0x3b] = bytes.fromhex('fbed4d')
z80[0x66:0x6e] = bytes.fromhex('f5 db00 d30c f1 ed45'.replace(' ', ''))
z80[0x100:0x104] = bytes.fromhex('d308 18fe'.replace(' ', ''))

fix = bytes(0x1000); spr = bytes(0x1000); pcm = bytes(0x1000)
ipl = b'TEST.FIX,0,0\r\nTEST.SPR,0,0\r\nTEST.Z80,0,0\r\nTEST.PCM,0,0\r\nTEST.PRG,0,0\r\n\x1a'

files = [('ABS.TXT', b'Abstracted by SNK corporation\x00'), ('BIB.TXT', b'Bibliographiced by SNK corporation\x00'),
         ('CPY.TXT', b'Copyright by SNK corporation\x00'), ('IPL.TXT', ipl), ('TEST.FIX', fix), ('TEST.PCM', pcm), ('TEST.PRG', bytes(prg)),
         ('TEST.SPR', spr), ('TEST.Z80', bytes(z80))]
files.sort()

ROOT = 20
lba = ROOT + 1
layout = []
for n, d in files:
    layout.append((n, d, lba)); lba += (len(d) + SEC - 1) // SEC
total = lba + 2
date = bytes([126, 9, 27, 12, 0, 0, 0])

def dirrec(name, lba, size, isdir):
    nb = name if isinstance(name, bytes) else (name + ';1').encode()
    l = 33 + len(nb); l += l & 1
    r = bytes([l, 0]) + both32(lba) + both32(size) + date + bytes([2 if isdir else 0, 0, 0]) + both16(1) + bytes([len(nb)]) + nb
    return r + bytes(l - len(r))

root = dirrec(b'\x00', ROOT, SEC, True) + dirrec(b'\x01', ROOT, SEC, True)
for n, d, l in layout: root += dirrec(n, l, len(d), False)
root = root + bytes(SEC - len(root))

pvd = bytearray(SEC)
pvd[0] = 1; pvd[1:6] = b'CD001'; pvd[6] = 1
pvd[8:40] = b' ' * 32; pvd[40:72] = b'NGCD_TEST'.ljust(32)
pvd[80:88] = both32(total)
pvd[120:124] = both16(1); pvd[124:128] = both16(1); pvd[128:132] = both16(SEC)
pvd[132:140] = both32(10)
pvd[140:144] = struct.pack('<I', 18); pvd[148:152] = struct.pack('>I', 19)
pvd[156:190] = dirrec(b'\x00', ROOT, SEC, True)
pvd[190:813] = b' ' * 623
for o in (813, 830, 847, 864): pvd[o:o+17] = b'2026092712000000\x00'
pvd[881] = 1
term = bytearray(SEC); term[0] = 255; term[1:6] = b'CD001'; term[6] = 1
lpt = bytes([1, 0]) + struct.pack('<I', ROOT) + struct.pack('<H', 1) + b'\x00\x00'
mpt = bytes([1, 0]) + struct.pack('>I', ROOT) + struct.pack('>H', 1) + b'\x00\x00'

img = bytearray(total * SEC)
def put(l, d): img[l*SEC:l*SEC+len(d)] = d
put(16, pvd); put(17, term); put(18, lpt); put(19, mpt); put(ROOT, root)
for n, d, l in layout: put(l, d)
open(sys.argv[1], 'wb').write(img)
print('%s: %d sectors' % (sys.argv[1], total), [(n, l, len(d)) for n, d, l in layout])
