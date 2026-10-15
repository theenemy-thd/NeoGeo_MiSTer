# Test "BIOS" for the NeoGeo CD core sim: copies a timing test to $000400 and
# runs it. Each section writes a marker to $100000 so the testbench can time it.
import struct
def w(*v): return b''.join(struct.pack('>H',x) for x in v)
def l(x): return struct.pack('>I',x)
bios=bytearray(0x80000)
bios[0:4]=l(0x0010F300); bios[4:8]=l(0x00C01004)
for v in range(2,64): bios[v*4:v*4+4]=l(0x00C00300)
bios[0x300:0x302]=w(0x4E73)                     # rte
boot = w(0x46FC,0x2700) + w(0x41F9)+l(0xC01000) + w(0x43F9)+l(0x400) + w(0x3E3C,0x01FF) \
     + w(0x32D8) + w(0x51CF,0xFFFC) + w(0x4EF9)+l(0x400)
bios[0x400:0x400+len(boot)]=boot
t=bytearray(w(0x46FC,0x2700))   # at $C01000: move #$2700,sr
def marker(k): t.extend(w(0x33FC,k)+l(0x100000))
def loop(n, body, count):
    t.extend(w(0x3E3C,count-1)); start=0x400+len(t)
    for _ in range(n): t.extend(body)
    here=0x400+len(t)                    # dbra opcode address
    t.extend(w(0x51CF, (start-(here+2)) & 0xffff))
marker(1); loop(16, w(0xD041), 4096)                                     # ALU: fetch only
marker(2); t.extend(w(0x41F9)+l(0x100100)); loop(8, w(0x3010), 4096)      # work RAM reads
marker(3); t.extend(w(0x43F9)+l(0x3C0002)+w(0x33FC,0)+l(0x3C0000)+w(0x33FC,1)+l(0x3C0004)); loop(8, w(0x3280), 1024)  # VRAM writes
marker(4); t.extend(w(0x41F9)+l(0x3C0002)); loop(8, w(0x3010), 1024)      # VRAM reads
marker(5); t.extend(w(0x41F9)+l(0x320000)); loop(8, w(0x1010), 1024)      # sound reply reads
marker(6); t.extend(w(0x60FE))
bios[0x1000:0x1000+len(t)]=t
open('spdbios.bin','wb').write(bios)
print("test code", len(t), "bytes")
