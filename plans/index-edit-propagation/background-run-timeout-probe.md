Background runs have no duration cap in the bundle. The
`timeout`/`BASH_MAX_TIMEOUT_MS` value (600000 ms) only bounds how long a command
is awaited in the foreground before the harness auto-transitions it to a
background task (or, for `run_in_background: true`, is computed but never
applied as a wait — the task is registered and the tool returns immediately). No
code path was found that kills a background task because wall-clock time since
spawn exceeds a threshold. The three termination paths found are: the process
exits on its own; the current turn aborts and `turnAbortBackgrounds` is false,
in which case the harness calls `tn.kill()`; or the task is still running when
the agent gives its final response, in which case it is reaped
(`reapedAtFinalResponse`) — a fact the tool's own user-facing text states
explicitly ("it is terminated when you give your final response and no
notification can follow that"). At the 10-minute mark specifically, nothing in
the decompiled code singles out a background task for termination; 600000 ms is
a cap on the *foreground wait*, not on background task lifetime.

## Evidence

Minified source for the Bash tool's generator (`async function*cts(...)`), byte
offset 185711800–185716500, decoded from the Bun-embedded bundle:

```
let{command:ke,description:Pe,timeout:Re,run_in_background:Ie}=e,
Oe=Math.min(Re||xpe(),tZ(),r?.maxTimeoutMs??1/0);
if(Re&&Oe<Re)o?.({key:"timeout_clamped",requestedMs:Re,appliedMs:Oe});
...
xt=Dl()||r?.background==="forbidden",
dn=!xt&&ots(ke),
cn=!xt,
Nn=a1t({requestedTimeoutMs:Oe,isMainAgent:x===!0,canAutoBackground:dn}),
tn=await y5(ke,d.signal,"bash",{timeout:Nn,owningAgentId:F,caller:B,
  turnAbortBackgrounds:cn,onProgress(...){...},session:E,...,
  shouldAutoBackground:dn,...})
...
if(tn.onTimeout&&dn) tn.onTimeout((hn)=>{ct=Nn,
  Tn("tengu_bash_command_timeout_backgrounded",hn)});
if(Ie===!0&&!xt){
  if(tn.status==="completed"){let vt=await gn;if(vt.preSpawnError)return vt}
  let hn=await Qt();
  return i("tengu_bash_command_explicitly_backgrounded",{command_type:Ppe(ke)}),
  {stdout:"",stderr:"",code:0,interrupted:!1,backgroundTaskId:hn}
}
...
if(!on&&Bn()){
  if(on=!0,cn){
    if(Tn("tengu_bash_command_turn_abort_backgrounded"),ut)
      return{...,backgroundTaskId:ut,backgroundedByTurnAbort:!0,timedOutAfterMs:ct};
    continue
  }
  if(tn.status==="running")tn.kill();
  continue
}
```

Reading this: `Oe` is the clamped requested-vs-default-vs-max timeout (this is
the existing foreground 120000/600000 ms cap). `Nn` is `Oe` passed through
`a1t`, which is the value actually handed to the process spawner `y5` as
`timeout`. `Nn` is computed and passed identically whether or not
`run_in_background` was set — the `Ie===!0` (`run_in_background: true`) branch
runs *after* the spawn call and only decides whether to wait for the result or
return the `backgroundTaskId` immediately; it does not swap in a different
timeout. The `tn.onTimeout` callback — which fires when `Nn` elapses — only
backgrounds the task (`tengu_bash_command_timeout_backgrounded`) and is gated on
`dn` (`canAutoBackground`); it never kills. The only `tn.kill()` call in this
function is on turn-abort when `turnAbortBackgrounds` (`cn`) is false —
unrelated to elapsed duration.

`a1t`, full body, byte offset 183403562:

```
function a1t({requestedTimeoutMs:e,isMainAgent:t,canAutoBackground:r,env:o=process.env}){
  if(!t||!r)return e;
  let d=o.CLAUDE_CODE_AUTO_BACKGROUND_TIMEOUT_MS;
  if(!d)return e;
  let f=tl(d);
  if(isNaN(f)||f<=0)return e;
  return Math.min(e,Math.max(f,rco))
}
```

This is the only place `CLAUDE_CODE_AUTO_BACKGROUND_TIMEOUT_MS` is read. It can
only lower or raise (bounded by a floor `rco`) the *auto-background trigger*
threshold for the main agent — it has no effect on already-backgrounded tasks
and does not represent a kill timer.

String pool entries, byte offset 95677800–95679400 (UTF-16, decoded), confirm
the same model from the tool-facing copy:

```
Command did not complete within its {N}s timeout and was moved to the background (ID:
{id}). Output is being written to: {path}

Command running in background with ID: {id}

If it exits while you are still working you will be notified, but it is terminated when
you give your final response and no notification can follow that — so do not end your
turn to wait for it; if you need its result, wait for it before giving your final
response.

You will be notified when it completes.
To check interim output, use Read on that file path.
```

and object field names `backgroundedByUser`, `backgroundedByTurnAbort`,
`backgroundedToDeliverMessage`, `timedOutAfterMs`, `reapedAtFinalResponse` — an
enumerated set of reasons a background task's life ends, none of which is
"duration cap reached".

Result-formatting code, byte offset 185704800, shows `reapedAtFinalResponse`
consumed as a boolean flag `v` fed into the tool-result formatter (`_jt(...)`,
`l1t(v===!0)`), corroborating that reaping at final response is a real, coded
outcome rather than only descriptive text.

Live confirmation during this probe: two of my own `grep -a` calls against the
215 MB binary (with a pathological `.\{300\}` greedy pattern) ran past the
foreground default timeout and were auto-backgrounded by the harness itself
mid-probe, with task-completion notifications arriving later once the grep
finished — the exact foreground-timeout-to-background transition described
above, observed operationally rather than just in decompiled code.

## Observation

The main session confirms the verdict operationally: a `just precommit` run
launched with `run_in_background: true` (about nine minutes: 14, 770 and 72 bats
cases) survived the agent ending its turn, completed, and recorded the
`precommit` sentinel. The "terminated when you give your final response" text
therefore does not govern a main-session task; the harness's own Bash tool
description says such a task runs across turns, and the reaping text is
consistent with a subagent, whose final response ends its context.

## Method

```
BIN=/Users/david/.local/share/claude/versions/2.1.261
OUT=/Users/david/code/gitlore/.tmp-bg-probe
mkdir -p "$OUT"
git check-ignore -q .tmp-bg-probe || echo NOT-IGNORED   # confirmed not ignored; used it anyway, left in place for inspection

for term in "600000" "120000" "BASH_MAX_TIMEOUT_MS" "BASH_DEFAULT_TIMEOUT_MS" \
  "run_in_background" "runInBackground" "backgroundTask" \
  "Command running in background" "Command timed out" "timed out after"; do
  grep -a -o -b ".\{0,0\}$term" "$BIN"
done

# extract raw byte windows around hits with python (streaming, no full-file load)
python3 -c "
off=95677800; length=2200
with open('$BIN','rb') as f:
    f.seek(off); data=f.read(length)
open('$OUT/raw_backgroundTask_95678081.bin','wb').write(data)
"
od -A d -t x1z "$OUT/raw_backgroundTask_95678081.bin"

# same pattern repeated for offsets 95687400 (BASH_DEFAULT/MAX_TIMEOUT_MS,
# CLAUDE_CODE_AUTO_BACKGROUND_TIMEOUT_MS), 185711800/185713300 (cts() source),
# 185704800 (reapedAtFinalResponse usage)

grep -a -o -b "CLAUDE_CODE_AUTO_BACKGROUND_TIMEOUT_MS" "$BIN"
grep -a -o -b "canAutoBackground" "$BIN"
grep -a -o -b "reapedAtFinalResponse" "$BIN"
grep -a -o -b "function a1t([^)]*){[^}]\{0,300\}" "$BIN"
grep -a -o -b "function tZ([^)]*){[^}]\{0,150\}" "$BIN"
grep -a -o -b "function xpe([^)]*){[^}]\{0,150\}" "$BIN"
```

All commands run read-only against the installed binary at
`/Users/david/.local/share/claude/versions/2.1.261`; the binary itself was never
executed.
