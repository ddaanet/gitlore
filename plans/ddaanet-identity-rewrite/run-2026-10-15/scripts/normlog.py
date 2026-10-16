import sys,re,subprocess
# usage: normlog.py before.git after.git ref fmt   -> prints "n_total n_msgdiff_only_ids n_other"
b,a,ref,fmt=sys.argv[1:5]
m={}
with open(a+'/filter-repo/commit-map') as f:
    next(f)
    for l in f:
        o,n=l.split(); m[o]=n
def log(r,ref):
    out=subprocess.run(['git','-C',r,'log','--format='+fmt+'%x00',ref],capture_output=True,check=True).stdout.decode()
    return out.split('\0')
def sub(mo):
    t=mo.group(0)
    c=[o for o in m if o.startswith(t)]
    return m[c[0]][:len(t)] if len(c)==1 else t
L1=log(b,ref); L2=log(a,ref)
assert len(L1)==len(L2),(len(L1),len(L2))
same=idonly=other=0
for x,y in zip(L1,L2):
    if x==y: same+=1; continue
    x2=re.sub(r'\b[0-9a-f]{7,40}\b',sub,x)
    if x2==y: idonly+=1
    else: other+=1; print('OTHER',repr(x[:200]),repr(y[:200]))
print(ref,'entries',len(L1)-1,'identical',same,'differ-only-by-remapped-embedded-ids',idonly,'other',other)
