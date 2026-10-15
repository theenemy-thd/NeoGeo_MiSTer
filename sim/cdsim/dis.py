import sys, subprocess
U='/root/.claude/uploads/318fcbfa-b65f-58cc-a3f0-144783abf396/'
files={'top':U+'42be829d-top-sp1.bin','cdz':U+'387f70dc-neocd.bin','uni':U+'21dd5d6b-uni-bioscd.rom'}
b=open(files[sys.argv[1]],'rb').read()
b=bytes(x for i in range(0,len(b),2) for x in (b[i+1],b[i]))
a=int(sys.argv[2],16); n=int(sys.argv[3],16) if len(sys.argv)>3 else 0x40
off=a-0xC00000
hx=b[off:off+n].hex()
r=subprocess.run(['/tmp/claude-0/-home-claude/318fcbfa-b65f-58cc-a3f0-144783abf396/scratchpad/capstone/build/cstool','m68k',hx,hex(a)],capture_output=True,text=True)
print(r.stdout)
