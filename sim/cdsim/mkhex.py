import sys
bios=open(sys.argv[1],'rb').read()
out=open(sys.argv[2],'w')
# word k = b[2k+1]<<8 | b[2k]  (same as the ioctl/memcp load)
words=[(bios[2*k+1]<<8)|bios[2*k] for k in range(len(bios)//2)]
out.write('@0\n'+'\n'.join('%04x'%w for w in words)+'\n')
# fill_ram(128K, 0xAA) -> memcp index 18 -> SDRAM byte 0x100000
out.write('@80000\n'+'\n'.join(['aaaa']*0x10000)+'\n')
