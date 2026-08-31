---
name: unslop
description: >
  Edit human-facing prose to remove the patterns that mark text as AI-written: puffery,
  AI vocabulary ("delve", "crucial", "landscape"), "not just X, but Y", forced groups of
  three, em-dash and colon overuse, bold-label lists, title-case headings, chatbot phrases,
  filler, hedging, abstract metaphor nouns ("substrate", "north star"), passive voice, and
  feeling-words in place of facts. Use when the user asks to unslop, de-AI, humanize, or
  clean up text, or to make writing "sound less like AI" — for documentation, README files,
  blog posts, emails, announcements, PR descriptions, and other prose people will read.
  Also apply on your own when writing a new documentation page, README, or announcement.
  Do NOT use on code, code comments, commit messages, or Claude's own chat replies - the
  length, wording, and AI tells of a chat reply are clear-and-short's job, including when the
  user asks to humanize the replies themselves ("humanize your responses", "your answers sound
  like ChatGPT"); this skill takes the request only when it names prose other people will read.
  Do NOT change the meaning, facts, numbers, or the technical terms of the text.
---

# Unslop

Edit text to remove the patterns that mark it as AI-written, keeping its meaning and tone.

## Process

1. Scan for the patterns below.
2. Rewrite. Preserve meaning, match intended tone.
3. Self-audit: "What makes this obviously AI generated?" Fix remaining tells.

## Patterns to detect and fix

### Content

1. **Puffery.** "pivotal moment", "testament to", "evolving landscape", "setting the stage for", "indelible mark", "deeply rooted". Cut puffery, state what happened.
2. **Name-dropping.** Listing media outlets without context. Pick one, say what was said.
3. **Superficial -ing phrases.** "highlighting...", "ensuring...", "reflecting...", "showcasing...", "fostering...". Delete or expand with real sources.
4. **Promotional language.** "nestled", "vibrant", "breathtaking", "groundbreaking", "renowned", "stunning", "must-visit". Use neutral descriptions.
5. **Vague attributions.** "Experts believe", "Industry reports suggest", "Some critics argue". Name the source or delete.
6. **Formulaic challenges.** "Despite challenges... continues to thrive." Replace with specific facts.
7. **Answering an objection nobody raised.** "This isn't really about...", "I'm not saying...", "To be clear", "Don't get me wrong". Remove the defense. If it holds a real claim, state that claim on its own.
8. **Rejecting a fake alternative.** "A tempting approach would be to rewrite the parser, but..." where the tempting approach never comes back. Cut the fake option, state the real constraint.
9. **Writing about the previous version.** Documentation and comments describe current behavior. "The loader no longer scans the whole tree" tells a new reader nothing. Keep before-and-after only in change logs, release notes, and migration guides.

### Language

10. **AI vocabulary.** Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate, landscape (abstract), pivotal, showcase, tapestry (abstract), testament, underscore, vibrant. Replace with plain words.
11. **Fancy ways to say "is".** "serves as", "stands as", "boasts", "features". Just say "is" or "has".
12. **"Not just X, but Y."** State the point directly instead. The tailing negation is the same pattern turned around: "The options come from the selected item, no guessing." becomes "The options come from the selected item, without forcing the user to guess."
13. **Rule of three.** Forcing ideas into groups of three. Use the natural number.
14. **Synonym cycling.** Protagonist, main character, central figure, hero all in one paragraph. Pick one, repeat it. Repeated sentence openings are the same tell in the other direction: "She noted the door. She noted the lock. She filed both away." Merge the sentences or start with the action. Do not ban the repeated word itself.
15. **False ranges.** "from X to Y" where X and Y aren't on a meaningful scale. List topics directly.

### Style

16. **Em dash overuse.** Avoid em dashes entirely. Use periods or commas only (no parentheses, no en dashes, no hyphen-as-dash substitutes). Em dashes are an AI tell, and reaching for parentheses instead just trades one tell for another. If a thought needs separation, end the sentence or use a comma.
17. **Colon overuse.** Colons are fine before a list or example. Not as mid-sentence connectors. "If you're coming from traditional automation: instead of registering event handlers, you describe conditions" adds nothing with the colon. Rewrite to let the point stand on its own without comparison framing. "Describing when the scheduler should fire works best as plain English." Same meaning, no crutch punctuation.
18. **Boldface overuse.** Don't bold every proper noun or acronym.
19. **Inline-header lists.** The tell is a bold label and colon that restates the line: "**Performance:** Performance improved...". Convert those to prose. A bold lead-in that ends in a period, names the item, and is followed by genuinely new detail ("**Schema in TypeScript.** Tables live in one file.") is fine, not a tell.
20. **Title case headings.** Use sentence case.
21. **Decorative emojis.** Remove from headings and bullets.
22. **Curly quotes.** Replace with straight quotes.
23. **Hyphenated pairs everywhere.** Keep the hyphen before a noun ("a high-quality report"), drop it after ("the report is high quality").
24. **A heading whose first sentence only repeats the heading.** "## Installing the CLI" followed by "This section covers installing the CLI." Delete that sentence and start with the content.

### Communication artifacts

25. **Chatbot phrases.** "I hope this helps!", "Let me know if...", "Of course!", "Certainly!", "Found the smoking gun!" Remove.
26. **Cutoff disclaimers.** "While specific details are limited..." Find sources or remove.
27. **Sycophantic tone.** "Great question! You're absolutely right!" Respond directly.
28. **Fake-candid openings.** "Honestly?", "Look,", "Here's the thing", "Let's be honest" used as a staged pause before an ordinary point. The same word inside a sentence is fine; the standalone opener is the tell.
29. **Announcing the next point.** "Let's dive in", "here's what you need to know", "quick note", and the casual form "one thing that bit me". State the point instead.

### Filler

30. **Filler phrases.** "In order to" becomes "To". "Due to the fact that" becomes "Because". "It is important to note that" gets deleted.
31. **Excessive hedging.** "could potentially possibly be argued that it might" becomes "may".
32. **Generic conclusions.** "The future looks bright." State specific plans or facts.

### Jargon

33. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness (as metaphor), surface (as in "API surface"), bedrock, scaffolding (as metaphor), modality, paradigm, gold-plating, ratchet (as metaphor), evacuate (for moving code), endgame, north star, flywheel. These read as technical but usually have a plainer concrete word. "Substrate" becomes "base". "Wedge in" becomes "add". "Vector" becomes "way" or "method". "Gold-plating" becomes "more than the job needs". "Ratchet" becomes the mechanism's real name or "a limit that only tightens". "Evacuate" becomes "move out". "Endgame" becomes "the last phase". Pick the concrete word.
34. **Fake deep truth.** "at its core", "the real question is", "fundamentally", "what really matters", "the deeper issue". The framing promises depth the sentence does not deliver. State the ordinary point.
35. **Formulaic sayings.** "X is the Y of Z", "the currency of", "the architecture of". Replace with the specific claim: "the currency of attention" becomes what is actually being traded.

### Plain speech

36. **Say what it does, not how it feels.** "the database stays close at hand", "SQL you can read", "types that follow your schema" name a feeling. The fix names the mechanism or a number: "`.toSQL()` returns the exact string sent to the database", "a column rename fails the build". Ask what the sentence tells the reader to do or know, then write that. If you can't restate it as a concrete instruction, fact, or number, cut it. One more check: if the sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.
37. **Shorten or split dense sentences.** If the reader has to backtrack to parse a sentence, break it in two or drop clauses. One idea per sentence.
38. **Active voice.** Prefer it. Catch "is/are/was/were + past participle" and name the actor: "queries are validated" becomes "the compiler validates queries", "the file is parsed by the loader" becomes "the loader parses the file". Catch the missing subject too: "No configuration file needed." becomes "You do not need a configuration file." Passive is fine only when the actor is unknown or genuinely doesn't matter.
39. **Cut adverbs, or use a stronger verb.** "runs quickly" becomes "is fast" or the number. "significantly improves" becomes the measured delta. An adverb propping up a weak verb means the verb is wrong.
40. **Prefer the plain word.** "utilize" becomes "use", "leverage" becomes "use", "facilitate" becomes "help", "numerous" becomes "many", "in the event that" becomes "if". The fancier synonym is rarely clearer.
41. **Forced punchlines and dramatic fragments.** A row of two-word sentences written for effect. "It worked. Mostly. Until it didn't." One short sentence for emphasis is fine; a row of them is the tell.

## What not to flag

None of these is evidence that a machine wrote the text. Judge the piece, not one feature of it.

- Perfect grammar, correct spelling, and consistent style.
- A mix of casual and formal register in one piece.
- Dry, plain writing that carries none of the specific tells above.
- Formal or academic words that are not on the AI-vocabulary list in pattern 10.
- A salutation or a sign-off.
- One transition word ("however", "moreover") on its own.
- Curly quotes on their own. A word processor inserts them.
- One em dash on its own.
- One short sentence used for emphasis.
- Repeated sentence openings used deliberately for rhythm.
- Real limits, legal notices, and named objections. A stated caveat is content, not a defense against an invented critic.
- Real alternatives weighed in a design document or a tutorial, where each option is answered rather than dropped.
- A claim with no source. That is a research problem, not a style tell.
- Clean formatting, headings, and lists.
- A watched phrase inside a quotation, a title, a proper name, or an example that discusses the phrase instead of using it.

One tell proves nothing. Several together are evidence.

Pattern 16 still bans em dashes in prose we write ourselves. That is the stricter rule for our own
text; this list applies when judging whether text someone else wrote is machine-written.

## Keep the author's own voice

Removing the tells must not flatten what the author actually wrote. Keep:

- Specific, unusual details: a real number, a named tool, the odd edge case they hit.
- Mixed feelings and unresolved tension. Not every paragraph has to resolve.
- Dated or era-bound references.
- Genuine asides and self-corrections.
- Variety in sentence length.

This is the mirror of the rule in Boundaries. Do not add a voice the author did not write, and do
not delete the voice they did.

## Boundaries

Prose only, written for other people to read. A request aimed at Claude's own chat replies
("humanize your responses", "remove the AI tells", "stop writing like an AI") belongs to
`clear-and-short`, which owns their length, wording, and tells. Preserve meaning, facts, numbers,
file paths, identifiers, and established technical terms. Match the intended tone of the piece; do
not add opinions or first-person voice the author did not write. When a rule conflicts with a
project style guide (for example a house rule on heading case), the project style guide wins.

Adapted from the `unslop` skill in `cursor/plugins` (`pstack`, MIT, © 2026 Lauren Tan): all 31 of
its patterns are kept; the "Adding soul" section (opinions, first person, deliberate mess)
is dropped because it conflicts with the plain-facts writing style used across this catalog.
Ten patterns (7, 8, 9, 23, 24, 28, 29, 34, 35, 41), the three pattern extensions (12, 14, 38), and
the "What not to flag" and "Keep the author's own voice" sections are adapted from
[`blader/humanizer`](https://github.com/blader/humanizer) (MIT, © 2025 Siqi Chen), whose list comes
from [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing).
Its "Add personality only when it fits" section is dropped for the same reason upstream's "Adding
soul" was.
