import sys,subprocess,collections
# pairs.py repo_after path childrepo_after(tiermap_repo) childmap-file
a,path,tier,tmap=sys.argv[1:5]   # a: repo whose map to walk; path: gitlink path; tier: repo holding old+new submodule commits; tmap: submodule commit-map
def g(r,*args): return subprocess.run(['git','-C',r]+list(args),capture_output=True,check=True).stdout
m=[l.split() for l in open(a+'/filter-repo/commit-map')][1:]
tm={}
for l in list(open(tmap))[1:]:
    o,n=l.split(); tm[o]=n
stats=collections.Counter(); bad=[]
for o,n in m:
    out=g(a,'diff','--raw','--no-renames','-z',o,n).split(b'\0')
    paths=[out[i] for i in range(1,len(out)-1,2)] if out!=[b''] else []
    # raw -z: ":meta\0path\0" pairs
    meta=out[0::2]; paths=out[1::2]
    paths=[p for p in paths if p]
    if not paths: stats['identical-tree']+=1; continue
    if paths!=[path.encode()]: stats['OTHER-PATHS']+=1; bad.append((o,n,paths)); continue
    ot=g(a,'rev-parse',o+':'+path).strip().decode() if False else None
    # gitlink ids
    def gl(c):
        s=g(a,'ls-tree',c,path).decode().split()
        return s[2]
    oc,nc=gl(o),gl(n)
    if oc not in tm: stats['gitlink-diff-unmapped-old']+=1; continue
    if tm[oc]!=nc: stats['GITLINK-NEW!=MAP']+=1; bad.append((o,n,oc,nc)); continue
    ot=g(tier,'rev-parse',oc+'^{tree}').strip(); nt=g(tier,'rev-parse',nc+'^{tree}').strip()
    if ot==nt: stats['gitlink-diff-tier-trees-identical']+=1
    else: stats['TIER-TREE-DIFFERS']+=1; bad.append((o,n,oc,nc))
print(dict(stats),'pairs',len(m)); print('BAD',bad[:10])
