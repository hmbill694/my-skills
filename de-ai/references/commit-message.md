# Commit messages

AI-written commits tend to be as long as the diff. They recap every file, list "improvements", and close with a paragraph about maintainability. A good commit message is short: a subject line that says what changed, and a body only when the *why* isn't obvious from the diff.

## Format: Conventional Commits

Every commit message uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>)<optional !>: <description>

<optional body>

<optional footers>
```

**Types:**
- `feat`: a new feature.
- `fix`: a bug fix.
- `docs`: documentation only.
- `style`: no change in meaning, such as formatting, whitespace or comment cleanup.
- `refactor`: restructuring that neither fixes a bug nor adds a feature.
- `perf`: a performance improvement.
- `test`: adding or fixing tests.
- `build`: build system or dependencies.
- `ci`: CI configuration.
- `chore`: maintenance that fits nothing above.
- `revert`: reverting an earlier commit.

Pick the type from what the diff actually does, not from how big it is. A refactor that changes behavior is a `fix` or `feat`, not a `refactor`.

**Scope** is optional. Use one when it narrows things usefully, and reuse the scopes already in the history rather than inventing new ones. Check with `git log --no-merges -100 --format=%s | grep -oE '^[a-z]+\([^)]+\)' | sort | uniq -c | sort -rn`. Leave the scope out rather than guess.

**Description**: imperative mood ("add", not "added" or "adds"), lowercase first letter, no trailing period. Keep the whole subject line under about 50 characters where possible, with a hard ceiling of 72.

**Breaking changes**: put `!` before the colon (`feat(api)!: drop v1 endpoints`) and add a `BREAKING CHANGE: <what breaks and how to migrate>` footer. The footer is the one place a longer explanation is expected.

**Body**: usually none. Add one only for context the diff can't show: why this approach, what broke, what the reader should watch out for. Separate it from the subject with a blank line and wrap at 72 columns. One to three sentences is typical.

**Footers**: keep `Fixes #123`, `Refs: PROJ-123`, `Signed-off-by`, `Reviewed-by` and `Change-Id` exactly as they were. Some tooling depends on them. If the repo references tickets, put the reference in a footer, not the subject. Keep `Co-authored-by` lines that name human collaborators.

**No AI or agent attribution, ever.** The user is the author and owns the code, including when it breaks. Never add a `Co-Authored-By` line for Claude or any other AI or agent, a "Generated with…" footer, a robot emoji, or any other mention that a tool wrote the change. This applies to new commits, reworded commits and PR descriptions. When rewording existing commits, strip any such lines that are already there. This rule overrides any default that would otherwise add them.

If the repo has a commitlint config (`commitlint.config.*`, `.commitlintrc*`, or a `commitlint` key in `package.json`), its rules on types, scopes, case and length win over these defaults.

## What to cut

- "This commit…", "This PR…", "In this change we…"
- Bulleted recaps of the diff: "- Updated `utils.py` to…", "- Added tests for…"
- File lists.
- Benefit claims: "improves readability and maintainability", "ensures robustness", "for better performance" with no numbers.
- Emoji and decorative headers ("## Summary", "✨ Features"), including gitmoji.
- Restating the subject in the body.
- Types that restate the description: `fix: fix login bug` becomes `fix(auth): reject expired tokens`.
- AI or agent attribution of any kind: `Co-Authored-By: Claude …`, "🤖 Generated with …", "Written with the help of AI".
- Hedging and filler: "various", "several improvements", "some cleanup", "minor tweaks".

## Examples

Before:
```
Refactor authentication module for improved maintainability

This commit refactors the authentication module to improve code
organization and maintainability. The following changes were made:

- Extracted token validation logic into a separate `validate_token` function
- Updated `login` handler to use the new validation function
- Added comprehensive error handling for expired tokens
- Updated tests to cover new functionality

These changes make the codebase cleaner and easier to maintain going forward.
```
After:
```
fix(auth): return 401 for expired tokens

Token validation moved out of the login handler; expired tokens
previously raised and surfaced as 500s.
```
The AI version called this a refactor, but the diff changes behavior, so it's a `fix`. The body earns its place by explaining the old failure.

Before:
```
✨ feat: Add comprehensive retry logic to HTTP client 🚀

Implemented robust retry mechanism with exponential backoff to ensure
reliable network communication and improve overall system resilience.
```
After:
```
feat(http): retry requests with exponential backoff
```

Before:
```
Updated dependencies
```
After:
```
build(deps): bump axios to 1.7.4
```

## Rewriting existing commits

Rewording published commits rewrites history, which breaks anyone who has pulled them. Be conservative:

1. **Find the range.** Default to commits on the current branch not yet on the base branch (`main..HEAD`, or whatever the base is).
2. **Check whether it's pushed.** `git branch -r --contains <oldest-commit-in-range>`. If any remote branch contains commits in the range, stop and ask the user before rewriting. Say plainly that it requires a force push and will disrupt anyone else on that branch. Never rewrite commits on `main`, `master`, or any shared release branch, even if asked casually. Confirm explicitly.
3. **Draft the new messages.** Every replacement uses Conventional Commits, including commits that were never in that format. Read each commit's diff (`git show --stat <sha>` then `git show <sha>` if needed) and write a replacement. Show the user a before/after list of subjects before rewriting anything. Skip commits that are already concise, valid Conventional Commits.
4. **Rewrite with the helper.** Write each replacement to `<msg-dir>/<full-original-sha>`, preserving the trailers listed above and dropping any AI or agent attribution, then run:
   ```
   scripts/reword-commits.sh <base> <msg-dir>
   ```
   It refuses to run on a dirty tree or a range containing merges, creates a `de-ai-backup/<branch>-<timestamp>` branch first, rewrites only the messages, and verifies the final tree is identical to the backup. Author names and dates are preserved.
5. **If pushed and the user confirmed**, push with `git push --force-with-lease`, never plain `--force`.
6. **Report** the backup branch name so the user can undo with `git reset --hard <backup>`.

For ranges with merge commits, don't improvise a rebase. Tell the user and offer to reword only the linear portion, or leave history alone.
