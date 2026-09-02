# Bang-expansion (`` !`cmd` ``) hook dispatch — decompile findings

## Question

When a slash-command/skill body contains a `` !`some command` `` block (or a fenced ` ```! ` block), is any hook event (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, or other) dispatched for that shell execution? Does the sandbox decision and `sandbox.excludedCommands` matching still apply on that path?

## Method

- Bundle analyzed: **2.1.258**, file `/Users/david/.local/share/claude/versions/2.1.258`.
- That path is a single **ELF 64-bit executable** (`file` output: `ELF 64-bit LSB executable, x86-64 ... not stripped`), 215473560 bytes — a bundled Bun/Node binary with the app's minified JS embedded as data, not a standalone `.js` text file.
- The shell's `grep` is shadowed by a function wrapper that execs `ugrep` through the `claude` binary itself (`type grep` showed a `_cc_bin=.../claude ... ARGV0=ugrep ...` wrapper). That wrapper chokes on some regex/complexity combos against 215MB of binary data (`ugrep: error: ... exceeds complexity limits`). All searches below used `/usr/bin/grep -a -o '...'` (or the `command grep -a` builtin bypass) directly, which reads the embedded text as binary-safe strings.
- Extracted matches were piped to `$TMPDIR/*.txt` (sandbox-writable) and read back with the Read tool, since `grep -o` with large context windows on this file is slow/borderline on the 2-minute default timeout (one query timed out at 90s+ and had to be re-run with a tighter window).
- Searches used: `grep -a -c "PreToolUse"` etc. to confirm presence; `grep -a -o '.\{0,N\}TERM.\{0,N\}'` to pull context around hits; targeted searches for `k1t(`, `$d(`, `IRe`, `lHe`, `oro(`, `nS(`, `excludedCommands`, `hook_event_name`, `allowed-tools`, `backtick`.

## Findings

### 1. What executes the `` !`...` `` / ` ```! ` block, and what it calls to run the shell command

The parser is function `k1t`:

```js
var W6r=/```!\s*\n?([\s\S]*?)\n?```/g,G6r=/(?<=^|\s)!`([^`]+)`/gm;
function k1t(e){let n=e.matchAll(W6r),r=e.includes("!`")?O7e(e).matchAll(G6r):[],o=[];for(let d of[...n,...r]){let p=d[1]?.trim();if(p)o.push({raw:d[0],command:p})}return o}
```

`O7e` first blanks out text already inside a real (non-`!`) backtick span so an inert code-span backtick can't be mistaken for a live marker:

```js
function O7e(e){return e.replace(/`[^`\n]+`/g,(n,r)=>{let o=e[r-1];return o==="!"||o==="`"?n:"`"+wi(" ",n.length-2)+"`"})}
```

`k1t` is called from `async function _8(e,n,r,o)`, which is the actual executor. Full body (assembled from two adjacent grep windows around the same match):

```js
async function _8(e,n,r,o){
  if(n.options.readOnlySkillLoad)return O5(e,"[shell command not executed: read-only skill load on the coordinator — delegate to a worker to run it]");
  let d=e;
  if(o==="bash"&&!cs())throw Error(`Skill ${r} requires bash (\`shell: bash\` in frontmatter) but Git Bash was not found. Install Git for Windows (...), or change the skill's frontmatter to \`shell: powershell\`.`);
  let p=o==="powershell"&&zC()?ZWn():cs()?jo:ZWn(),
      y=n.toolUseId??`${JWn()}${x5e}`;
  return await Promise.all(k1t(e).map(async({raw:k,command:v},x)=>{
    let F={...n,innerCall:!0,toolUseId:`${y}${Kpn}${x}`};
    try{
      let B=await $d(p,{command:v},n,fu({content:[]}),"");
      if(B.behavior!=="allow"){
        if(t(`Shell command permission check failed for command in ${r}: ${v}. Error: ${B.message}`),bo(F.session))
          throw t(`prompt shell permission denial: ${B.message||"Permission denied"}`,{level:"error"}),new tD(`Shell command permission check failed for pattern "${k}" (detail withheld on this connection)`);
        throw new tD(`Shell command permission check failed for pattern "${k}": ${B.message||"Permission denied"}`)
      }
      let{data:U}=await p.call({command:v},F),
          j=await Nfe(p,U,JWn(),kb(F.session),F.storageV5),
          G=typeof j.content==="string"?j.content:e2n(U.stdout,U.stderr);
      d=d.replace(k,()=>G)
    }catch(B){
      if(B instanceof tD)throw B;
      uVo(B,k,F.session)
    }
  })),d
}
```

`_8` is confirmed as the generic "run inline shell in a loaded prompt body" entry point by another call site that names its context: `await _8(o.content,{...n,getAppState:hj(n,d)},"security-review")` (the built-in `/security-review` command loads its body through the same function).

So: for each `{raw,command}` extracted by `k1t`, `_8` runs a permission check (`$d`) and, on `"allow"`, calls `p.call({command:v},F)` directly — `p` being the resolved shell tool object (`jo` for bash, `ZWn()`'s `PowerShellTool` on Windows). It then formats the result with `Nfe`/`e2n` and splices the output back into the prompt text at the `raw` marker's position (`d=d.replace(k,()=>G)`).

### 2. Same executor as the ordinary `Bash` tool, or separate/lower-level?

Same tool object's `.call()` method, called directly — not through the ordinary per-tool-call orchestration wrapper. Evidence:

- The tool object literal matching the `Bash` tool's shape (has a `.ws` branch for the background-monitor websocket path, and a `command` field) is:

  ```js
  async checkPermissions(e,o){if(e.ws){let n=_6n("Monitor websocket",o);if(n!==void 0)return n;return pe(e.ws)}return Eht({...e,command:e.command},o)},
  async call(e,o,n,u){if(e.ws)return iqe({...e,...W2n(e),ws:e.ws},oPe(o));return de(e.command,e,o,u)}
  ```

  `.call()` delegates straight to `de(e.command,e,o,u)`, the low-level shell runner (which itself calls `r8(...)` — see §4).

- `_8` calls `p.call({command:v},F)` on that same tool object (`p`), i.e. it reaches `de` → `r8` exactly the way the ordinary tool-use loop would when the *model* requests a `Bash` call. The command-running machinery (`de`/`r8`, sandboxing, output capture) is shared.
- What is **not** shared is the surrounding orchestration: the ordinary agent loop wraps every tool call in `async function*IRe(e,n,r,o,d,p,y,k)`, which itself iterates `lHe(...)` (the `PreToolUse` hook chain — see §3) before ever reaching `.call()`. `_8` contains no reference to `IRe`, `lHe`, or any hook-chain call; it goes `$d` (permission check only) → `p.call()` directly.

### 3. Is any hook event dispatched on the `_8`/`k1t` path?

**No `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, or `PostToolBatch` dispatch appears anywhere in `_8`, `k1t`, `O7e`, or their direct helpers `Nfe`/`W6e`/`e2n`.** None of the strings `"PreToolUse"`, `"PostToolUse"`, `"PostToolBatch"`, `"hook_event_name"`, or the hook-chain function names `lHe`/`IRe` occur inside the extracted text of these functions (checked by grepping the surrounding ~3000-byte windows on all sides of the `_8`/`k1t` definitions and call site — none matched).

The ordinary-tool call site that *does* dispatch `PreToolUse` is `lHe`, an async generator:

```js
async function*lHe(e,n,r,o,d,p,y=dd,k){
  let v=o.managedPass,
      x=!k?.managedHooksOnly&&v?.toolUseId===n&&t4.stableKey(v.input)===t4.stableKey(r)?v.pass:void 0,
      F=!k?.managedHooksOnly&&(x!==void 0||gd.hasModuleHandlers("PreToolUse"))&&Te(r)?r:void 0;
  if(F===void 0&&!k?.managedHooksOnly&&!Cw("PreToolUse",o.sessionHooksRegistry,lD(o,"PreToolUse",o.session.id)))return;
  t(`executePreToolHooks called for tool: ${e}`,{level:"verbose"});
  let B={...ba(o.session,ne(),d,o),hook_event_name:"PreToolUse",tool_name:e,tool_input:r,tool_use_id:n};
  ...
}
```

`lHe` is called from `async function*IRe(e,n,r,o,d,p,y,k)` — the standard wrapper around a tool invocation in the model-driven agent loop:

```js
async function*IRe(e,n,r,o,d,p,y,k){
  if(!Yq(n,e))return;
  ...
  for await(let G of lHe(n.name,o,r,e,fe(e).mode,e.abortController.signal))
    ... // builds hookPermissionResult / preventContinuation / permissionBehavior handling
}
```

`IRe` is what the model-driven tool-execution path runs before a tool's `.call()`/`checkPermissions()` is ever reached; `_8` (the bang-expansion executor) never calls `IRe` or `lHe`, and never constructs a `hook_event_name` payload. Its only gate is `$d(p,{command:v},n,fu({content:[]}),"")`, which is a **pure permission-rule check**, not a hook dispatcher (see next paragraph).

`$d` resolves to a permission-decision chain, not hooks:

```js
var $d=async(e,n,r,o,d,p)=>{if(p)return p;return Cwe(e,n,r,o,d,void 0)},
Cwe=async(e,n,r,o,d,p,y)=>{let k=await Bro(e,n,r,o,d,p,y);return k.behavior==="deny"?{...k,decideLocation:"pre-ask",...!1}:k},
Bro=async(e,n,r,o,d,p,y)=>{let k={...r,toolUseId:d},v=await jro(e,n,k,p);if(v.behavior==="allow"){...}if(v.behavior==="ask"){...} ...}
```

`$d → Cwe → Bro → jro` matches allow/deny/ask permission rules (settings.json permission rules, `--allowed-tools`/`--disallowed-tools`, mode such as `dontAsk`/`auto`, denial-tracking, etc.) — it is the same permission-check primitive used elsewhere for tool calls, but it is **not** the hook-chain (`lHe`) and does not construct or examine a `hook_event_name` payload anywhere in its traced body.

Post-execution, `_8` calls `Nfe(p,U,...)`:

```js
async function Nfe(n,e,r,i,a){return W6e(n.mapToolResultToToolResultBlockParam(e,r),n,i,a)}
async function W6e(n,e,r,i){return J(n,e.name,r,j6e(e.name,e.maxResultSizeChars,e.persistenceThresholdCeiling,e.skipAggregateToolResultBudget===!0),i)}
```

This only maps the raw stdout/stderr into a tool-result content block and applies result-size/persistence budgeting (`J`) — no `PostToolUse`/`PostToolUseFailure` string or hook-chain call appears in this path either.

**Conclusion for §3: no hook event is dispatched for a `` !`cmd` `` / ` ```! ` bang-expansion execution.** The ordinary `Bash` tool call site (`IRe`→`lHe`) is a distinct call path that `_8` does not go through.

### 4. Does the sandbox decision / `sandbox.excludedCommands` matching still apply?

**Yes — confirmed**, but for a different reason than "hooks still run": the sandbox decision lives inside the *shared low-level executor* (`de`/`r8`), which both call paths reach through the same tool object's `.call()` method (§2), not inside the hook-chain that bang-expansion skips.

The `Bash` tool's `.call()` delegates to `de`, whose body invokes the real shell runner `r8` with an explicit `shouldUseSandbox` flag computed from the command:

```js
async function de(e,o,n,u){
  let{description:g}=o,{timeout_ms:w,persistent:M}=W2n(o),{abortController:k,toolUseId:P,taskRegistry:p}=n,y=wde(n),r={},
      W=Njt({description:g,agentId:y,taskRef:r,killTask:()=>{if(!r.id)return!1;return qF(r.id,p),!0}}),
      _=await r8(e,k.signal,"bash",{session:n.session,preventCwdChanges:!0,shouldUseSandbox:nS({command:e}),sandboxAttributionId:P, ...})
  ...
}
```

`nS(e,n)` is the sandbox-applicability function, and it explicitly consults `excludedCommands` via `oro`:

```js
function nS(e,n){
  if($u()&&NO())return!0;
  if(!ut.isSandboxingEnabled())return!1;
  if((e.shellType??"bash")==="bash"&&D()==="windows"&&DN()===null)return!1;
  let r=n?.disableUnsandboxedCommands===!0||x5().unsandboxedCommandsDisabled||a.CLAUDE_CODE_EVAL_CONFINED;
  if(e.dangerouslyDisableSandbox&&!r&&ut.areUnsandboxedCommandsAllowed())return!1;
  if(!e.command)return Boolean(r);
  if(!r&&oro(e.command))return!1;
  return!0
}
function oro(e){
  let r=kn().sandbox?.excludedCommands??[];
  if(r.length===0)return!1;
  let o;try{o=Ap(e)}catch{o=[e]}
  for(let d of o){
    let y=[d.trim()],k=new Set(y),v=0;
    while(v<y.length){ /* expand prefixes/subcommands */ }
    for(let x of r){let F=ERe(x);for(let B of y)if(Nsn(F,B))return!0}
  }
  return!1
}
```

Because `_8` reaches this same `de`/`r8`/`nS`/`oro` chain via `p.call({command:v},F)` (identical to how the model-driven `Bash` tool call reaches it), the sandbox on/off decision and the `sandbox.excludedCommands` pattern matching apply identically to a `` !`cmd` `` bang-expansion command as to an ordinary model-issued `Bash` call. This is a property of the shared `.call()`/executor code, independent of whether the hook chain (`IRe`/`lHe`) ran first.

## Verdict

Hooks are **not** dispatched for a `` !`cmd` `` (or ` ```! ` fenced) bang-expansion block. The executor (`_8`, calling the extractor `k1t`) performs only a permission-rule check (`$d`→`Cwe`→`Bro`→`jro`) and then calls the shell tool's `.call()` method directly; it never touches the `PreToolUse`/`PostToolUse` hook-chain functions (`IRe`/`lHe`) that gate ordinary model-issued tool calls, and no `hook_event_name` payload is constructed anywhere on this path. The sandbox decision and `sandbox.excludedCommands` matching, however, **do** still apply — not because hooks fire, but because that gating (`nS`/`oro`) lives one layer lower, inside the shared low-level shell runner (`de`→`r8`) that both the ordinary tool-call path and the bang-expansion path invoke through the same tool object's `.call()` method. Confidence is high for §1–§3 (direct, unambiguous code excerpts with no competing candidate functions found for `k1t`/`_8`/`lHe`/`IRe`). Confidence is high-but-not-absolute for the `sandbox.excludedCommands` half of §4, and for identifying `jo`/`Bash` unambiguously — see Ambiguities.

## Ambiguities

- **Identifier reuse across the bundle.** Minified names like `jo`, `nS`, `oro` recur dozens of times in unrelated scopes elsewhere in this 215MB bundle (React internals, lodash, an unrelated file-watcher `nS`, an unrelated UI-state `oro`). I disambiguated by following call chains from unique anchor strings (`"PreToolUse"`, `excludedCommands`, `shouldUseSandbox:nS({command:e})`, the `_8`/`"security-review"` call site) rather than by name alone, but I could not independently prove `jo` inside `_8`'s scope is *byte-identical* to the `jo` used as the exported `Bash` tool constant elsewhere — I inferred it from the tool-shaped `call(e,o,n,u){if(e.ws)... return de(e.command,e,o,u)}` object matching the `.ws`/`.command` fields `_8` expects on `p`. This is strong circumstantial evidence, not a symbol-table proof (the binary is not stripped of function names but has no source map available here).
- **`$d`'s permission chain (`Cwe`/`Bro`/`jro`) was read for two of its ~4 nesting levels** (`Bro`'s body was captured to ~1200 bytes before truncation); I did not fully expand `jro` itself. It's possible `jro` internally consults something that *resembles* a hook (e.g. a "hook-suggested permission" plumbing point referenced elsewhere as `hookAskFloor`/`Lne()` in the `Bro` excerpt) but that machinery reads prior hook state passed in via context (`k.hookAskFloor`), not a live dispatch — no call resembling `lHe`/`IRe` appears inside the `Bro` text I captured. I'm treating this as settled but flag that `jro`'s full body wasn't quoted.
- One `grep -a -o` query (`var $d=async.\{0,2500\}` combined with `env LC_ALL=C`) failed/timed out due to `command`-wrapper interaction quirks in this shell before I isolated the working invocation (`/usr/bin/grep -a -o ... 1200-1500` char windows); no incorrect data was captured from the failed attempts, they simply returned empty/errored before any output was produced.
