<#
.SYNOPSIS
    Measures what fills the system drive of a Windows machine. Reads only; deletes nothing.

.DESCRIPTION
    Prints seven sections:
      1. Free and total space on the system drive, and whether this shell is elevated.
      2. TEMP and TMP as the user's registry sets them, compared with %LOCALAPPDATA%\Temp.
      3. The largest folders in the user profile, AppData\Local and AppData\Roaming. "GB" is the
         size the files report; "On disk GB" is the space they really take (cloud placeholders,
         sparse files and compressed files take less).
      4. Known locations (caches, crash dumps, setup logs, model files) with a category and a note.
      5. Large profile folders whose name matches no installed program (candidates for leftovers).
      6. Docker disk use and the virtual disk (.vhdx) files of Docker and every WSL distribution.
      7. Repeating Temp growth: Visual Studio Installer copies, .node files, and the update tasks.
    A folder this shell cannot fully read is marked "partial" or "not checked", never reported as empty.

.PARAMETER Top
    How many of the largest folders to list for each parent folder. Default 12.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Measure-DiskUsage.ps1
#>
param(
    [int] $Top = 12
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not ('DiskCleanup.Native' -as [type])) {
    Add-Type -Namespace DiskCleanup -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);
'@
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Space a file really takes on disk; falls back to its reported length when Windows cannot say.
function Get-AllocatedBytes([System.IO.FileInfo] $File) {
    $high = [uint32] 0
    $low = [DiskCleanup.Native]::GetCompressedFileSizeW($File.FullName, [ref] $high)
    if ($low -eq [uint32]::MaxValue -and [Runtime.InteropServices.Marshal]::GetLastWin32Error() -ne 0) { return [long] $File.Length }

    return [long] (([uint64] $high -shl 32) + $low)
}

# Sections 3, 4 and 5 often measure the same folder; each path is walked once.
$sizeCache = @{}

# Reported size, on-disk size and readability of a file or folder; $null when the path does not exist.
function Measure-Path([string] $Path) {
    if ($sizeCache.ContainsKey($Path)) { return $sizeCache[$Path] }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }

    $errs = @()
    $files = if ($item.PSIsContainer) {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable errs
    } else {
        @($item)
    }

    $logical = [long] 0
    $onDisk = [long] 0
    foreach ($f in $files) {
        $logical += $f.Length
        $onDisk += Get-AllocatedBytes $f
    }

    $result = [pscustomobject]@{
        Logical = $logical
        OnDisk  = $onDisk
        Partial = ($errs.Count -gt 0)
    }
    $sizeCache[$Path] = $result

    return $result
}

# Formats bytes as GB with two decimals.
function Format-GB([long] $Bytes) { '{0:N2}' -f ($Bytes / 1GB) }

# Lists the largest children of a folder, skipping junctions and symbolic links (they point elsewhere).
function Show-LargestChildren([string] $Parent, [string[]] $Exclude = @()) {
    "--- $Parent"
    $rows = foreach ($child in (Get-ChildItem -LiteralPath $Parent -Force -ErrorAction SilentlyContinue)) {
        if ($child.LinkType -in 'Junction', 'SymbolicLink') { continue }
        if ($Exclude -contains $child.Name) { continue }

        $m = Measure-Path $child.FullName
        if ($null -eq $m) { continue }

        [pscustomobject]@{
            GB           = [math]::Round($m.Logical / 1GB, 2)
            'On disk GB' = [math]::Round($m.OnDisk / 1GB, 2)
            Name         = $child.Name + $(if ($m.Partial) { '  (partial: some items unreadable)' } else { '' })
            Modified     = $child.LastWriteTime.ToString('yyyy-MM-dd')
        }
    }
    $rows | Sort-Object GB -Descending | Select-Object -First $Top | Format-Table -AutoSize | Out-String -Width 220
}

$userTempVar = (Get-ItemProperty HKCU:\Environment -ErrorAction SilentlyContinue).TEMP
$userTmpVar = (Get-ItemProperty HKCU:\Environment -ErrorAction SilentlyContinue).TMP
$localTemp = Join-Path $env:LOCALAPPDATA 'Temp'

# 1. Drive
'=== 1. System drive'
$drive = Get-PSDrive $env:SystemDrive.TrimEnd(':')
'{0} free {1} GB of {2} GB. Elevated shell: {3}' -f $env:SystemDrive, (Format-GB $drive.Free), (Format-GB ($drive.Free + $drive.Used)), $isAdmin
''

# 2. Temp variables
'=== 2. Temp folders'
"User TEMP (registry): $userTempVar"
"User TMP  (registry): $userTmpVar"
"This shell's TEMP:    $env:TEMP"
"AppData\Local\Temp:   $localTemp"
foreach ($v in @($userTempVar, $userTmpVar)) {
    if ([string]::IsNullOrEmpty($v)) { continue }
    $expanded = [Environment]::ExpandEnvironmentVariables($v)
    if ($expanded.TrimEnd('\') -ne $localTemp.TrimEnd('\')) {
        "NOTE: $expanded is not AppData\Local\Temp. Measure and clean both by full path; never by `$env:TEMP alone."
    }
}
''

# 3. Largest folders
'=== 3. Largest folders'
Show-LargestChildren $env:USERPROFILE -Exclude @('AppData')
Show-LargestChildren $env:LOCALAPPDATA
Show-LargestChildren $env:APPDATA

# 4. Known locations
'=== 4. Known locations'
$known = @(
    @{ Path = $localTemp; Cat = 'Safe'; Note = 'Temporary files; items in use are skipped' }
    @{ Path = "$env:LOCALAPPDATA\CrashDumps"; Cat = 'Safe'; Note = 'Application crash dumps' }
    @{ Path = "$env:APPDATA\Code\User\workspaceStorage"; Cat = 'Safe (old)'; Note = 'VS Code per-folder state incl. chat history; delete folders unused 60+ days' }
    @{ Path = "$env:SystemRoot\LiveKernelReports"; Cat = 'Safe (admin)'; Note = 'Kernel crash dumps' }
    @{ Path = "$env:SystemRoot\Panther\monitor"; Cat = 'Safe (admin)'; Note = 'Windows Setup monitor logs (WinSetupMon_*.log)' }
    @{ Path = "$env:USERPROFILE\.nuget\packages"; Cat = 'Cache'; Note = 'dotnet nuget locals all --clear' }
    @{ Path = "$env:LOCALAPPDATA\NuGet\v3-cache"; Cat = 'Cache'; Note = 'dotnet nuget locals all --clear' }
    @{ Path = "$env:LOCALAPPDATA\pnpm\store"; Cat = 'Cache'; Note = 'One subfolder per pnpm version; prune only reaches (pnpm store path). Measure each' }
    @{ Path = "$env:LOCALAPPDATA\pnpm-cache"; Cat = 'Cache'; Note = 'pnpm metadata cache' }
    @{ Path = "$env:LOCALAPPDATA\npm-cache"; Cat = 'Cache'; Note = 'npm cache clean --force clears _cacache only; _npx is separate' }
    @{ Path = "$env:LOCALAPPDATA\Yarn\Cache"; Cat = 'Cache'; Note = 'yarn cache clean' }
    @{ Path = "$env:LOCALAPPDATA\pip\cache"; Cat = 'Cache'; Note = 'pip cache purge' }
    @{ Path = "$env:USERPROFILE\.gradle\caches"; Cat = 'Cache'; Note = 'Gradle cache; downloads again' }
    @{ Path = "$env:USERPROFILE\.m2\repository"; Cat = 'Cache'; Note = 'Maven cache; downloads again' }
    @{ Path = "$env:LOCALAPPDATA\ms-playwright"; Cat = 'Cache'; Note = 'Playwright browsers; keep if a project runs Playwright tests' }
    @{ Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\OptGuideOnDeviceModel"; Cat = 'Cache'; Note = 'Chrome on-device AI model; set policy GenAILocalFoundationalModelSettings=1 first or it downloads again' }
    @{ Path = "$env:LOCALAPPDATA\Temp\DockerDesktop"; Cat = 'Safe'; Note = 'Old Docker Desktop update files; delete with Docker Desktop closed' }
    @{ Path = "$env:USERPROFILE\.cache\huggingface"; Cat = 'Your call'; Note = 'Downloaded AI models' }
    @{ Path = "$env:USERPROFILE\.cache\whisper"; Cat = 'Your call'; Note = 'Downloaded speech models' }
    @{ Path = "$env:LOCALAPPDATA\Ollama"; Cat = 'Your call'; Note = 'Ollama app data; leftover if Ollama is not installed' }
    @{ Path = "$env:USERPROFILE\.ollama"; Cat = 'Your call'; Note = 'Ollama models' }
    @{ Path = "$env:APPDATA\Claude\vm_bundles"; Cat = 'Your call'; Note = 'Claude desktop local agent VM; downloads again if needed' }
    @{ Path = "$env:USERPROFILE\Downloads"; Cat = 'Your call'; Note = 'Personal files' }
    @{ Path = "$env:USERPROFILE\CrossDevice"; Cat = 'Keep'; Note = 'Phone files shown in Explorer; placeholders, compare On disk GB' }
    @{ Path = "$env:SystemRoot\Installer"; Cat = 'Keep'; Note = 'Needed to repair and uninstall programs' }
)
$rows = foreach ($k in $known) {
    if ($k.Cat -eq 'Safe (admin)' -and -not $isAdmin) {
        [pscustomobject]@{ Category = $k.Cat; GB = 'not checked (needs admin)'; 'On disk GB' = ''; Path = $k.Path; Note = $k.Note }
        continue
    }

    $m = Measure-Path $k.Path
    if ($null -eq $m) { continue }

    [pscustomobject]@{
        Category     = $k.Cat
        GB           = (Format-GB $m.Logical) + $(if ($m.Partial) { ' (partial)' } else { '' })
        'On disk GB' = Format-GB $m.OnDisk
        Path         = $k.Path
        Note         = $k.Note
    }
}
$rows | Format-Table -AutoSize | Out-String -Width 300
$knownPaths = @($known | ForEach-Object { $_.Path })

# 5. Folders no installed program seems to own
'=== 5. Large folders with no matching installed program (confirm by hand before calling them leftovers)'
$normalize = { param([string] $Name) ($Name -replace '[^a-zA-Z0-9]', '').ToLowerInvariant() }
$installed = @(@(
    Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        ForEach-Object DisplayName
    Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object Name
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object ProcessName
) | Where-Object { -not [string]::IsNullOrEmpty($_) } | ForEach-Object { & $normalize $_ })

# Editor extensions have no uninstall entry and often no process, but keep data in folders such
# as ~\.sonarlint. Count an editor's extensions only while that editor is installed: the
# extensions folder of an uninstalled editor is part of its leftovers. The value is the editor's
# name as its uninstall entry shows it, normalized ("Microsoft Visual Studio Code" has no "vscode").
$editors = @{ '.vscode' = 'visualstudiocode'; '.cursor' = 'cursor'; '.windsurf' = 'windsurf'; '.antigravity' = 'antigravity' }
$installed += foreach ($folder in $editors.Keys) {
    $editor = $editors[$folder]
    if (-not ($installed | Where-Object { $_.Contains($editor) } | Select-Object -First 1)) { continue }

    Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE "$folder\extensions") -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object { & $normalize $_.Name }
}

# Shared Windows and tool folders that never match a program name.
$ignore = @('temp', 'packages', 'programs', 'microsoft', 'crashdumps', 'cache', 'local', 'config', 'd3dscache', 'appdata', 'downloads', 'documents', 'desktop', 'pictures', 'videos', 'music', 'onedrive', 'crossdevice', 'npmcache', 'pnpmcache', 'pnpm', 'nuget', 'npm')
$candidates = @(
    Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name.StartsWith('.') }
    Get-ChildItem -LiteralPath $env:LOCALAPPDATA -Directory -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $env:APPDATA -Directory -Force -ErrorAction SilentlyContinue
) | Where-Object { $_.LinkType -notin 'Junction', 'SymbolicLink' -and $knownPaths -notcontains $_.FullName }
$rows = foreach ($c in $candidates) {
    $key = ($c.Name -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    if ($key.Length -lt 3 -or $ignore -contains $key) { continue }
    if ($installed | Where-Object { $_.Contains($key) } | Select-Object -First 1) { continue }

    $m = Measure-Path $c.FullName
    if ($null -eq $m -or $m.OnDisk -lt 500MB) { continue }

    [pscustomobject]@{ 'On disk GB' = [math]::Round($m.OnDisk / 1GB, 2); Path = $c.FullName; Modified = $c.LastWriteTime.ToString('yyyy-MM-dd') }
}
if ($null -eq $rows) { 'None over 0.5 GB.' } else { $rows | Sort-Object 'On disk GB' -Descending | Format-Table -AutoSize | Out-String -Width 220 }

# 6. Docker and WSL virtual disks
'=== 6. Docker and WSL virtual disks'
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $df = docker system df 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { $df } else { 'docker system df: not checked (Docker is not running).' }
} else {
    'Docker CLI not installed.'
}
$vhdxDirs = @("$env:LOCALAPPDATA\Docker\wsl") + @(
    Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-ItemProperty $_.PSPath).BasePath } | Where-Object { $_ } | ForEach-Object { $_ -replace '^\\\\\?\\', '' }
)
# Docker's own WSL distribution lives under Docker\wsl too, so the same file can be found twice.
$vhdxFiles = foreach ($d in ($vhdxDirs | Select-Object -Unique)) {
    Get-ChildItem -LiteralPath $d -Recurse -File -Force -Filter '*.vhdx' -ErrorAction SilentlyContinue
}
$rows = $vhdxFiles | Sort-Object FullName -Unique | ForEach-Object {
    [pscustomobject]@{ GB = Format-GB $_.Length; 'On disk GB' = Format-GB (Get-AllocatedBytes $_); Path = $_.FullName; Modified = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
}
if ($null -eq $rows) { 'No .vhdx files found.' } else { $rows | Format-Table -AutoSize | Out-String -Width 250 }

# 7. Repeating Temp growth
'=== 7. Repeating Temp growth'
$entries = Get-ChildItem -LiteralPath $localTemp -Force -ErrorAction SilentlyContinue
$vsCopies = @($entries | Where-Object { $_.PSIsContainer -and $_.Name -match '^[a-z0-9]{8}\.[a-z0-9]{3}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'setup.exe')) })
$vsBytes = [long] 0
foreach ($v in $vsCopies) { $vsBytes += (Measure-Path $v.FullName).Logical }
$nodeFiles = @($entries | Where-Object { $_.Extension -eq '.node' })
"Visual Studio Installer copies in Temp: {0} folders, {1} GB" -f $vsCopies.Count, (Format-GB $vsBytes)
"Loose .node files in Temp: {0} files, {1} GB" -f $nodeFiles.Count, (Format-GB ([long] ($nodeFiles | Measure-Object Length -Sum).Sum))
Get-ScheduledTask -TaskPath '\Microsoft\VisualStudio\*' -ErrorAction SilentlyContinue |
    Select-Object TaskPath, TaskName, State | Format-Table -AutoSize | Out-String -Width 220
