<#
.SYNOPSIS
    Deletes the disk-space items that are safe to remove on a Windows machine.

.DESCRIPTION
    Removes these groups and prints how much each one held:
      1. Items in AppData\Local\Temp older than -TempDays days.
      2. VS Code per-folder state (workspaceStorage) not used in -WorkspaceDays days.
         This also removes the chat history kept for those folders.
      3. The folders passed in -LeftoverPaths (folders of programs confirmed as uninstalled).
      4. Kernel crash dumps in C:\Windows\LiveKernelReports.
      5. Windows Setup monitor logs in C:\Windows\Panther\monitor.
    Groups 4 and 5 need administrator rights, so the script restarts itself elevated (one UAC prompt).
    Files that are in use are skipped.

.PARAMETER LeftoverPaths
    Folders to delete, separated by semicolons. Pass only folders whose program is confirmed as
    not installed.

.PARAMETER DryRun
    Show what would be deleted and its size, without deleting anything. Runs without elevation,
    so groups 4 and 5 are reported as not checked.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Clear-DiskSpace.ps1 -DryRun

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Clear-DiskSpace.ps1 -LeftoverPaths "$HOME\.cursor;$env:APPDATA\Cursor"
#>
param(
    [int] $TempDays = 2,
    [int] $WorkspaceDays = 60,
    [string] $LeftoverPaths = '',
    [switch] $DryRun,
    # Not $env:TEMP: the user's TEMP variable can point somewhere else (such as C:\Temp),
    # while the folder that grows is AppData\Local\Temp.
    [string] $UserTemp = "$env:LOCALAPPDATA\Temp",
    # Passed in when the script restarts elevated, so that a separate admin account
    # still cleans this user's profile and not its own.
    [string] $UserAppData = $env:APPDATA
)

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $DryRun) {
    # Wraps a value in double quotes for the new process's command line. Backslashes just before
    # the closing quote are doubled: "C:\Some Dir\" would otherwise escape the quote, and the
    # arguments after it would be swallowed into this one.
    $quote = { param([string] $Value) '"' + ($Value -replace '(\\+)$', '$1$1') + '"' }
    $argList = "-NoProfile -ExecutionPolicy Bypass -NoExit -File $(& $quote $PSCommandPath) -TempDays $TempDays -WorkspaceDays $WorkspaceDays " +
        "-LeftoverPaths $(& $quote $LeftoverPaths) -UserTemp $(& $quote $UserTemp) -UserAppData $(& $quote $UserAppData)"
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    return
}

$results = New-Object System.Collections.Generic.List[object]

# Size in bytes of a file, or of every file under a folder; 0 when the path is gone.
function Get-ItemSize([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return [long] 0 }
    if (-not $item.PSIsContainer) { return [long] $item.Length }

    return [long] (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}

# Deletes the given paths (unless -DryRun) and records how many bytes went away.
function Remove-Group([string] $Name, [string[]] $Paths) {
    $before = [long] 0
    foreach ($p in $Paths) { $before += Get-ItemSize $p }

    $after = [long] 0
    if (-not $DryRun) {
        foreach ($p in $Paths) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        foreach ($p in $Paths) { $after += Get-ItemSize $p }
    }

    $results.Add([pscustomobject]@{ Group = $Name; Items = $Paths.Count; 'Size GB' = [math]::Round(($before - $after) / 1GB, 2) })
}

$drive = $env:SystemDrive.TrimEnd(':')
$freeBefore = (Get-PSDrive $drive).Free

# 1. Temp
$cutoff = (Get-Date).AddDays(-$TempDays)
$temp = @(Get-ChildItem -LiteralPath $UserTemp -Force -ErrorAction SilentlyContinue |
    Where-Object LastWriteTime -lt $cutoff | ForEach-Object FullName)
Remove-Group "AppData\Local\Temp (older than $TempDays days)" $temp

# 2. VS Code workspaceStorage
$cutoff = (Get-Date).AddDays(-$WorkspaceDays)
$workspaces = @(Get-ChildItem -LiteralPath "$UserAppData\Code\User\workspaceStorage" -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object LastWriteTime -lt $cutoff | ForEach-Object FullName)
Remove-Group "VS Code workspaceStorage (unused $WorkspaceDays days)" $workspaces

# 3. Folders of uninstalled programs
$leftovers = @($LeftoverPaths -split ';' | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' -and (Test-Path -LiteralPath $_) })
Remove-Group 'Folders of uninstalled programs' $leftovers

# 4 and 5. Windows folders (admin only)
if ($isAdmin) {
    $dumps = @(Get-ChildItem -LiteralPath "$env:SystemRoot\LiveKernelReports" -Recurse -File -Force -Filter '*.dmp' -ErrorAction SilentlyContinue |
        ForEach-Object FullName)
    Remove-Group 'Kernel crash dumps (LiveKernelReports)' $dumps

    $logs = @(Get-ChildItem -LiteralPath "$env:SystemRoot\Panther\monitor" -File -Force -Filter 'WinSetupMon_*.log' -ErrorAction SilentlyContinue |
        ForEach-Object FullName)
    Remove-Group 'Windows Setup monitor logs (Panther\monitor)' $logs
} else {
    $results.Add([pscustomobject]@{ Group = 'Crash dumps + Setup monitor logs'; Items = '-'; 'Size GB' = 'not checked (needs admin)' })
}

$results | Format-Table -AutoSize | Out-String -Width 200

$total = ($results | Where-Object { $_.'Size GB' -is [double] } | Measure-Object 'Size GB' -Sum).Sum
if ($DryRun) {
    "Dry run: nothing was deleted. Would remove {0:N2} GB of files." -f $total
} else {
    $freeAfter = (Get-PSDrive $drive).Free
    "Removed {0:N2} GB of files. Free space on {1}: went from {2:N1} GB to {3:N1} GB." -f $total, $env:SystemDrive, ($freeBefore / 1GB), ($freeAfter / 1GB)
    'Compressed files (such as the Setup monitor logs) take less on disk than their size, so the free-space change is the real gain.'
}
