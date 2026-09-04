---
name: session-cleanup
description: Clean up after a finished piece of work — delete the branches, plan documents, spec artifacts, scratch files and background processes the session created, without touching anyone else's. Use this whenever the user says "clean up", "tidy up", "remove the branches", "delete the temp files", "kill the processes you started", or asks what is left over after work is merged and deployed. Reach for it too whenever you are about to delete a branch, a plan file, or a spec change after a merge, even if the user did not use the word "cleanup" — the checks here are what stop a deletion that looks safe from destroying work that only exists in one place. Especially important in a checkout that other people or other agent sessions are also using.
---

# Session cleanup

Cleanup is the phase where a careful session does its worst damage. Everything
is merged, the pressure is off, and deletion feels like tidying rather than a
change. But a branch delete can be the only thing standing between an unpushed
commit and oblivion, and `git branch -d` will happily tell you a branch is
unmerged when its content shipped an hour ago.

Two questions decide every deletion, and they are different questions:

1. **Is it mine?** Did this session create it?
2. **Is it recoverable?** If I am wrong, can the work be got back?

You need *both* answers before you delete anything. "Safe to delete" is not the
same as "mine to delete", and conflating them is the most common way this goes
wrong.

## The ownership test comes first

Before the git checks, before anything: **list what this session created.** Not
what is stale, not what is merged, not what looks finished — what *you made*.

Anything you did not create belongs to someone else, and "someone else" includes
another agent session working in the same checkout, a teammate, or the state the
repository was in when you arrived. Their branch may be stale, their plan
document may be obviously implemented, their scratch file may be pure noise.
None of that makes it yours to remove.

When you are unsure whether you created something, you did not. Sessions
remember what they did; uncertainty is itself the answer.

The failure mode is subtle because the reasoning feels responsible: you check a
branch, confirm its content is in `develop`, and delete it as housekeeping. The
check was real, the conclusion was true, and it was still not your call. Report
it instead:

> `feature/X` is fully contained in `develop` and looks finished, but this
> session did not create it, so I left it. Delete it with `git branch -d
> feature/X` if you want it gone.

That sentence costs nothing and it is always correct.

## Ancestry lies after a squash merge

For the branches that *are* yours, the question is whether their content is
somewhere durable. The instinct is `git branch -d`, which refuses anything not
reachable from the current branch. That instinct is wrong in both directions:

- **A squash merge produces a new commit with a new hash.** The content is on
  the target branch; the original commits are not ancestors of anything. Git
  reports "not fully merged" and refuses. The branch is nonetheless safe.
- **Ancestry can also pass while content is missing** — a branch merged before
  later commits were added to it looks contained by its merge commit while its
  newest work is not.

So ask about content, not lineage:

```bash
# Does this branch hold anything the target lacks?
git log --oneline <target>..<branch>          # commits not in target
git diff --stat <branch> <target>             # content difference, both directions
```

An empty `git diff --stat` means the trees agree and the branch is redundant
regardless of what ancestry says. If commits *are* listed, look at what they
actually change before concluding anything — a branch that is merely *behind*
the target will list nothing, while a branch carrying one real commit will show
it.

When ancestry and content disagree, content wins. Say which one you used:

> `agent/my-work` reports "not fully merged" because pull request #10 was
> squashed, but `git diff --stat` against `develop` is empty — the content is
> there. Deleting.

## Check recoverability before you delete, not after

A local branch delete is trivially reversible *if* the commit lives somewhere
else. It is permanent if it does not. Find out which case you are in first:

```bash
git ls-remote --heads origin '<pattern>'      # does the branch exist on the remote?
git branch -r --contains <sha>                # is the commit on any remote branch?
```

A commit on no remote branch, reachable from one local ref, is the one thing in
a cleanup that can actually be destroyed. Treat that ref as load-bearing even
when it is stale, even when it is someone else's, even when deleting it would
tidy the list. Say what you found:

> `agent/notify-admin` holds `fafd2c2`, which `git branch -r --contains` places
> on no remote. Deleting that branch destroys those 246 lines, so I left it.

If you delete something and realise it was wrong, do not panic — the commit
usually survives in the object store, and `git branch <name> <sha>` puts the ref
back. Restore the upstream too, so the branch is genuinely as it was:

```bash
git branch <name> <sha>
git branch --set-upstream-to=origin/<name> <name>
```

That restore only works because the commit was somewhere else. So never delete
the remote copy. `git push origin --delete <branch>` is not the bigger version
of the local delete; it removes the one thing that made the local delete
reversible, and it takes the branch away from everyone else at the same time.
Cleanup deletes local refs. If the remote branch should go too, say so and let
the user run it, or let the merge platform delete it when the pull request
closes.

## The rest of the sweep

Branches get the most attention because they are the most dangerous, but the
same two questions govern everything else.

**Worktrees.** A run that worked in its own checkout under
`../<repo>.worktrees/<name>` leaves two things behind: the directory, and a
registration inside `.git/worktrees`. Remove it with git rather than with the
filesystem:

```bash
git worktree list                    # what exists, and which branch each one holds
git worktree remove <path>           # refuses while the tree is dirty
git worktree prune                   # clears entries whose directory is already gone
```

`rm -rf` on the directory leaves the registration in place, and git then
refuses to check that branch out anywhere else until you prune. A `git worktree
remove` that refuses because the tree is dirty is the check doing its job: read
what is uncommitted there before you reach for `--force`. The branch the
worktree held is a separate question, answered by the two sections above.

**Plan documents and design briefs.** Many repositories delete a plan once it is
implemented. Two traps: a document that says *"Status: not started"* is queued
work, not finished work, and deleting it silently drops something from the
backlog. And the plan you were working from is rarely the only one in the
directory — check the filename against the work you actually did before removing
anything. If the repository's convention is to commit the plan and then delete it
in the implementing commit, that already happened during the work; there is
nothing left to clean.

**Spec and change artifacts.** If the workflow archives a change rather than
deleting it, the archive *is* the record and must stay. Folding a delta into the
live specs and moving the change folder is the cleanup — it is not a step that
leaves rubbish behind.

**Scratch files.** Your own temporary directory is the one place you can delete
freely. Remove the backups, patches, diffs and logs you created. If the user
names specific categories, remove those and say what remains rather than
guessing at the rest.

**Processes.** Kill what you started. Identify processes by what they are doing,
not by name alone — a `gcloud` or `node` process may belong to another session or
to the user. If you cannot tell whose it is, leave it and say so. Background jobs
that already exited need nothing.

**Uncommitted files that are not yours.** Do not commit them under your name and
do not discard them. Surface them, name the risk, and let their owner decide.
The same goes for staging: stage by explicit path, never `git add -A` or
`git add .`, because in a shared checkout those sweep up work you have not read.

## Shared checkouts move under you

When several sessions share a working directory, the branch can change between
one command and the next. Before any commit or branch operation, re-check where
you are:

```bash
git branch --show-current
git status --short
```

If you are on someone else's branch, do not commit there. Create your own from
the base you actually want:

```bash
git switch -c <my-branch> origin/<base>
```

Uncommitted changes carry across a branch switch, including other people's. That
is usually fine, but confirm the file you are about to disturb is identical on
both branches before switching — comparing the blob is enough:

```bash
git rev-parse <branch-a>:<path> <branch-b>:<path>
```

When another session is live in the checkout, tell it before you move the branch.
A short message naming what you intend to do, and what of theirs you have
noticed, is far cheaper than untangling a surprise afterwards.

## Report what you did not do

The most useful part of a cleanup report is the exceptions. A list of deletions
is reassuring and mostly uninteresting; the things you left, and why, are what
the user actually needs to act on.

Structure it as: removed, kept and why, and anything at risk. Keep the "kept"
entries specific enough to act on — a branch name, a commit, what would be lost.

If you made a mistake and reversed it, say that too. A cleanup that quietly
deleted and restored something looks identical to one that never erred, and the
user is the one who needs to know their branch briefly vanished.

## The habit underneath all of this

Cleanup rewards the same instinct as the work that preceded it: check the thing
itself rather than the story about the thing. `git branch -d` tells a story about
ancestry. A merge tells a story about content. A filename tells a story about
what a document is for. Each is usually right and occasionally, expensively,
wrong — so when a deletion is irreversible, spend the extra command and look.
