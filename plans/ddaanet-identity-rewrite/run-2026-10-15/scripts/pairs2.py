import subprocess,collections
W='/tmp/claude-1000/identity-rewrite-h/'
def g(r,*a,check=True): return subprocess.run(['git','-C',W+r]+list(a),capture_output=True,check=check).stdout
def cmap(r): return dict(l.split() for l in list(open(W+r+'/filter-repo/commit-map'))[1:])
gm,mm,tm=cmap('gitlore-after.git'),cmap('memory-after.git'),cmap('tier-after.git')
def paths(r,o,n):
    out=g(r,'diff','--raw','--no-renames','-z',o,n).split(b'\0')
    return [p for p in out[1::2] if p]
def gl(r,c,p):
    s=g(r,'ls-tree',c,p).decode().split()
    return s[2] if s and s[0]=='160000' else None
st=collections.Counter(); bad=[]; pairmem={}
for o,n in gm.items():
    ps=paths('gitlore-after.git',o,n)
    if ps==[]: st['tree-identical']+=1; 
    elif ps!=[b'memory']: st['OTHER']+=1; bad.append((o,n,ps)); continue
    oc,nc=gl('gitlore-after.git',o,'memory'),gl('gitlore-after.git',n,'memory')
    pairmem[n]=(oc,nc)
    if ps==[]: continue
    if oc is None or nc is None: st['memory-added-removed']+=1; continue
    if oc not in mm: st['mem-old-unmapped']+=1; continue
    if mm[oc]!=nc: st['NEWGITLINK!=MAP']+=1; bad.append((o,n)); continue
    mp=paths('memory-after.git',oc,nc)
    if any(p!=b'ddaanet' for p in mp): st['MEM-OTHER']+=1; bad.append((o,n,mp)); continue
    if mp:
        ot,nt=gl('memory-after.git',oc,'ddaanet'),gl('memory-after.git',nc,'ddaanet')
        if ot in tm and tm[ot]==nt and g('tier-after.git','rev-parse',ot+'^{tree}')==g('tier-after.git','rev-parse',nt+'^{tree}'): st['mem-diff-ddaanet-tier-trees-identical']+=1
        elif ot==nt: st['mem-diff-ddaanet-unmapped-same']+=1
        else: st['TIER-BAD']+=1; bad.append((o,n,ot,nt))
    else: st['mem-trees-identical']+=1
print(dict(st),'pairs',len(gm),'BAD',bad[:10])
import json; json.dump(pairmem,open(W+'pairmem.json','w'))
