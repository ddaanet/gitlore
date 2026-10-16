import subprocess,re,collections
W='/tmp/claude-1000/identity-rewrite-h/'
def cmap(r): return dict(l.split() for l in list(open(W+r+'/filter-repo/commit-map'))[1:])
pre={}
for repo,r in (('gitlore','gitlore-after.git'),('memory','memory-after.git'),('tier','tier-after.git')):
    for o,n in cmap(r).items():
        if o==n: continue
        for L in range(7,41): pre.setdefault(o[:L],set()).add(repo)
rx=re.compile(rb'(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])')
rows=[]
def scan(repo,ref,prefix):
    p=subprocess.run(['git','-C',W+repo,'ls-tree','-r','-z','--format=%(objectmode) %(objectname) %(path)',ref],capture_output=True,check=True).stdout
    items=[e for e in p.split(b'\0') if e]
    ents=[]
    for e in items:
        mode,sha,path=e.split(b' ',2)
        if mode==b'160000': continue
        ents.append((sha,path))
    inp=b''.join(s+b'\n' for s,_ in ents)
    # batch read
    pr=subprocess.Popen(['git','-C',W+repo,'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    out,_=pr.communicate(inp)
    pos=0
    for sha,path in ents:
        nl=out.index(b'\n',pos); hdr=out[pos:nl].split(); size=int(hdr[2]); data=out[nl+1:nl+1+size]; pos=nl+1+size+1
        if b'\0' in data[:8000]: continue
        for i,line in enumerate(data.split(b'\n'),1):
            for mo in rx.finditer(line):
                t=mo.group(0).decode()
                if t in pre:
                    rows.append((prefix+path.decode('utf8','replace'),i,t,'/'.join(sorted(pre[t]))))
scan('gitlore-after.git','refs/heads/main','')
scan('memory-after.git','refs/heads/live','memory/')
scan('tier-after.git','refs/heads/live','memory/ddaanet/')
with open(W+'stale.md','w') as f:
    f.write('| file | line | token | repo-of-id |\n|---|---|---|---|\n')
    for r in rows: f.write('| %s | %d | %s | %s |\n'%r)
c=collections.Counter(); 
for r in rows:
    parts=r[0].split('/'); top=parts[0] if len(parts)==1 else parts[0]+'/'+(parts[1] if parts[0]=='memory' else '')
    c[top.rstrip('/')]+=1
print(len(rows)); 
for k,v in sorted(c.items(),key=lambda x:-x[1]): print(k,v)
print('files',len({r[0] for r in rows}), 'by repo-of-id',collections.Counter(r[3] for r in rows))
