# Prints the CRC each vendor module was built with for the given symbols.
# usage: crcs.py <folder of .ko files> <symbol> [symbol...]
import sys,glob,struct
want=set(sys.argv[2:]); found={}
for f in glob.glob(sys.argv[1]+'/*.ko'):
    b=open(f,'rb').read()
    shoff=struct.unpack_from('<Q',b,0x28)[0]; shentsize,shnum,shstrndx=struct.unpack_from('<HHH',b,0x3a)
    sh=[struct.unpack_from('<IIQQQQIIQQ',b,shoff+i*shentsize) for i in range(shnum)]
    stro=sh[shstrndx][4]
    for s in sh:
        name=b[stro+s[0]:b.index(b'\0',stro+s[0])].decode()
        if name=='__versions':
            for o in range(s[4],s[4]+s[5],64):
                crc=struct.unpack_from('<Q',b,o)[0]; n=b[o+8:o+64].split(b'\0')[0].decode()
                if n in want: found.setdefault(n,set()).add(crc)
for n in sorted(want): print(n, [hex(c) for c in found.get(n,[])])
