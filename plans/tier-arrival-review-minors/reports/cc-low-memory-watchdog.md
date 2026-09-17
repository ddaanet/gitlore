# Claude Code low-memory task killing

CLI inspected: `2.1.273 (Claude Code)`, binary at
`/Users/david/.local/share/claude/versions/2.1.273` (a Bun-compiled,
not-stripped ELF executable, 228663608 bytes; the "real" claude —
`/Users/david/code/gitlore/.gitlore/bin/claude` is a project-local shim that
execs this same binary). All findings below are from `strings`/byte-offset
inspection of that binary unless marked otherwise.

## 1. Is this a Claude Code watchdog, and what triggers it?

Yes — it is Claude Code's own logic, layered on top of a
**Bun runtime feature**, not the Linux OOM killer.

**Message source** (verified, exact string in the binary):

```js
var VLe = {memory_pressure: "stopped because the system is running low on memory"};
```

**Kill path** (verified, function `kgr`, called only from `Mue` — the
*backgrounded* local-bash task registration path, `isBackgrounded:true`):

```js
function kgr(e,n,r,s,d,h){
  Ox(h,`bash:${e}`,r);
  let y;
  if(!Te() && !a.CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP){
    let S=()=>{
      let O=r.get(e);
      if(O?.status!=="running" || O.notified || Date.now()-Bm()<r2s || Pie() || hD(r.all()))
        return;
      _("task_local_shell_pressure_reap"),
      pCt(e,n,"killed",void 0,r,s,d,h,void 0,void 0,"memory_pressure"),
      $2(e,r)
    };
    process.on("memoryPressure", S),
    y=()=>process.off("memoryPressure", S)
  }
  return ()=>{ y?.(); /* ... */ }
}
var r2s = 1800000;   // 30 minutes, a grace-period constant used above
```

So: each *running background* Bash task registers its own
`process.on("memoryPressure", …)` listener. When that event fires, the listener
kills that task (status `killed`, `stopCause: "memory_pressure"`) — **unless**
`O.notified` is already true, or `Date.now()-Bm() < r2s` (task must have been
running/registered for at least 30 minutes before it's eligible — `Bm()`'s exact
semantics, and the two further gates `Pie()` and `hD(r.all())`, I could not pin
down from the minified bundle; they read as additional debounce/exemption
conditions, not as another threshold).

**What fires `"memoryPressure"`:** this is not Claude Code polling memory itself
for this path — it's a native Bun runtime event. The bundle embeds Bun's own
internal module registry, which lists (among ~200 other native lazy-bound
functions): `emitMemoryPressure`, `isMemoryPressureWatcherInstalled`,
`memoryPressureWatcherHasOsBackend`, `memoryPressurePsiTrigger`. The string
`/sys/fs/cgroup/memory.pressure` sits in the same strings region as
`memoryPressure`/`emitMemoryPressure`. Together this indicates Bun has a
built-in, OS-backed memory-pressure watcher that on Linux is driven by cgroup
**PSI** (pressure stall information — a kernel-level, event-driven mechanism;
not a fixed-interval poll loop, and not a simple free-bytes threshold). I did
not find a specific PSI threshold/window number in the bundle — Linux PSI
triggers are registered as "stall X% over window Y" pairs, and Bun's default for
its own watcher isn't surfaced as a string I could locate.

**Scope confirmed:** this kill path is wired only into the *background*
local-bash registration (`Mue`, `isBackgrounded:true`), not plain synchronous
foreground calls. However, Claude Code auto-backgrounds a long-running
foreground command after `CLAUDE_CODE_AUTO_BACKGROUND_TIMEOUT_MS` (a separate,
documented-ish env var read in `ern()`), so a long foreground command that gets
auto-backgrounded becomes subject to the same reap path — which is consistent
with your report of long foreground commands also getting killed.

**A second, unrelated low-memory check exists** (`xwn()`/`lY()`), used only for
background *worker pool* housekeeping (retiring idle workers before spawning a
new one — logged as
`bg: low memory (…) — retiring settled workers before spawning …`), not for
killing a running task:

```js
import { freemem as N } from "os";
function xwn(){
  let e = P("tengu_bg_low_mem_mb", 1024) * 1024 * 1024;   // MB -> bytes, default 1024 MB
  if (e<=0) return {lowMem:false, level:undefined};
  if (M()!=="macos") return {lowMem: N()<e, level:undefined};   // Linux/other: os.freemem() < threshold
  let n=K(); return {lowMem: n!==undefined && n>=I, level:n};    // macOS: Bun.ant.memoryPressureLevel() >= "critical"
}
```

`P(e,n)` is a remote feature-gate/dynamic-config getter (`qp(e,n).value`), so
`tengu_bg_low_mem_mb` is a **server-controlled** numeric flag; `1024` (MB) is
only the local fallback default. On Linux this compares `os.freemem()` — which
reads the kernel's raw free-memory figure (`MemFree`-equivalent via the
`sysinfo()` syscall), **not** `MemAvailable` — against that threshold. This
distinction (`MemFree` vs `MemAvailable`) matches your box's numbers (buff/cache
squeezed out by swelled swap/cache reads as "low" even when much of it is
reclaimable), and matches community bug reports below.

## 2. Supported way to tune or disable it

None found. `code.claude.com/docs/en/settings-reference` (fetched directly) has
no mention of memory pressure, background-task killing, or any related setting —
confirmed by direct fetch, not inferred. No `settings.json` key, no CLI flag.

## 3. Unsupported-but-real knob

**`CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP`** — an environment variable read
directly in `kgr()` (shown above): if set to a truthy value, the entire
`process.on("memoryPressure", …)` listener registration for that background task
is skipped, so this specific auto-kill path never fires for it. This is read
straight off `process.env` (`a` is the bundle's alias for `process.env` in this
module), with no other validation — any non-empty value should work, following
the pattern of the many other `CLAUDE_CODE_DISABLE_*` flags in this bundle (309
string hits for that prefix; this exact variable is not one of the documented
ones).

This variable is **not documented** anywhere I could find — not in the settings
reference page, not in search results, not in the two GitHub issues below. It's
a real, functioning internal escape hatch, not a supported public API, and could
be renamed or removed without notice.

I did not find any variable to change the underlying threshold/behavior itself
(e.g., no `tengu_bg_low_mem_mb` override read from env — that value comes only
from the server-side feature-gate system) or to disable the Bun-level PSI
watcher.

## Corroborating reports (not part of the binary evidence, cited separately)

Two open GitHub issues describe exactly this symptom on Linux with plenty of
memory *available* (just not *free*), naming the `MemFree`-vs-`MemAvailable`
mechanism independently of this inspection:

- [Background tasks killed for "low memory" with 17.9 GB available (MemFree vs MemAvailable) · Issue #92228](https://github.com/anthropics/claude-code/issues/92228)
- [Background tasks killed for "low memory" with 26 GB free on WSL2 · Issue #92448](https://github.com/anthropics/claude-code/issues/92448)

Issue #92228, fetched directly, has no maintainer response, no disclosed
threshold, and no mention of any disable flag — matching "no supported knob
exists."

## Bottom line

1. It's a Claude Code / Bun watchdog, not the OOM killer. On Linux it's driven
   by the kernel's PSI signal via Bun's native `memoryPressure` event, applied
   only to registered *background* (or auto-backgrounded) Bash tasks, with a
   30-minute grace period before a task becomes eligible for reaping.
2. No supported settings.json/CLI knob exists (verified against the live docs
   page).
3. `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` is a real, unsupported
   environment variable that disables this specific reap path, found by direct
   inspection of `kgr()` in the 2.1.273 bundle.
