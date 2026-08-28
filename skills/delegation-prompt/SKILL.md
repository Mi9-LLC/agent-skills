---
name: delegation-prompt
description: >-
  Write a paste-ready prompt that briefs a DIFFERENT session, agent, or teammate
  to carry out a follow-up task on work this session just finished. Use whenever
  the user asks for "a prompt for another session", "write me a prompt to review
  this", "give me something to paste into a fresh session so it can do the next
  job", "brief another agent to test/port/audit this", or otherwise wants to hand
  a new job to someone who was not part of this conversation. Trigger it even
  when the user only says "generate the prompt" or "write it up for the reviewer"
  after finishing a piece of work, because that is the same request. The skill
  decides whether the receiving session is CHECKING this session's work (in which
  case it withholds this session's conclusions, so the reviewer verifies the work
  instead of agreeing with the answer) or EXTENDING it (in which case it hands
  over everything already worked out). Do NOT use it to save context so the SAME work
  can continue after a pause or a full context window, which is session-handoff's
  job; and do NOT use it to perform the follow-up task yourself, which is what
  the user is explicitly asking someone else to do.
---

# Delegation prompt

You have just finished something. The user wants a prompt they can paste into a
different session so that session does the next job: review the pull request,
test the change on another machine, port the same fix to a sibling repository,
audit what was built.

You are not doing that job. You are writing the brief for whoever does.

If the user instead wants the SAME work to continue later, in a fresh window or
after a pause, that is `session-handoff`, not this skill. Say so and stop.

## What you produce

One fenced code block in the chat, containing the whole prompt and nothing else,
so the user can copy it in one gesture. Above it, one to three lines saying which
mode you chose and why. Below it, nothing. No summary, no offer to also run it.

Do not write it to a file unless the user asks. A prompt they have to go and open
is slower to use than one already on screen.

## Decide the mode before you write the prompt

Everything else follows from this, so settle it first.

**Checking mode.** The receiving session will review, audit, verify, test, or
question work this session produced. Its value comes entirely from reaching
its own conclusions.

**Extending mode.** The receiving session will continue, implement, port, deploy,
or build on the work. Its value comes from not repeating what you already did.

Say which one you picked in the lines above the block, with the reason. When a
task is genuinely both (port this fix and check it still holds), keep both parts
inside the single block as two headed sections, one under checking rules and one
under extending rules, and name the split in the lines above the block.

### Why the mode matters more than the formatting

In checking mode, every conclusion you hand over is one the receiving session no
longer reaches by itself. Tell a reviewer "the sort order is preserved" and you
will very often get back "confirmed, the sort order is preserved". That is
agreement, not verification. The reviewer read your sentence, found
nothing that contradicted it, and stopped. If your sentence was wrong, the review
cannot catch it, because your sentence is what it was measuring against.

So in checking mode you hand over the facts the session cannot derive on its own,
and you keep the judgements it exists to make. In extending mode the opposite is
true: making it re-derive what you already established wastes its budget and adds
a chance to get it wrong.

## The receiving session knows nothing

It cannot see this conversation, your reasoning, the files you opened, or the
commands you ran. This is the most common way these prompts fail, and it fails
silently: the prompt reads perfectly to you, because you supply the missing
context without noticing.

Before you finish, read the block as if you had never seen this conversation.
Every identifier it names, could you find it? Every claim it makes, could you
check it? Anything that only makes sense because you were here has to be spelled
out or cut.

Be concrete about identifiers. "The PR" is useless; "pull request #8 in
mi9retail/loyalty-service" plus the URL is not. The same goes for branch names,
file paths, ticket numbers, and the exact tool to use. A path that is valid only
on this machine is not an identifier for a session elsewhere; give the clone URL,
branch, and commit sha as well.

When the recipient is a person rather than an agent, drop the instructions only
an agent needs (tool call order, skill names) and keep the identifiers, the
traps, and the ground rules.

## Carry over only what you can trace to a source

Writing this prompt means compressing finished work into a page, and the gaps
show. You will not know which files changed, or what the incident looked like
minute by minute, or which of two approaches was tried first. A plausible answer
comes to mind for each gap, and the prompt reads better with it filled in. This
is the most damaging failure this skill guards against.

Measured while testing this skill: given a description of some retry-logic work,
prompts written without this rule invented a timing profile for the incident
("three synchronised spikes at 5, 10 and 15 seconds"), invented what the load
scenario models, and invented that one file was the only file changed. Given a
migration rename, another invented a prior decision nobody had made and put it
under a heading reading "the rules we learned, which are not negotiable". None of
it was in the user's message. Every one reads as ordinary, helpful detail.

It is worse here than in ordinary conversation for a specific reason. In chat the
user sees the invented fact and corrects it in the next message. In a delegation
prompt it travels to a session that was not there, cannot check it against
anything, and will treat it as ground truth given by the person who did the work.
A reviewer told that one file was the only one changed has been given a reason
not to look at the others.

So for every specific claim you write down (a number, a filename, a date, a
version, a command, a decision that was made), be able to point at where it came
from: the user said it, you read it in a file, you ran the command, or this
session did it. If you cannot trace it, cut it or mark it unknown.

Marking it unknown is usually better than cutting it. "The author did not say
which other files changed; establish that yourself" tells the receiving session a
gap exists and to go fill it. Silence leaves it assuming the prompt was complete.

Two things this rule does not forbid. General knowledge that invents no fact
about this work is fine, so a note that half-up and half-even rounding disagree
on negative values is advice, not a fabrication. And arithmetic on numbers the
user gave you is fine when you show it as derived: three attempts at five seconds
is about fifteen seconds, marked approximate.

## What usually belongs in the prompt

Not a template to fill in order. A checklist of what tends to matter, so you
notice what you left out.

**The task and its identifier.** One line. What to do, to what, and the URL or
path that finds it.

**How to do it.** The specific tools, commands, or steps. If the job needs a
particular MCP server, CLI, or script, name it, because a session guessing at
this wastes its first several turns. If the job is what an installed skill
does (`verify-implementation` for a claim of doneness, `plan-eng-review` for a
written plan, `security-vulnerability-scan` for a security review), tell the
receiving session to invoke that skill by name, and say it must be installed.

**What the work is.** Enough that the receiving session reads the artifact
correctly. In checking mode this is description, not assessment: what changed and
why it was done, not whether it was done well.

**Provenance and how far to trust it.** If an AI session produced the work, say
so, and say that claims in commit messages and descriptions are claims to verify
rather than evidence. Reviewers calibrate differently once they know, and they
should.

Do not let the rule above about carrying over only what you can trace to a source
talk you out of this. The mistake was observed: a run refused to state provenance
because the user had not literally said who wrote the code. You were there. If
this session produced the work, or produced it alongside the user, that is
first-hand knowledge and reporting it is not inventing. What you cannot do is
guess at provenance you do not have, such as asserting how an earlier commit on
the branch was written when you never saw it made.

**What to verify or what to build on.** In checking mode, write these as
questions with no answers attached: "does the run order survive?", not "the run
order survives". Point at where the risk lives, especially where a normal reading
of the diff would miss it, and say how to settle it rather than what it settles
to. In extending mode, just state what you established, so nothing is redone.

**Things that look like defects and are not.** Include these in both modes, and
in checking mode frame every one as a claim to test: "the change claims the
archive is deliberately left stale; judge whether that reasoning holds". Without
this the reviewer spends an hour on a non-issue and files a wrong finding. Stated
as a verdict ("the stale archive is fine") it removes a check the reviewer should
still run. Attaching the claim and asking them to judge it keeps both.

**Environment traps.** Always include these, in both modes, and be blunt about
them. They are facts about the machine, not judgements about the work, so they
cost nothing in independence and save hours. The kind of thing that belongs: a
package that must be reinstalled after checkout or a stale copy is used, a build
cache that returns a pass without running anything, a service that must be
started first, a sibling checkout that is read-only. Say what the failure looks
like when it happens, because misdiagnosing the failure costs more time than the
failure itself.

**Ground rules.** What not to do. Read-only, do not push, do not merge, do not
edit repository X. Say these plainly; a session that is not told assumes it may.

**No secrets.** The prompt will be pasted, forwarded, and possibly logged. Never
put a token, password, API key, or connection string in it, even one you saw in
this session. Name where the credential lives instead (the environment variable,
the `.env` file, the secret store) and how the receiving session obtains it.

**The output you want.** Where it goes, what shape it takes, and any house style
the user cares about. If the receiving session is posting a comment somewhere
public, that matters more, not less.

Cut any line the receiving session would not act on. A long prompt is not a thorough one,
and the reader has to hold all of it.

## Where these prompts go wrong

**Telling them the answer.** Covered above, and it is the failure this skill
mainly exists to prevent. Watch for it coming back through wording:
"verify the fix is correct" already asserts it is a fix.

**Assuming context you have and they do not.** The prompt reads fine to you
because you fill the gaps automatically. Read it cold.

**Filling a gap with something plausible** rather than marking it unknown. See
the section above; this is the failure that survives longest, because an invented
fact in a delegation prompt has nobody left who can contradict it.

**Leaving out the traps** because they feel like your problem rather than theirs.
They are about to hit the same ones.

**Asking for agreement.** "Confirm this looks good" produces confirmation.
"Decide whether this holds, and say what you ran" produces a review.

**Padding.** Restating something already stated elsewhere in the same prompt, or
repeating the same instruction in three places. It buries the parts that matter.

## Worked example, checking mode

An implementation session had just renamed a set of database migration files and
opened a pull request. The user asked for a prompt so a separate session could
review it.

The lines above the block:

> Here is the prompt. I have deliberately kept my own conclusions out of it, so
> the review does not measure the work against them. It gets the facts needed to
> read the diff correctly, and the risk areas are framed as questions rather than
> as reassurances.

Inside the block, the shape that worked:

```
Review pull request #<number> in <workspace>/<repo> using the <named> tools.
<url>

Read + comment only. Do not push, do not merge, do not edit any code.

## How to do it
<the specific tool calls, in order, and the local checkout it can use to
verify claims the diff alone cannot settle>

## What the change does
<description, not assessment. What changed and why.>

This change was written by an AI session, not typed by a human. Treat every
claim in the commit messages and the description as a claim to verify, not as
evidence.

## Verify these independently
<numbered risk areas, each phrased as a question, each saying how to settle it
and never what it settles to. "Work out from the library source how X sorts,
then decide for yourself whether Y is right." Not "Y is right because X.">

## Things that look like misses and are claimed to be deliberate
<each one, with the claim attached and an instruction to judge whether the
reasoning holds rather than to accept it>

## Repo facts you need
<every environment trap: a stale-install caveat, a cache that fakes a pass, the
order the gates must run in, what needs to be running. Plus: if you see <this
failure>, suspect a stale install before suspecting the change.>

## The review comment
<where it goes, its shape, and: every finding must quote its evidence; say what
you checked and found fine, so the author can tell that apart from what you did
not check>
```

Note what is absent. It never says the change is correct, never says the tests
pass, never says an earlier audit came back clean. Those were exactly the things
the review existed to determine.

## Worked example, extending mode

Same work, but the user wants another session to apply the same rename to a
sibling repository. Now the conclusions are the point:

```
Apply the same migration filename change to <sibling repo> that was just made in
<this repo>, commit <hash>.

## What was decided and why, so you do not re-derive it
- The prefix is exactly 17 digits reading YYYYMMDDHHMMSSmmm in UTC. Not 16, not
  18: the migration runner reads exactly 17 as a date and any other length as a plain
  number, which sorts it in the wrong place with no error.
- <the rest of the settled decisions, stated as settled>

## Traps hit in the first repository, so you do not hit them
<the traps, the same as checking mode>

## What is different about this repository
<the parts that do not transfer>
```

The traps and the environment facts appear in both modes. Only the judgements
move.
