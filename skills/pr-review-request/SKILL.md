---
name: pr-review-request
description: >-
  Write the Google Chat message that asks colleagues to review one or more open pull requests: the
  team header, then four short sections (why, what changed, behavior to check, also in the PR),
  every fact read from the pull request, its diff and the ticket. Use it when the user wants a review request, a
  "ready for review" message or a pull request announcement for the team chat: "write a review
  request for PR 50", "ask the team to review these PRs", "draft the Google Chat message for my
  pull request", "announce PR 394 and PR 27 for review", or a pasted PR URL with "ready for
  review, write the message". Outputs one code block to paste and posts nothing. Do NOT use it
  to review a pull request, which is pr-review's job, even when "PR" and "review" both appear
  ("review PR 29", "can you review this pull request"); to brief another AI session to review the
  work (delegation-prompt); to reply to a reviewer's comments on a pull request; or to write the
  pull request's own title or description.
disallowed-tools: Edit, Write, NotebookEdit
argument-hint: "<pull request URL or number> [more URLs or numbers]"
---

# Pull request review request

The user has one or more pull requests open and wants colleagues to review them. You write the
message they paste into Google Chat. You do not review the pull request, and you do not post
anything.

The reader is a reviewer who has not seen the diff. After reading the message they should know
where the risk is before they open the pull request. That is the whole purpose of the detail
sections: a message that only says "ready for review" makes the reviewer find the risk alone, and a
long one does not get read.

## What you produce

- One fenced code block that holds the whole message. The raw Google Chat markup goes inside the
  block, so that the asterisks and backticks survive copying.
- Above the block, a short note of at most six lines, one line per item, in this order:
  1. the reviewer mention has to be entered again in Chat (see "Reviewer mentions");
  2. what you left out because no source gave it (the ticket key, a figure, what a file changes),
     all on one line. An empty *Also in the PR* is not reported: most pull requests have nothing
     for it;
  3. each difference you found between the description and the diff;
  4. anything the user should fix before sending, such as a secret in the diff;
  5. when you could not read the diff, that the message rests on the pasted text alone.

  Nothing else goes in the note: not how you chose a word, not what the message already says, and
  not a list of everything you did not read.
- Below the block, nothing. No summary and no offer to post it.

Fence the block with three backticks.

Do not write the message to a file, and do not send it anywhere. This skill declares
`disallowed-tools: Edit, Write, NotebookEdit` because its only output is text in the chat. It
declares no `allowed-tools`: the Bitbucket tools are the user's own Composio MCP registration and
cannot be listed here.

If the user says that Chat shows a line break in the middle of a paragraph, the text was selected
with the mouse in a terminal, and that copies the terminal's wrapped lines. Tell them to copy the
block with `/copy`, which copies the reply's own text and offers the code block as a choice.

## Input

- One or more pull request URLs. They are usually Bitbucket URLs of the form
  `https://bitbucket.org/<workspace>/<repo>/pull-requests/<n>`. One ticket often has pull requests
  in several repositories; they all go in one message.
- A bare pull request number means that pull request in the repository that
  `git remote get-url origin` points at. If that does not resolve to one repository, ask.
- Optional: the ticket key, the reviewer names, and the section to stress.

## When you have to ask

Several steps below say to ask the user. Ask with `AskUserQuestion` when the session has that
tool. When it does not (a `claude -p` run, a subagent), put the question in the reply and stop.
Stopping means that you write no message block: not a partial one, and not one built on the most
likely answer. Only the user's own words answer the question. The state of the repository, the
pull request title and what is usual in other pull requests do not.

## Step 1: Read the pull requests

Read every pull request before you write a word. For each one you need the title, the description,
the state and the draft flag, the source and destination branch, the commits, and the diff stat
(the changed files with added and removed line counts).

**Bitbucket.** Use the Composio MCP tools: call `COMPOSIO_SEARCH_TOOLS` to load the tool schemas,
then run them through `COMPOSIO_MULTI_EXECUTE_TOOL`. These slugs are the ones the `pr-review` skill
uses and are verified to exist. Do not invent others.

- `BITBUCKET_GET_PULL_REQUEST`: title, description, state, draft flag, branches.
- `BITBUCKET_GET_PULL_REQUEST_COMMITS`: the commit messages.
- `BITBUCKET_GET_PULL_REQUEST_DIFFSTAT`: the changed files. The response is paginated: follow
  `response.data.next` until it is absent. `values[].new.path` is null for a deleted file, so fall
  back to `values[].old.path`.
- `BITBUCKET_GET_PULL_REQUEST_DIFF`: the unified diff. If `response.data.truncated` is true, the
  diff is incomplete. Read the missing part from a local checkout or leave those files undescribed.
- `BITBUCKET_GET_FILE_FROM_REPOSITORY`: one file at a commit, for a CHANGELOG entry or a design
  document that the pull request adds.

**GitHub.** Use `gh pr view <url> --json title,body,state,isDraft,baseRefName,headRefName,commits,files,additions,deletions`
and `gh pr diff <url>`.

**A local checkout** of the repository can replace or complete either one. Use read-only git
commands against the remote-tracking branches: `git log --oneline origin/<destination>..origin/<source>`,
`git diff --stat origin/<destination>...origin/<source>` and `git show`. Compare
`git rev-parse origin/<source>` with the pull request's head commit first. Bitbucket gives that
hash as 12 characters, so the two match when the short one is the start of the long one. If they
differ, run `git fetch origin` and compare again. Never check out, switch or pull a branch: the
working tree belongs to the user.

**Read the diff itself when the description and the diff stat do not answer a question** the
message has to answer: what one change does, whether a limit is 128 or 256, whether a config file
changed. For a small pull request, read all of it. For a large one, read the files the message
names. A diff you read only in part (a large pull request, a truncated response) supports claims
about the files you read and no claim about the rest: see the "unchanged" line under *Behavior to
check*.

**Then read what explains the change**, when it exists:

- The ticket. If the user did not paste it, look for a Jira tool with `COMPOSIO_SEARCH_TOOLS` or
  use an Atlassian connector if the session has one. If neither is there, continue without the
  ticket and do not describe its content.
- A CHANGELOG entry in the diff stat.
- A spec, plan or design document in the diff stat or named in the description, for example
  `design.md`, `openspec/changes/<name>/` or a file under `docs/plans/`. This is usually the best
  source for *Why* and for an accepted trade-off.

**If a pull request cannot be read** (no Composio tools, no `gh`, no local checkout, nothing
pasted), ask the user to paste the description and the diff stat. Do not write the message from
the URL and the title alone.

**If a pull request is not open, or is a draft, say so and ask before you write.** The mention line
says the pull request is ready for review, and for a merged, declined or draft pull request that is
false.

## Step 2: Every claim has a source

The message is sent under the user's name to people who act on it. A reviewer who reads "response
codes are unchanged" does not check response codes. So every specific claim in the message (a
number, a file name, a limit, a behavior change) must come from one of these:

- the pull request title or description, or a commit message,
- the diff or the diff stat,
- the ticket, a CHANGELOG entry, or a spec or plan document,
- the user's own words in this conversation.

When no source gives a fact, leave it out, and say in the note above the block what is missing. Ask
only when the header cannot be written without the answer. Never fill a gap with a plausible guess:
a guessed request rate or row count reads the same as a real one, and nobody in the chat can tell
them apart.

Three rules follow from this:

- **A number the diff can confirm is confirmed in the diff.** A length limit, a constant, a file
  name. If the description says 128 and the code says 256, the code is right: write 256 and tell
  the user about the difference in the note.
- **A number only a document states is carried as stated.** A production measurement, a request
  rate, a memory figure. Do not round it, recompute it, or extend it to a case the source did not
  cover.
- **"Unchanged" is a claim too.** See *Behavior to check* below.

## Step 3: Write the message

The message has two parts. The header is the team's existing format and stays as it is. The detail
sections come after it.

### The header

```
STF-1330 LDA: Fix multi-release deployments running newest-first

Hi @<reviewer> These PRs are ready for review.

LDA PR: https://bitbucket.org/<workspace>/<repo>/pull-requests/394

DMS PR: https://bitbucket.org/<workspace>/<repo>/pull-requests/27
```

- **Line 1 is `<TICKET> <Component>: <summary>`.**
  - The ticket key comes from the user, the pull request title, the branch name
    (`bugfix/ORD-340-carrier-webhook-retries`) or the commit messages. If none of them has one, write
    the line without a key and say so in the note.
  - The component is the short name the team uses for the product or repository: the name the user
    gave, or the prefix the pull request title already carries. If there is neither, use the
    repository name from the URL. Do not make up an abbreviation. With several repositories, it is
    the component the ticket or the main pull request names; if that is not clear, ask.
  - The summary says what the change does, starting with a verb: "Fix ...", "Stop ...", "Add ...".
    Take it from the pull request title, and rewrite it when the title is vague ("Redis fixes").
- **The mention line** is `Hi @<reviewer> This PR is ready for review.` for one pull request and
  `Hi @<reviewer> These PRs are ready for review.` for more than one. It is the only greeting in
  the message.
- **One `<Repo label> PR: <url>` line per pull request**, with a blank line between them. The label
  follows the same rule as the component. The URL is the pull request's main page, without a
  `/diff` suffix or a query string.

### Reviewer mentions

- If the user gave no reviewer names, write `@<reviewer>` and say in the note that it is a
  placeholder. Never invent a name, and never take one from the pull request's reviewer list or
  from a commit author unless the user tells you to.
- If the user gave names, write them as given: `Hi @Name1 @Name2 This PR is ready for review.`
- In both cases the note says that the mention has to be entered again in Chat. Google's page
  tells a person to enter `@` and then the person's name, and, in its steps for editing a message,
  to select the name from the suggestion menu. It does not document that a pasted `@Name` becomes
  a mention, so treat the pasted one as plain text and do not tell the user that it will notify
  anyone.

### The detail sections

They come in this order. Include a section only when it has content from a source; a section with
nothing in it is left out, not filled.

1. `*Why*`: the problem, with its concrete effect. What went wrong or could go wrong, where, and
   how much: the endpoint, the size, the rate, who is affected. Two to four sentences in one
   paragraph.
2. `*What changed*`: one bullet per change a reviewer has to understand, not one per file. Each
   bullet names the file or the function in backticks and says what the change does, with the
   value that changed ("was `Promise.allSettled`", "max 128 characters"). When the message covers
   more than one pull request, start each bullet with the repo label.
3. `*Behavior to check*`: what behaves differently after this change, and the trade-offs the
   reviewer has to judge. A trade-off that was accepted on purpose is named as accepted, with the
   document that describes it. The last bullet says what did NOT change: response codes, config,
   env vars, deployment. Put an item on that line only after you checked it: "config and env vars"
   when no config file or env schema is in the diff stat, "deployment" when no Dockerfile, pipeline
   file, deploy script or database migration is, "response codes" when you read the whole diff and
   it changes none, or the description says so. After a partial read of the diff, the diff cannot
   put "response codes" on the line. Leave out an item you could not check. Write the line as the
   claim ("Config and env vars are unchanged."), not as the check you ran ("no Dockerfile is in
   the diff stat").
4. `*Also in the PR*`: changes in the same pull request that are not part of the fix: tooling,
   generated files, archived specs, an unrelated cleanup. It tells the reviewer which files they
   can read quickly.

**The message has no *Not in scope* section and no *Verification* section.** Do not write them,
under these names or others, and do not say in the note that they are missing.

- The gates (lint, typecheck, tests, build) pass before a review is requested, so a line saying
  that they pass is the same in every message and tells the reviewer nothing. Do not run the gates
  for this message, and do not put test counts or gate results in another section.
- A list of what the pull request does not do is not what the reviewer came to check. A design
  document's non-goals do not go in the message.

**The section to stress.** When the user names one, that section gets the detail and the others
are cut to one or two lines each. The order does not change.

### Length and layout

- The whole message, header included, stays within about 350 words. A larger pull request does not
  get a longer message. When the draft runs over, group the smaller changes under *What changed*
  and shorten *Why* and *Also in the PR* first. *Behavior to check* is cut last, because it is
  where the reviewer's risk is.
- Each section is one short paragraph or two to six bullets. If *What changed* needs more than six
  bullets, group the smaller changes into one.
- Write each paragraph and each bullet as one line. Do not wrap lines inside the block: a line
  break in the block is a line break in Chat.
- One blank line between sections. The section label is on a line of its own, and its text starts
  on the next line.

### Wording

The message is technical and professional. It reads like a colleague who knows the change stating
facts.

- No pleasantries except the mention line. No "Hi team", "can you please", "kindly", "thanks in
  advance", no sign-off, no emoji.
- Use the common, literal word. "The check runs after validation", not "the check now lives behind
  validation".
- No figurative verbs for plain facts: not "lands", "ships", "drops", "surfaces", "kicks in".
- No AI vocabulary: not "robust", "seamless", "comprehensive", "streamline", "leverage", "ensure"
  where "make sure" or a plain statement fits.
- No em dashes. Use a period, a comma or a colon.
- State numbers with their unit, as the source gives them: "60 units per 300 s", "1,024 JSON
  characters".
- Say what the code did and what it does: "was `Promise.allSettled`", "now runs in a `preHandler`".
- Keep the names the code uses. Do not rename a function, a setting or an endpoint to something
  more readable.
- Never put a token, password, API key or connection string in the message, even one you saw in
  the diff.
- Never add a line saying that the code was written with an AI tool or reviewed by an AI session,
  even when that is true or the user confirmed it. Do not offer such a line in the note. If the
  user asks for one, leave it out and say in the note that this skill does not add it. A direct
  request in the prompt does not change this: the owner of this skill decided the rule, and the
  user can type the line into Chat by hand.

## Google Chat markup

Checked on 2026-11-24 against Google's pages; re-check them when a message does not render as
expected.

What a person can type in the compose box
([Add formatting to your Google Chat messages](https://support.google.com/chat/answer/7649118)):

| Result | Typed |
|---|---|
| Bold | `*Text*` |
| Italic | `_Text_` |
| Strikethrough | `~Text~` |
| Inline code | `` `Text` `` |
| Multi-line code block | ```` ```Text``` ```` |
| Block quote | `>Text` |
| Bullet | `- Text` or `* Text` |
| Numbered list | `1. Text` |

What is not available to a person typing:

- **No headings.** The help page lists none, and Google's developer page marks headings "Not
  supported" in Chat's own syntax
  ([Format messages](https://developers.google.com/workspace/chat/format-messages)). Do not write
  `#` lines.
- **No `[text](url)` links, no `**bold**`, no tables.** The developer page lists these only for
  messages an app sends through the Chat API in Markdown mode. For a person, the help page offers
  the *Insert link* button and nothing typed. Paste the bare URL on its own; the developer page
  says a plain URL in message text is turned into a link.
- **Mentions are not markup.** See "Reviewer mentions"
  ([Mention someone or add someone to a message](https://support.google.com/chat/answer/14170425)).

What the message uses, and why:

- `*Label*` for the section labels, on a line of their own.
- Backticks around every file name, function, endpoint, setting, key and code value. This is also
  what protects them: `*`, `_` and `~` format text, so an identifier such as `pending_secret_hash`
  outside backticks can come out partly in italics.
- A literal `•` followed by a space for bullets. It is a plain character, so it reads as a bullet
  whether or not Chat converts markup in the pasted text.
- Bare URLs.
- Nothing else: no italics, no strikethrough, no quotes, no numbered lists, no code blocks.

One thing Google does not document: what happens to these characters when text is pasted, as
opposed to typed. The help page describes characters added "as you type", and says that with
*Live Markdown* off "after you send the message, the text converts to the format". It was tested
once, on 2026-11-24: a message from this skill, pasted into Google Chat and sent, showed bold
section labels, inline code, the `•` bullets and a linked URL. That test did not record whether
*Live Markdown* was on. If the user reports that the asterisks and backticks still show after
pasting, point them to that setting (Settings, then *Message & Media*) and do not claim a behavior
the page does not state.

## Check before you show it

Read the block once as the reviewer, then check:

1. Every number, file name, limit and behavior claim traces to a source from Step 2.
2. Line 1 is `<TICKET> <Component>: <summary>`, and the mention line is singular for one pull
   request and plural for more.
3. There is one link line per pull request, and each URL is the one the user gave, without a
   suffix.
4. Each item on the "unchanged" line was checked against the diff stat or the whole diff.
5. There is no *Not in scope* section, no *Verification* section and no gate or test result, and
   no line says the code or the review was done with an AI tool.
6. No `#`, no `[text](url)`, no `**`, no em dash, no line wrapped inside a paragraph.
7. Every identifier is in backticks.
8. No real name that the user did not give, and no secret.
9. The note above the block says the mention has to be entered again, and names what was left out.
10. The whole message is within about 350 words.

## Worked example

The example is invented: the service, the ticket and every number are made up, so that no real
system is described here. Its shape and length are those of a review request a user accepted on
2026-11-24.

The user asked for a review request for one pull request and gave no reviewer names. The ticket,
and the decision record were available in the session.

The note above the block:

> `@<reviewer>` is a placeholder. In Chat, replace it by typing `@` and choosing the person from the
> suggestion menu.

The block:

```
ORD-340 Orders: Stop duplicate shipments when the carrier retries a webhook

Hi @<reviewer> This PR is ready for review.

Orders PR: https://bitbucket.org/<workspace>/<repo>/pull-requests/50

*Why*
`POST /api/v1/webhooks/carrier` created the shipment before it checked whether the event was already processed. The carrier sends an event again when the response takes longer than 10 s, up to 5 times, so one slow request could create 6 shipments for one order. The ticket lists 41 orders that were shipped twice in March.

*What changed*
• `carrierWebhook.routes.ts`: the handler first inserts the event id into the new table `webhook_events`. When the id is already there, it returns 200 and does nothing else.
• `shipment.service.ts`: `createShipment` runs in the same transaction as that insert (was two separate calls).
• `carrierWebhook.schema.ts`: `eventId` max 64 characters. A longer one gets 400 before any write.
• `purgeWebhookEvents.job.ts`: a nightly job deletes `webhook_events` rows older than 30 days.

*Behavior to check*
• A repeated event returns 200 with an empty body. It returned 201 with the shipment before.
• An event that arrives again after 30 days is processed a second time. This trade-off is accepted and described in `docs/adr/0017-webhook-idempotency.md`.
• Each webhook request makes one more database write, adding about 3 ms.
• The migration `0042_webhook_events.sql` has to run before this version starts.
• Config and env vars are unchanged.

*Also in the PR*
`package-lock.json` is regenerated with no version change, and the test helper `buildOrder.ts` is renamed to `orderFactory.ts`.
```

What to notice:

- The header is the team's format, unchanged. The sections add to it and do not replace it.
- *Why* gives the effect in numbers a reviewer can weigh: 10 s, 5 repeats, 6 shipments for one
  order, 41 orders shipped twice.
- *Behavior to check* states the accepted trade-off as accepted and names where it is described,
  so the reviewer judges it and does not report it as a defect.
- The last bullet of *Behavior to check* names only config and env vars. A response code changed
  (201 became 200) and a migration is in the diff, so neither "response codes" nor "deployment" is
  on that line.
- There is no *Not in scope* and no *Verification* section. The gates passed before the review
  was requested, and the message does not repeat that.
- The message is 240 words. Every number in it would have to be in the diff, the decision record
  or the ticket. None is estimated.
