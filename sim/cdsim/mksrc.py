# Copies the core sources for Verilator, dropping initializers of variables
# declared inside always blocks (Verilator 5.030 re-runs them every time the
# block executes). Reports every change; non-zero ones are listed for review.
import re, os, sys
S=os.path.dirname(os.path.abspath(__file__))
out_list=[]
decl=re.compile(r'^(\s*)(reg|integer|logic|bit|int)\b(.*);(.*)$')
tok=re.compile(r'\b(begin|end|fork|join)\b')
nonzero=[]
for line in open(os.path.join(S,sys.argv[1] if len(sys.argv)>1 else 'files.f')):
    f=line.strip()
    if not f or f.startswith('+'): out_list.append(f); continue
    src=open(f,encoding='latin-1').read().replace('\r','')
    lines=src.split('\n')
    in_al=False; depth=0; seen=False
    for i,l in enumerate(lines):
        code=l.split('//')[0]
        if not in_al and re.search(r'\balways(_ff|_comb|_latch)?\b',code):
            in_al=True; depth=0; seen=False
        if in_al:
            m=decl.match(l)
            if m and depth>0 and '=' in m.group(3):
                # remove "= expr" parts (top level commas)
                body=m.group(3); parts=[]; cur=''; lvl=0
                for ch in body:
                    if ch in '([{': lvl+=1
                    if ch in ')]}': lvl-=1
                    if ch==',' and lvl==0: parts.append(cur); cur=''
                    else: cur+=ch
                parts.append(cur)
                newp=[]
                for p in parts:
                    if '=' in p:
                        name,val=p.split('=',1)
                        v=val.strip()
                        if not re.fullmatch(r"(\d+'[bdh])?0+|'0|\d*'b0+|0",v.replace('_','')):
                            nonzero.append('%s:%d: %s'%(f,i+1,l.strip()))
                        newp.append(name.rstrip())
                    else: newp.append(p)
                lines[i]='%s%s%s;%s'%(m.group(1),m.group(2),','.join(newp),m.group(4))
            for t in tok.findall(code):
                if t in('begin','fork'): depth+=1; seen=True
                else: depth-=1
            if seen and depth<=0: in_al=False
            elif not seen and ';' in code and not re.search(r'\balways',code) : pass
    dst=os.path.join(S,'src',f.lstrip('/'))
    os.makedirs(os.path.dirname(dst),exist_ok=True)
    open(dst,'w').write('\n'.join(lines))
    out_list.append(dst)
out=[]
for x in out_list:
    pass
    out.append(x)
open(os.path.join(S,sys.argv[2] if len(sys.argv)>2 else 'files_sim.f'),'w').write('\n'.join(out)+'\n')
print('\n'.join(nonzero))
