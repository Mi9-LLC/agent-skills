# Locations and procedures

What each common space user is, whether it can go, and the exact steps. Read the section for a
location before you recommend anything about it. Every command here is for the user to run.

## Contents

- [Temp folders](#temp-folders)
- [VS Code workspaceStorage](#vs-code-workspacestorage)
- [Folders of uninstalled programs](#folders-of-uninstalled-programs)
- [Windows crash dumps and setup logs](#windows-crash-dumps-and-setup-logs)
- [Package caches](#package-caches)
- [Docker and WSL virtual disks](#docker-and-wsl-virtual-disks)
- [Visual Studio Installer copies in Temp](#visual-studio-installer-copies-in-temp)
- [A second database server version](#a-second-database-server-version)
- [Chrome on-device AI model](#chrome-on-device-ai-model)
- [Folders that report more than they use](#folders-that-report-more-than-they-use)
- [Never delete](#never-delete)

## Temp folders

There can be two: `%LOCALAPPDATA%\Temp`, which most programs use and which grows, and whatever
the user's `TEMP` variable names (`HKCU\Environment` → `TEMP`), which can be a different folder
such as `C:\Temp`. **Always name the folder by full path.** A command written as `$env:TEMP`
cleans whichever folder the variable points to, and the agent's own shell may have a different
`TEMP` than the user's shell, so a dry run in the agent's shell can measure a third folder.

Everything in a Temp folder is safe to delete; files a running program holds open fail and are
skipped. Right after a restart is the best time. A folder modified recently is skipped by an
age filter even when its contents are old (`Temp\DockerDesktop` is an example), so "older than N
days" can leave several GB behind. Deleting everything:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Temp" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
```

## VS Code workspaceStorage

`%APPDATA%\Code\User\workspaceStorage\<hash>` holds VS Code's saved state for one opened folder:
open tabs, extension state, and **the chat history for that folder**. Each hash folder has a
`workspace.json` naming the folder it belongs to. Folders not modified in 60 days are safe to
delete if the user does not need their old chat history. Close VS Code first: a delete while it
runs can leave folders behind, and a re-measure then shows fewer removed than expected.

```powershell
Get-ChildItem "$env:APPDATA\Code\User\workspaceStorage" -Directory | Where-Object LastWriteTime -lt (Get-Date).AddDays(-60) | Remove-Item -Recurse -Force
```

The same layout exists for forks of VS Code (Cursor, Windsurf and others) under their own
`%APPDATA%\<name>\User\workspaceStorage`.

## Folders of uninstalled programs

Before calling a folder a leftover, confirm all four:

1. No entry in the installed-programs list (`HKLM` and `HKCU` `...\CurrentVersion\Uninstall\*`,
   and `HKLM\Software\WOW6432Node\...` for 32-bit programs) and no Store package
   (`Get-AppxPackage *name*`).
2. No running process with that name.
3. No environment variable or PATH entry pointing into it.
4. No extension of an installed editor uses it. Editor extensions have no uninstall entry and
   often no process, but keep data in folders such as `~\.sonarlint`. List the extension folders
   (`Get-ChildItem "$HOME\.vscode\extensions", "$HOME\.cursor\extensions" -Directory`, one path
   per installed editor) and look for the folder's name in them.

Editors built on VS Code leave three to four folders each: `~\.<name>` (extensions),
`%APPDATA%\<Name>` (settings, caches, workspace state), sometimes `%LOCALAPPDATA%\Programs\<name>`
and `%LOCALAPPDATA%\<name>-updater`. Local model runners leave `%LOCALAPPDATA%\<Name>` and
`~\.<name>` (models). Measure each one; some are empty.

## Windows crash dumps and setup logs

- `C:\Windows\LiveKernelReports` — kernel crash dumps (`*.dmp`). Unreadable without admin, so a
  non-elevated measurement shows nothing: report it as **not checked**, never as empty. Disk
  Cleanup → "Clean up system files" → "System error memory dump files", or the cleanup script.
- `C:\Windows\Panther\monitor` — `WinSetupMon_*.log` files written during Windows feature updates.
  They can number in the thousands. They are NTFS-compressed, so their reported size is several
  times the space they take; report the on-disk size. Safe to delete from an admin shell.

## Package caches

All of these download again when needed. Clearing them costs download time on the next build.

| Cache | Command |
|---|---|
| NuGet (`~\.nuget\packages`, `%LOCALAPPDATA%\NuGet\v3-cache`) | `dotnet nuget locals all --clear` |
| pnpm store | `pnpm store prune` removes only packages no project uses. To remove all of it: `Remove-Item -Recurse -Force (pnpm store path)`; existing `node_modules` keep working. `pnpm store` with no second word only prints its usage. |
| npm | `npm cache clean --force` |
| Yarn | `yarn cache clean` |
| pip | `pip cache purge` |
| Gradle / Maven | delete `~\.gradle\caches` / `~\.m2\repository` |
| Playwright browsers (`%LOCALAPPDATA%\ms-playwright`) | keep if any project runs Playwright tests; `npx playwright install` restores them |

A cache that grows back after clearing is being used. Say so instead of recommending it again.

## Docker and WSL virtual disks

Docker Desktop keeps all images, containers, volumes and build cache inside one virtual disk,
`%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`. The file grows and **never shrinks by itself**:
`docker system df` can show 37 GB in use inside a 122 GB file. **Never delete the `.vhdx`.**

1. With Docker running, see what is inside: `docker system df`.
2. Remove what is not needed. Build cache is always safe: `docker builder prune -a -f`. Unused
   images: `docker image prune -a`. **Volumes hold data** (local databases, test fixtures): list
   them first with `docker volume ls -f dangling=true`, and never suggest `--volumes` or
   `docker system prune -a --volumes` without that list.
3. Quit Docker Desktop (tray icon → Quit). The next steps fail, or do nothing, while it runs.
4. `wsl --shutdown` (no admin needed).
5. Admin shell, compact the file. Write the file's full path, as the measuring script printed it,
   into `$vhdx`: an admin shell that runs as a separate admin account has that account's
   `$env:LOCALAPPDATA`, not the user's.

```powershell
$vhdx = 'C:\Users\<user>\AppData\Local\Docker\wsl\disk\docker_data.vhdx'; $f = New-TemporaryFile; "select vdisk file=`"$vhdx`"`nattach vdisk readonly`ncompact vdisk`ndetach vdisk" | Set-Content $f; diskpart /s $f; Remove-Item $f
```

Afterwards measure the file again; that is the only proof it shrank. If it did not, the last
option is Docker Desktop → Troubleshoot → "Clean / Purge data", which resets the disk to nearly
nothing and **deletes every image and volume**.

A WSL distribution's disk (`ext4.vhdx`, its folder is in `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss\*\BasePath`)
shrinks the same way: delete files inside the distribution, `wsl --shutdown`, then the same
diskpart steps with that file's path.

## Visual Studio Installer copies in Temp

The scheduled task `\Microsoft\VisualStudio\Updates\BackgroundDownload` runs every 3 hours. It can
leave a copy of the installer (a folder named like `2v2ox2hr.dux` holding `setup.exe`) in
`%LOCALAPPDATA%\Temp`, and these build up to tens of GB. Count only folders that hold
`setup.exe`: other programs also create folders with random names like these. Confirm by matching the
folders' creation times to the task's run times (`Get-ScheduledTaskInfo`). To stop it (admin):

```powershell
Disable-ScheduledTask -TaskPath '\Microsoft\VisualStudio\Updates\' -TaskName 'BackgroundDownload'
```

Visual Studio still reports available updates; the user installs them from the Visual Studio
Installer. An installer update can turn the task back on, so check its State after each update.
The Visual Studio setting "Automatically download updates" alone is not proven to stop the copies.

To find the cause of any other repeating growth, compare the creation times of the new items with
`Get-ScheduledTask | Get-ScheduledTaskInfo` run times and with the processes running at that time.

## A second database server version

Example: PostgreSQL 17 and 18 both installed. Before recommending removal of one, check:

- **Data**: count the folders under `<install>\data\base` (one per database). Three means only
  the default `postgres`, `template0` and `template1` databases. More means the user has data
  there, and removal is their decision after a backup.
- **Port**: read `port` in each `<install>\data\postgresql.conf`. The removed server may own the
  default port (5432); every connection that uses the default port then fails until it is
  changed to the remaining server's port. Say this before removal.
- **Shared tools**: each installer may bundle its own pgAdmin; shortcuts can point to the copy
  being removed.
- **PATH**: which version's `bin` is on PATH.

Removal: run `<install>\uninstall-postgresql.exe` (or Settings → Apps), then delete the
`<install>` folder, which the uninstaller leaves behind with the data folder in it.

## Chrome on-device AI model

`%LOCALAPPDATA%\Google\Chrome\User Data\OptGuideOnDeviceModel` (about 4 GB) is Chrome's built-in
AI model. Deleting it alone does not last: Chrome downloads it again. Turn off the on-device model
setting in `chrome://flags` first, restart Chrome, then delete the folder.

## Folders that report more than they use

Always compare the reported size with the on-disk size before recommending anything.

- `~\CrossDevice\<phone name>` — Windows shows a linked phone's files in File Explorer as cloud
  placeholders. It can report tens of GB while using almost nothing. Deleting it frees nothing;
  the feature is turned off in Settings → Bluetooth & devices → Mobile devices.
- OneDrive and Google Drive folders with files-on-demand — same placeholder behavior.
- `C:\Windows\WinSxS` — files are hard-linked into `System32`, so a folder sum counts them twice.
  The on-disk size counts them twice too: Windows reports the full size for every link, so the
  two columns agree and do not show the double count. Never delete from it by hand. Measure it properly and clean it with (admin):
  `Dism /Online /Cleanup-Image /AnalyzeComponentStore`, then
  `Dism /Online /Cleanup-Image /StartComponentCleanup`.
- NTFS-compressed folders (Panther logs, some program folders) — on-disk size is smaller.

## Never delete

- `C:\Windows\Installer` — needed to repair and uninstall programs.
- `C:\System Volume Information` — restore points; reduce their space in System Properties →
  System Protection → Configure.
- `C:\Program Files\WindowsApps` — Store apps; uninstall the app instead.
- Anything else under `C:\Windows` not named above.
- A `.vhdx` file — shrink it instead.
- Docker volumes or database data folders without listing their contents first.
