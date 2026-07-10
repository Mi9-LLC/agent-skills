# new-feature — Worked Examples

Full worked examples for the `new-feature` skill's category/question format. The inline example in `SKILL.md` is kept short so it loads on every run; this file holds the longer ones.

### Example — launch mechanism decision

After reading the relevant wrapper class and checking current Microsoft docs:

> ## Question 10 — Category B, launch mechanics
>
> **B1. Token flow.** Standard pattern:
> ```
> WTSQueryUserToken → DuplicateTokenEx(TokenPrimary) → CreateProcessAsUser
> ```
> **[REC]** This pattern. Alternative `CreateProcessWithTokenW` is simpler but needs SE_IMPERSONATE (LocalSystem has both; no practical difference). Sticking with CreateProcessAsUser matches the dominant pattern in Microsoft's session-isolation sample code.
>
> **B2. Environment block.** `CreateEnvironmentBlock(hToken, FALSE)`:
>   - (i) Call `LoadUserProfile` first. Heavy but complete for profiles not already loaded.
>   - (ii) **[REC]** Skip `LoadUserProfile` — user has a live session, profile is already loaded in HKCU, block build succeeds. Lighter, no cleanup path.
>   - (iii) System env only (null token). Missing HKCU-derived PATH and user-specific vars.

Every sub-item has enumerated options, one carries `[REC]` with a concrete reason. User can skim, agree, or redirect.
