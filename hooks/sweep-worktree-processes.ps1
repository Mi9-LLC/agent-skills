<#
.SYNOPSIS
    Kill build and test processes left running inside an execute-change run's git worktree.

.DESCRIPTION
    Called by hooks/execute-change-watch.py once the last subagent of an execute-change run
    has stopped. A step-6 implementer that leaves a test watcher or a dev server alive keeps
    file handles open inside the run's worktree, and the next step's dependency install or
    the close-out `git worktree remove` then fails with nothing on screen to explain it.

    A process is killed only when ALL THREE of these hold:
      1. its command line names the worktree, OR it descends from the current claude process;
      2. it started at or after -Since (the run start), so nothing predating the run is touched;
      3. its executable name is in the allowlist below (build and test tools only).

    KNOWN BLIND SPOT: a process started as `node script.js` with its working directory set to
    the worktree shows no worktree path anywhere on its command line, so rule 1 catches it
    only through the parent chain. Win32_Process has no working-directory field, so there is
    no cheap way to close that gap -- reading each process's PEB would mean native interop.

.PARAMETER Worktree
    Path of the run's git worktree. Compared case-insensitively, with / and \ treated alike.

.PARAMETER Since
    ISO-8601 timestamp of the run start. Processes older than this are never touched.

.PARAMETER WhatIf
    List what would be killed and kill nothing.
#>
param(
    [Parameter(Mandatory = $true)][string]$Worktree,
    [Parameter(Mandatory = $true)][string]$Since,
    [switch]$WhatIf
)

# Windows only. On PowerShell 7 for macOS/Linux $IsWindows is $false; on Windows PowerShell
# 5.1 the variable does not exist at all, which reads as $null and correctly falls through.
if ($IsWindows -eq $false) {
    Write-Output "sweep skipped: not Windows -- a non-Windows sweep is out of scope"
    exit 0
}

# Build and test tooling only. Anything not on this list is never a candidate, whatever its
# command line or parent says.
#
# NO SHELLS HERE -- not bash, sh, or pwsh. Every leftover this sweep exists for is a node or
# dotnet process, while a shell is far more often the lead's own tooling: the stall watcher it
# arms with a background Bash call right after launching a subagent, a backgrounded gate run, a
# persistent Bash tool shell. All three are descendants of claude and all three sit inside the
# batch window, so a shell on this list means killing the lead's watcher at the end of every
# batch. Dropping them costs nothing: a leftover dev server or test watcher IS the node
# process, and killing it lets the orphaned shell exit on its own. Killing the shell was never
# what released the file handles.
$allowed = @(
    'node', 'npm', 'npx', 'pnpm', 'yarn', 'bun', 'biome', 'eslint', 'tsc',
    'vitest', 'jest', 'esbuild', 'dotnet'
)

function Get-BaseName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return '' }
    return ($name -replace '\.(exe|cmd|bat|com)$', '').ToLowerInvariant()
}

function Get-ComparablePath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return '' }
    # String.Replace, not -replace: the latter reads its first argument as a regex, where a
    # lone backslash is a syntax error.
    return $path.Replace('\', '/').ToLowerInvariant()
}

try {
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor `
              [System.Globalization.DateTimeStyles]::AssumeUniversal
    $sinceUtc = [datetime]::Parse($Since, [cultureinfo]::InvariantCulture, $styles)
}
catch {
    Write-Output "sweep skipped: cannot parse -Since '$Since'"
    exit 0
}

try {
    $procs = @(Get-CimInstance Win32_Process -ErrorAction Stop)
}
catch {
    Write-Output "sweep skipped: Win32_Process query failed"
    exit 0
}

$needle = Get-ComparablePath $Worktree

$byPid = @{}
foreach ($p in $procs) { $byPid[[int]$p.ProcessId] = $p }

# Walk up from this shell: every ancestor is protected, and the nearest one named claude is
# the root of the subtree the parent-chain rule uses. Killing an ancestor would kill the
# session that started the sweep, so the protected set is checked before anything else.
$protected = New-Object 'System.Collections.Generic.HashSet[int]'
$claudePid = 0
$cursor = $PID
$hops = 0
while ($cursor -gt 0 -and $hops -lt 64) {
    $hops++
    [void]$protected.Add($cursor)
    $entry = $byPid[$cursor]
    if ($null -eq $entry) { break }
    if ($claudePid -eq 0 -and (Get-BaseName $entry.Name) -eq 'claude') {
        $claudePid = [int]$entry.ProcessId
    }
    $cursor = [int]$entry.ParentProcessId
}

# Children by parent pid. Windows reuses pids, so a dead parent's pid can be inherited by an
# unrelated process and make a stranger look like a descendant -- the -Since and allowlist
# gates are what keep that from mattering. The HashSet guard also stops a reuse cycle from
# looping forever.
$children = @{}
foreach ($p in $procs) {
    $parentPid = [int]$p.ParentProcessId
    if (-not $children.ContainsKey($parentPid)) {
        $children[$parentPid] = New-Object System.Collections.ArrayList
    }
    [void]$children[$parentPid].Add([int]$p.ProcessId)
}

$descendants = New-Object 'System.Collections.Generic.HashSet[int]'
if ($claudePid -gt 0) {
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($claudePid)
    while ($queue.Count -gt 0) {
        $current = [int]$queue.Dequeue()
        if ($children.ContainsKey($current)) {
            foreach ($child in $children[$current]) {
                if ($descendants.Add($child)) { $queue.Enqueue($child) }
            }
        }
    }
}

foreach ($p in $procs) {
    $procId = [int]$p.ProcessId
    if ($procId -le 4) { continue }                     # idle and system
    if ($protected.Contains($procId)) { continue }      # this shell and its ancestors

    $base = Get-BaseName $p.Name
    if ($allowed -notcontains $base) { continue }

    $created = $null
    try { $created = $p.CreationDate } catch { $created = $null }
    # Get-CimInstance hands back a real DateTime, so there is no WMI string to parse -- but a
    # process can still report none, and without a start time it cannot be tied to this run.
    if ($null -eq $created) { continue }
    if ($created.ToUniversalTime() -lt $sinceUtc) { continue }

    $commandLine = Get-ComparablePath ([string]$p.CommandLine)
    $byPath = ($needle -ne '' -and $commandLine.Contains($needle))
    $byTree = $descendants.Contains($procId)
    if (-not ($byPath -or $byTree)) { continue }

    $reason = if ($byPath) { 'worktree path on command line' } else { 'descendant of claude' }

    if ($WhatIf) {
        Write-Output "would kill pid $procId ($base) -- $reason"
        continue
    }

    # /T already killed some of these as part of an earlier tree, so re-check before trying.
    if ($null -eq (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { continue }

    & taskkill /PID $procId /T /F 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "killed pid $procId ($base) -- $reason"
    }
    else {
        Write-Output "kill failed for pid $procId ($base) -- $reason"
    }
}

exit 0
