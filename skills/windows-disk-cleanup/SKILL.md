---
name: windows-disk-cleanup
description: >-
  Find what fills a Windows machine's disk and what can be removed without harm, give the user the
  commands to remove it, and re-measure after they run them. Measures with a bundled read-only
  PowerShell script (reported size AND real on-disk size, so cloud placeholders, sparse and
  compressed files are not mistaken for waste), sorts every large item into safe to delete /
  cache / shrink / your call / do not delete. Use whenever the user asks to free disk space,
  clean up the C drive, find what is taking space, check which files or folders can be removed,
  asks whether the folders a program left behind after it was uninstalled can be deleted, or
  pastes `du`, TreeSize or WinDirStat output and asks what is safe to delete; also for "check
  again" after a cleanup. Do NOT use for cleaning up
  after a coding session in a repository (branches, scratch files, worktrees - session-cleanup),
  for removing dead code (dead-code-removal), or on Linux or macOS.
---

# windows-disk-cleanup

Finds what fills a Windows disk, says what can go and how, and checks the result after the user
runs the commands. Two bundled scripts:

- `scripts/Measure-DiskUsage.ps1` — **read-only**. Drive free space, the Temp variables, the
  largest folders with reported and on-disk size, known locations with a category, large folders
  no installed program matches, Docker and WSL virtual disks, and repeating Temp growth.
- `scripts/Clear-DiskSpace.ps1` — deletes the "safe to delete" groups for the user, with
  `-DryRun`. It restarts itself elevated for the two Windows folders.

`references/locations.md` holds what each location is and the exact procedures (Docker shrink,
Visual Studio Installer task, second database server, Chrome model, OneDrive files kept on this
PC, placeholders, never-delete list). **Read the section for a location before recommending anything about it.**

## Rules

1. **You never delete.** You measure, explain, and give commands; the user runs them. This holds
   even when the user asks you to run them: hand over the command instead.
2. **Every size comes from a measurement taken in this session.** No size from memory, from the
   user's pasted output alone, or from an earlier check after the user changed something. Output
   cut short by a limit or a filter proves nothing about what is missing from it.
3. **Reported size is not space used.** Recommend on the on-disk size. A large gap means
   placeholders, sparse or compressed files; deleting those frees little. Hard links (WinSxS)
   show no gap: both columns count every link in full (`references/locations.md`).
4. **Name the Temp folder by full path** (`$env:LOCALAPPDATA\Temp`), never `$env:TEMP`. The
   user's `TEMP` can point to another folder, and your shell's environment can differ from the
   user's, so a check in your shell can measure a different folder than their command cleans.
5. **A folder is a leftover only after you confirm** its program is not installed, not a Store
   package, and not running; no environment variable or PATH entry points into it; and no
   extension of an installed editor uses it (`references/locations.md` → Folders of uninstalled
   programs).
6. **Unreadable is not empty.** Without admin, `C:\Windows\LiveKernelReports` and similar folders
   read as nothing. Report them as "not checked (needs admin)".
7. **Before removing anything that holds data, look inside**: database servers (database count,
   port), Docker volumes (list them), backups. Say what would be lost.
8. **A path you tell the user to run must exist.** Give the script's full path in this skill's
   installed folder (`${CLAUDE_SKILL_DIR}`, written out as the real path) and check the file is
   there first. Never give a path in a scratch folder, or a folder you only suggested copying to.
9. Follow the user's or project's wording rules for the report. Use plain words: "delete", "cache",
   "downloads again".

## Workflow

### Step 1 — Measure

Run the measuring script from this skill's folder. It takes several minutes on a full profile
(it walks every file once); run it in the background and wait for it.

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/scripts/Measure-DiskUsage.ps1"
```

If the user pasted `du` or similar output, use it only to decide where to look; the numbers in
your report come from the script or from your own follow-up measurements.

### Step 2 — Look closer at anything large and unexplained

For each large item the script does not classify: list its children with reported and on-disk
size, open a few files or names to see what it is, and match it against
`references/locations.md`. For anything that **keeps coming back** (thousands of similar items,
regular creation times), find what creates it: compare creation times with scheduled task run
times and running processes. The source is the fix; deleting the result is not.

### Step 3 — Report

Five groups, each a table with the path, the on-disk size, what it is, and how to remove it:

| Group | Meaning |
|---|---|
| Safe to delete | Temporary or regenerated by Windows; nothing is lost |
| Caches | Download again when needed; costs time on the next build |
| Shrink, do not delete | Virtual disks, WinSxS; give the procedure |
| Your call | Personal files, models, backups, second versions of programs; say what is lost |
| Do not delete | System folders and data; say what to do instead, if anything |

Then the commands: one per fenced `powershell` block, each marked when it needs an admin shell,
and the warnings that go with each (close VS Code first, quit Docker first, the port changes).
Offer `Clear-DiskSpace.ps1` when several "safe to delete" groups apply, by its full installed
path (rule 8); run it with `-DryRun` yourself first and show the numbers, and pass confirmed
leftover folders in `-LeftoverPaths`.
Name anything you could not check and why.

### Step 4 — Check again

When the user says they ran the commands, measure again (the script, or the specific paths) and
compare with the earlier numbers, item by item. For anything that did not change, find out why
before saying anything else: the command targeted a different folder, a program was still running
(Docker Desktop's start time is in `Get-Process`), a prune applied to a different builder, or a
cache was refilled by use. Report free space before and after. Say plainly when a step of yours
was wrong, and fix the command or script.

## Reference

- `references/locations.md` — every location, its category, and the procedures.
- `scripts/Measure-DiskUsage.ps1` — the measurement. Works in Windows PowerShell 5.1 and 7.
- `scripts/Clear-DiskSpace.ps1` — the deletion of the safe groups. Parameters: `-TempDays`
  (default 2), `-WorkspaceDays` (default 60), `-LeftoverPaths` (semicolon-separated),
  `-DryRun`.
