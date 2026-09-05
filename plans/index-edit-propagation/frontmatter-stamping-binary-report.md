# How Claude Code stamps memory frontmatter — binary reading

**Binary inspected:** `/Users/david/.local/share/claude/versions/2.1.261`
(bun single-file executable, bundle self-identifies as `// Version: 2.1.261`).

**Method.** The bundle's JS is stored as plain text inside the executable. I made
an offset-preserving copy with `tr '\0' '\n' < <binary> > bin261.txt` (same byte
length, so every offset below is a true offset into the shipped binary) and read
regions out with `dd`. All offsets are decimal byte offsets.

Two disjoint regions contain the literals of interest: ~91–99 MB is a serialized
string pool (bytecode constants — not code), ~177–210 MB is the readable JS
bundle. Everything load-bearing below is quoted from the JS region.

---

## 1. Mechanism

### 1.1 There is exactly one writer

The whole mechanism is one function. Its own log messages name it
`stampNewMemoryContent`; the minified symbol is `nY`, defined at **182889417**
(regexes) / **182889475** (function):

```js
// @182889417
var lQr=/^(\s*)modified\s*:/,SXe=/^\s*(#|$)/,bXe=/^\s+\S/;
function nY(e,t){
  if(!(e.endsWith(".md")&&QO(e))||!KL.test(t))return t;
  let o=new Date().toISOString(),
      d=D2(e)?null:Iv(t,e,{quoteLossyValues:!0}),
      f=d!==null&&Dpe(d.frontmatter,"originSessionId")===null?d:null;
  if(f!==null){
    if(f.rewriteHazard===void 0)
      return Ser(ber(f.frontmatter,{originSessionId:Y(),modified:o}),f.body);
    n(`stampNewMemoryContent: not stamping provenance on ${e} — ${f.rewriteHazard}`,{level:"warn"})
  }
  let y=cQr(t,o);
  if(y===null)return n(`stampNewMemoryContent: not dating ${e} — no faithful place for a modified line`,{level:"warn"}),t;
  return y
}
```

`nY` is a **pure content transform**: it takes `(absolutePath, newContent)` and
returns the content to write. It performs no I/O, has no timer, no debounce, no
queue. It is called synchronously by the tool handler *before* the bytes reach
disk.

`Ser` — the function that emits `node_type` — is called from exactly two places
in the whole bundle: its own definition and this line. Strict-identifier grep:

```
$ grep -abo -E '[^A-Za-z0-9_$]Ser\(' bin261.txt
179689076: Ser(      # inside its own definition
182889729: Ser(      # inside nY
```

### 1.2 The two branches

**Provenance branch** (taken when `metadata.originSessionId` is absent, and the
path is *not* under the team-memory subdirectory). It reserializes the entire
frontmatter block. `Ser` at **179689068**:

```js
// @179688142
var Id=["name","description","metadata"],Od=/^[a-z0-9_-]+$/,Dd="memory",
Ro=(e)=>typeof e==="string"&&e.length>0?e:null,
Nd=(e)=>{let t=me(e.metadata)?e.metadata:{},
  r=Object.entries(e).reduce((o,[d,f])=>{if(Id.includes(d)||f==null)return o;return o[d]=f,o},{});
  return{name:Ro(e.name),description:Ro(e.description),metadata:Object.freeze({...r,...t})}};
function Iv(e,t,r){let{frontmatter:o,content:d,rewriteHazard:f}=Vo(e,t,r);
  return{frontmatter:Nd(o),body:d,...f!==void 0&&{rewriteHazard:f}}}
...
var Dpe=(e,t)=>Ro(e.metadata[t]),
    ber=(e,t)=>({...e,metadata:Object.freeze({...e.metadata,...t})}),
    $d=(e)=>Od.test(e)?e:e.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"");
function Ser(e,t){
  let r=Object.fromEntries([["node_type",Dd],...Object.entries(e.metadata).filter(([f])=>f!=="node_type")].filter(([,f])=>f!=null)),
      o={name:$d(e.name??""),...e.description!==null&&{description:e.description},metadata:r},
      d=t.replace(/^\n+/,"");
  return`---\n${VFe(o)}---\n\n${d}`}
```

So the provenance branch is not a surgical insert — it rewrites the block:
`node_type: memory` is forced to the front of `metadata`, `name` is slugified
by `$d`, null-valued metadata entries are dropped, and (via `Nd`) **any
top-level frontmatter key other than `name`/`description`/`metadata` is folded
into `metadata`**. Leading blank lines of the body are stripped.

`VFe` at **179409310**, in the frontmatter chunk:

```js
function $I(e){return Bun.YAML.parse(e)}
function VFe(e){return Bun.YAML.stringify(e,null,2)+`\n`}
```

That is where the trailing space in `metadata: ` comes from. Verified
empirically with `bun 1.3.13`:

```
$ bun -e 'process.stdout.write(Bun.YAML.stringify({name:"s",metadata:{node_type:"memory"}},null,2))' | cat -A
name: s$
metadata: $
  node_type: memory$
```

*(Inference: the bun runtime embedded in 2.1.261 is not necessarily 1.3.13, so
this is a same-behaviour-in-a-nearby-version check rather than a check of the
shipped emitter. The rest of the shape — key order, the blank line after the
closing `---` — is read directly from `Ser` above.)*

**Dating branch** (`cQr`, at **182890044**) — taken when `originSessionId` is
already present, when the path is under team memory, or when the provenance
branch bailed on a `rewriteHazard`. It rewrites *only* the `modified:` line, and
then proves the rewrite was faithful before returning it:

```js
function cQr(e,t){
  let r=e.match(KL),o=e.match(Wve);
  if(r===null||o===null||r[1].trim()!==o[1].trim())return null;
  let d=Iv(e),{name:f,description:y,metadata:E}=d.frontmatter;
  if(f===null&&y===null&&Object.keys(E).length===0)return null;
  let v=o[0].length,x=e.slice(0,v).split(`\n`),
      D=e.slice(0,v).includes(`\r\n`)?"\r":"",
      N=(be,ke="")=>`${be}modified: ${t}${ke}${D}`,
      F=x.flatMap((be,ke)=>ke>0&&ke<x.length-1&&lQr.test(be)?[ke]:[]);
  if(F.length>1||F.length===0&&"modified"in E)return null;
  let B=F[0],
      q=B!==void 0?[...x.slice(0,B),N(...uQr(xO(x[B]))),...x.slice(B+1)]:dQr(x,N);
  if(q===null)return null;
  let re=q.join(`\n`)+e.slice(v),ue=Iv(re),de=re.match(Wve);
  return Qs(ue.frontmatter,{...d.frontmatter,metadata:{...E,modified:t}})&&ue.body===d.body&&de!==null&&re.slice(de[0].length)===e.slice(v)?re:null}
```

`dQr` (same region) decides where to *insert* a `modified:` line when none
exists: it finds a block-style `metadata:` line (`/^metadata:\s*(#.*)?$/`),
walks to the end of that block, and inserts at the block's own indentation
(default two spaces). If a `/^metadata:/` line exists but is not block-style —
an inline `metadata: {…}` flow mapping — it returns `null` and nothing is
stamped. If there is no `metadata:` line at all it inserts before the closing
`---` at top level.

### 1.3 Triggers — three call sites, all tool handlers

Grep for the identifier (`grep -abo -F 'nY('`) returns 11 hits; 7 are a
different `nY` in other chunks (fast-mode status strings, a Zod schema pruner),
1 is inside the definition. The three real call sites:

**(i) `Edit` — `FileEditTool`, handler `Aeo`, at 183040994:**

```js
// @183040900
Gt=Jue(De,F)||F,en=knn(F,Gt,GDe(F,Gt,B)),
tn=bgt({filePath:q,fileContents:De,oldString:Gt,newString:en,replaceAll:N}),
dn=nY(q,tn.updatedFile),cn=dn!==tn.updatedFile,
xt=!cn?tn.patch:ywe({filePath:q,oldContent:De,newContent:dn,convertTabs:!0}),Nn;
await Me.recheckBeforeWrite();
try{Nn=await AQ(Me.ioPath,dn,Ke,et)}catch(Qt){throw kf(q),Qt}
```

Note `cn` (`memdirStamped`) is surfaced in the tool result and changes the
message the model sees.

**(ii) `Write` — `FileWriteTool`, handler `dio`, at 183299400:**

```js
// @183299370
let Re=Pe?.encoding??"utf8",Ie=Pe?.content??null,Oe=t;
t=nY(N,t);
let Me=t!==Oe,De;
await ke.recheckBeforeWrite();
try{De=await AQ(ke.ioPath,t,Re,"LF")}catch(je){throw kf(N),je}
```

**(iii) The memory-store `write` tool** (`searchHint:"save a document to a
memory store"`), at 185125637:

```js
// @185125540
async call({store:e,path:t,content:r,if_version:o},{abortController:{signal:d}}){
  let f=CB(r),y=my(t),E=MQ({storeId:e,write:!0});
  ...
  let{kind:v}=E.served,
      x=v==="personal"?CB(nY(h$(y),f)):f,
```

`h$(e)` is `RVo(Os(),...e.split("/"))` (**185094212**) — the store-relative path
joined onto the memory root. **Only `kind==="personal"` stores are stamped
here**; `project`/`team` store writes go to disk as `f`, unstamped.

There is no fourth writer, no file watcher, no save-path hook, and no
post-tool-use pass. The three tool handlers are the entire surface.

---

## 2. The three claims

### (a) These fields are written by auto-memory and by nothing else

**CONFIRMED.**

- `originSessionId` appears at 4 offsets in the whole binary. 95624200 is the
  string pool. 179409073 is inside a passive allow-list of recognised
  frontmatter keys in the frontmatter chunk (`var R=["name","description",
  "model","allowed-tools",…,"type","originSessionId","hide-from-slash-command-
  tool"]`) — a parser key list, not a writer. The remaining two, 182889650 and
  182889753, are both inside `nY` (the `Dpe(...,"originSessionId")` read and the
  `originSessionId:Y()` write).
- `node_type` appears at 4 offsets. 885477 and 97497788 are non-code data.
  179689114 and 179689178 are both inside `Ser` (`["node_type",Dd]` and the
  `f!=="node_type"` filter).
- `modified: ` as a written literal appears twice in the JS region: 182890380
  (inside `cQr`) and 182185946 / 190760181 / 203180532 which are MCP messages
  (`MCPB file modified: mtime …`, `File modified: <path>`), not frontmatter.

`Ser` — the only emitter of the block — has exactly one call site, inside `nY`.
Two other `Bun.YAML.stringify` frontmatter writers exist (193151742, 193166817)
but they are the Codex/Gemini config importers writing subagent and command
files; they emit only `name`/`description`/`allowed-tools`.

### (b) `modified:` restamped on every Edit/Write to a memory file; not on Bash

**The Bash half is CONFIRMED. The "every Edit/Write" half is CONTRADICTED as
stated — the code shows several silent skips.**

*Bash.* A normal Bash tool call spawns a shell; nothing in that path touches
`nY`. There is also a non-obvious second Bash write path — an internal
`_simulatedSedEdit` input that applies a pre-computed `sed -i` result in-process
(schema at **185695134**, dispatch at **185705449**):

```js
async call(e,t,r,o,d){if(e._simulatedSedEdit&&!t.remoteCall)return its(e._simulatedSedEdit,t,o);
```

`its` at **185698775** writes the precomputed content straight through:

```js
function its(e,t,r){let{filePath:o,newContent:d,baseHash:f}=e,y=ot(o),E=E1(t,y);
  ...
  try{await N.recheckBeforeWrite(),re=await AQ(N.ioPath,d,x,D)}catch(de){throw kf(y),de}
```

No `nY`. So both Bash paths — real subprocess and simulated sed — leave the file
unstamped. A `python3` heredoc is the ordinary subprocess path and is likewise
untouched.

*Edit/Write.* `nY` is reached unconditionally on every call, but returns `t`
unchanged, silently or with only a `warn`-level log, in all of these cases:

1. `!e.endsWith(".md")` — a non-`.md` file under the memory dir is never stamped.
2. `!QO(e)` — path not lexically under the memory root (see §3).
3. `!KL.test(t)` where `KL=/^---\s*\n([\s\S]*?)---\s*\n?/` (**179410780**) — the
   *new* content must open with a `---` fence at byte 0. Note `KL` is tested on
   raw `t`, before the BOM strip that `Vo` does internally, so a BOM defeats it.
4. `cQr` returns `null`, logging `not dating … no faithful place for a modified
   line`, when: the opening and closing fences disagree
   (`KL` vs `Wve=/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(\r?\n|$)/`); the
   frontmatter has no `name`, no `description` and empty `metadata`; there is
   more than one `modified:` line; there is no `modified:` line yet `"modified"
   in E`; `dQr` finds an inline `metadata: {…}`; or the final faithfulness
   check (reparsed frontmatter deep-equals the original plus the new `modified`,
   body byte-identical, tail byte-identical) fails.
5. The path is under team memory (`D2`) *and* has no `modified:` line and no
   block-style `metadata:` — then `dQr` inserts before the closing `---`, which
   is fine, but if the block-style/flow test fails it returns null.

Also: when the provenance branch fires, `modified` is set by `Ser`, not `cQr` —
same value, different code path, and the whole block is reformatted at the same
time.

There is **no debounce and no batching**: `o=new Date().toISOString()` is taken
at the top of `nY`, inside the handler, one stamp per tool call. The ~300 ms
correlations in the behavioural sample are consistent with this; the code shows
the stamp is in fact synchronous with the write, and any lag observed is the
tool call's own latency.

One consequence worth stating: the Edit handler stamps even when the edit does
not touch the frontmatter, because `nY` runs on the whole post-edit document.

### (c) `originSessionId` is stamped at creation only, never rewritten

**CONFIRMED as "never rewritten", CONTRADICTED as "names the file's creator".**

The guard is `Dpe(d.frontmatter,"originSessionId")===null` — a read of the
*existing* content. If the key is present and a non-empty string, `f` is null and
the provenance branch is skipped entirely; `ber({originSessionId:Y()})` is
unreachable. Nothing anywhere else writes the key (see (a)). So it is never
overwritten once set. That part holds.

What is too strong is "at file creation". The condition is *absence of the key*,
not *absence of the file*. Any Edit or Write through the tool to an existing
memory `.md` that lacks `originSessionId` will stamp it with the **editing**
session's id and reserialize the block. A file created by `Bash` (unstamped) and
later edited by the tool therefore carries the id of the *editor*, not the
creator. So `originSessionId` names *the first session that wrote the file
through Edit/Write/the memory tool*, which coincides with the creator only when
the file was created through those tools.

`Y()` is defined at **177050985**:

```js
function n(){return C()?.session??y}
function g(){let e=C();return e?.session?void 0:e}
var C=()=>{return};function $br(e){C=e}
function Y(){return g()?.sessionId??n().id}
```

`$br` is exported as `setSessionOverridesGetter` (name table at **191614581**),
so `C` is installable; by default it returns undefined and `Y()` is the ambient
session id.

---

## 3. Scope conditions

**Which directories count.** `QO` at **179197970**:

```js
function QO(e){return jl(e).startsWith(Os())}
```

`jl` is `path.normalize` — the aliased import is visible at **178613700**:
`import{isAbsolute as lde,join as Kl,normalize as jl,sep as Yl}from"path"`. So
the test is a **lexical prefix match with no realpath resolution**: a memory
directory reached through a symlink, or a path spelled with decomposed Unicode
(`Os()` is `.normalize("NFC")`, `QO`'s argument is not), will not match and will
not be stamped. *(Inference from the code: I did not empirically test the
symlink case.)*

`Os()` resolves, in order (**179196000–179198000**):

1. `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE`
2. `autoMemoryDirectory` from settings, first hit of
   `policySettings, flagSettings, [localSettings, projectSettings], userSettings`
   (`~/` expanded, `..`-escape rejected)
3. default: `<CLAUDE_CODE_REMOTE_MEMORY_DIR ?? ~/.claude>/projects/<project-slug>/memory/`

Always with a trailing separator and NFC-normalized.

**Team memory is inside the memory dir and is treated differently.**
`_nt="team"` (**177507726**), `j_()` (**179732131**) is `Os()/team/`, and
`D2` (**179733341**) is:

```js
function D2(e){let t=P2(Ma(e)),r=P2(j_());return t+$n===r||t.startsWith(r)}
```

with `P2(e)=e.normalize("NFC").toLowerCase()` (**179687507**) — so this one *is*
case-insensitive. Because `nY` does `D2(e)?null:Iv(...)`, files under
`<memory>/team/` **never get `originSessionId` or `node_type`**; they only ever
get the surgical `modified:` rewrite. Team files are still under `Os()`, so
`QO` is true and the dating branch does run.

**Subagents.** Subagent tool calls go through the same `FileEditTool`/
`FileWriteTool` handlers — there is no separate write path — so they stamp
identically. `Y()` reads the ambient session id and never consults the agent id
(`Ve()` is the agent-id accessor and is not used here), so a subagent's writes
carry the parent session's id. *(Inference: this depends on no
`setSessionOverridesGetter` being installed with a distinct `sessionId` for
subagent execution; I traced the setter's export but not every caller.)*

**A file lacking the fields does acquire them** — see (c). This is the main
mechanism by which a hand-written or `Bash`-written memory file becomes stamped.

**Rename / move.** The three fields live in the file *content*, not in
filesystem metadata, so a `mv` carries them verbatim and stamps nothing (`mv` is
Bash). There is no rename or delete operation in the memory-store tool family
either: the tool set is exactly three tools — list (**185112149**, read-only),
read (**185116192**, read-only), write (**185123492**). So nothing in the bundle
observes a rename.

**Memory pause does not stop stamping.** `wb()` (memory paused, message
`"Memory is paused. Run /pause-memory to resume automemory."`) gates the memory
tools (**185094965**) and a permission wrapper (**185475556**), but `nY` has no
pause check — an `Edit` to a memory `.md` still restamps while memory is paused.

**`MEMORY.md`.** `iQ()` is `Os()/MEMORY.md`, so the index file is inside the
stamping scope and is `.md`. It is spared only by rule (3) above: it has no
`---` fence, so `KL.test(t)` is false and `nY` returns it untouched. If a
frontmatter block were ever added to it, it would start being stamped.

**Why `modified` matters downstream.** The memory listing sorts by it and falls
back to mtime when it is absent or unparseable (**182046088**):

```js
let{frontmatter:B,body:q}=Iv(N,D),re=Dpe(B,"modified"),ue=re===null?NaN:Date.parse(re);
return{filename:x,filePath:D,mtimeMs:F,modifiedMs:Number.isNaN(ue)?F:ue,...}
```

**Version spread.** The literal `stampNewMemoryContent: not stamping provenance`
is present in 2.1.258, 2.1.259, 2.1.260 and 2.1.261 alike. I did not diff the
function bodies across those four.

---

## What the binary cannot settle

- Whether the *shipped* bun's `Bun.YAML.stringify` emits `metadata: ` with the
  trailing space. The code proves the emitter is `Bun.YAML.stringify(o,null,2)`;
  the trailing space is confirmed on bun 1.3.13 on this machine, not on the
  embedded runtime. Settling it properly means observing a file actually written
  by 2.1.261 — which the 13-file sample already does.
- Whether a subagent ever runs with an overridden session id. Settling it means
  finding every caller of the exported `setSessionOverridesGetter`, or simply
  writing a memory file from a subagent and comparing `originSessionId` to the
  parent session's id.
- Whether the `_simulatedSedEdit` preview path is ever *offered* for paths under
  the memory dir. It does not matter for the stamping conclusion — `its()`
  never stamps either way — but it does mean a `sed -i` may write in-process
  rather than via a subprocess, which changes nothing observable about
  frontmatter.
