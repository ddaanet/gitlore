import subprocess, re, sys
W='/tmp/claude-1000/identity-rewrite-h'
def g(repo,*a): return subprocess.run(['git','-C',f'{W}/{repo}-after.git',*a],check=True,capture_output=True).stdout.decode()
def cmap(repo):
    m={}
    for l in open(f'{W}/{repo}-after.git/filter-repo/commit-map').read().split('\n')[1:]:
        if l: o,n=l.split(); m[o]=n
    return m
T,M,G=cmap('tier'),cmap('memory'),cmap('gitlore')
allmap={**T,**M,**G}
def tree(repo,c): return g(repo,'rev-parse',c+'^{tree}').strip()
def gl(repo,c,p):
    out=g(repo,'ls-tree',c,'--',p).split()
    return out[2] if out and out[0]=='160000' else None
def msg(repo,c): return g(repo,'cat-file','commit',c).split('\n\n',1)[1]
def hdr(repo,c): return [l for l in g(repo,'cat-file','commit',c).split('\n\n',1)[0].split('\n') if l.startswith(('author','committer'))]
hexre=re.compile(r'\b[0-9a-f]{7,40}\b')
def remap(s):
    def f(mo):
        t=mo.group(0); hits=[o for o in allmap if o.startswith(t)]
        return allmap[hits[0]][:len(t)] if len(hits)==1 else t
    return hexre.sub(f,s)
bad=[]
def dates(h): return [re.sub(r'^(\w+) .*> ',r'\1 ',l) for l in h]
def common(repo,o,n):
    if dates(hdr(repo,o))!=dates(hdr(repo,n)): bad.append((repo,o,'dates'))
    mo,mn=msg(repo,o),msg(repo,n)
    if mo!=mn and remap(mo)!=mn: bad.append((repo,o,'message'))
def diffpaths(repo,o,n): return [l.split('\t',1)[1] for l in g(repo,'diff-tree','-r','--no-renames','--raw',o,n).splitlines() if '\t' in l]
for o,n in T.items():
    if o==n: continue
    common('tier',o,n)
    if tree('tier',o)!=tree('tier',n): bad.append(('tier',o,'tree'))
def sub_ok(subrepo,o,n):
    return o==n or (o and n and tree(subrepo,o)==tree(subrepo,n))
memdiff={}
for o,n in M.items():
    if o==n: continue
    common('memory',o,n)
    ps=diffpaths('memory',o,n)
    if set(ps)-{'ddaanet'}: bad.append(('memory',o,'paths',ps))
    elif ps and not sub_ok('tier',gl('memory',o,'ddaanet'),gl('memory',n,'ddaanet')): bad.append(('memory',o,'tiertree'))
def mem_equiv(o,n):
    if o==n: return True
    ps=diffpaths('memory',o,n)
    return not (set(ps)-{'ddaanet'}) and (not ps or sub_ok('tier',gl('memory',o,'ddaanet'),gl('memory',n,'ddaanet')))
for o,n in G.items():
    if o==n: continue
    common('gitlore',o,n)
    ps=diffpaths('gitlore',o,n)
    if set(ps)-{'memory'}: bad.append(('gitlore',o,'paths',ps))
    elif ps:
        a,b=gl('gitlore',o,'memory'),gl('gitlore',n,'memory')
        if b!=M.get(a,a) or not mem_equiv(a,b): bad.append(('gitlore',o,'memtree',a,b))
# tags and tips
for l in g('gitlore','for-each-ref','--format=%(refname) %(objectname)','refs/before/tags','refs/before/heads').splitlines():
    ref,_=l.split(); new=ref.replace('refs/before/','refs/')
    op=g('gitlore','rev-parse',ref+'^{commit}').strip(); np=g('gitlore','rev-parse',new+'^{commit}').strip()
    if G[op]!=np: bad.append(('tag/tip',new))
print('pairs tier/mem/gitlore changed:',sum(o!=n for o,n in T.items()),sum(o!=n for o,n in M.items()),sum(o!=n for o,n in G.items()))
print('BAD',len(bad)); [print(b) for b in bad[:30]]
