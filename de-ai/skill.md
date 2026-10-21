---
name: de-ai
description: Strip AI-style noise from a codebase and its git history. Removes implementation narration, comments that restate the code, "now we..." walkthroughs, section banners, edit-history notes, and signature-restating docstrings while keeping comments that explain *why*. Also writes short Conventional Commits messages and safely rewords wordy AI-generated ones. Use this whenever the user says "de-ai", "de-slop", "clean up comments", "remove narration", "too many comments", "fix my commit messages", "commits are too long", "this reads like AI wrote it", or asks to tidy AI-generated code or commits, even if they only point at a single file, diff, or branch.
---

# De-AI

Code written by language models tends to talk to itself. It announces what the next line does, labels every block, and leaves notes about what it just changed. None of that helps the next reader: the code already says *what* it does, and the noise buries the few comments that actually matter.

The goal of this skill is code where comments are rare, and therefore worth reading when they appear. Behavior never changes — this is a comment-and-docstring pass, not a refactor.

The same habit shows up in git history: commit messages that recap the whole diff in bullets and end with a paragraph about maintainability. This skill covers those too. **For anything involving commit messages — writing new ones or rewording existing ones — read `references/commit-messages.md` first.** Rewording history has real risks, and that file covers how to do it safely.

**Never add AI or agent attribution** — no `Co-Authored-By: Claude`, no "Generated with…" footer, in commits or PR descriptions. The user is the author and is accountable for the code. When rewording existing commits, remove any such lines.

## The core test

For every comment, ask: **would a competent engineer reading this code for the first time lose anything if it vanished?**

A comment survives only if it carries information the code cannot express: intent, a constraint, a hazard, a reason something non-obvious is the way it is. If the answer is "no, the code already says that," delete it.

## Remove

**Narration** — describes what the next line does.
```python
# Loop through the users
for user in users:
    # Check if the user is active
    if user.is_active:
        # Add the user to the result list
        result.append(user)
```
Delete all three. The code is the description.

**Step labels and walkthroughs** — `# Step 1: Validate input`, `// First, we fetch the data`, `// Now we transform it`, `// Finally, return the result`. If a function genuinely has phases that need labels, that's a sign it wants to be split into named functions — mention it to the user rather than doing it.

**Section banners** — `# ===== Helper Functions =====`, `// --- Imports ---`, `/* Constants */` above a block of obvious constants.

**Edit history** — `// Changed to use async`, `# Fixed bug where X`, `// Updated per review`, `# New implementation`, `// Removed old logic`. That belongs in version control.

**Restated types and signatures** — docstrings and JSDoc that repeat what the signature already says:
```ts
/**
 * Gets the user by ID.
 * @param id - The ID of the user.
 * @returns The user.
 */
function getUserById(id: string): Promise<User>
```
Delete the whole block.

**Hedging and chatter** — `// This should work`, `# Hopefully this handles edge cases`, `// Simple helper function`, `// Note: this is important`, `// IMPORTANT:` with nothing important after it.

**Obvious return/assignment notes** — `return result  # Return the result`, `count = 0  # Initialize counter`.

**Commented-out code** — delete it; git remembers. Exception: if it's clearly a deliberate toggle the team uses (e.g., a debug config block with an explanation), leave it and mention it.

**Placeholder TODOs** — `// TODO: add error handling` with no owner, ticket, or specifics, especially ones the model left behind. Keep TODOs that reference a ticket or describe a concrete known gap.

## Keep

- **Why, not what**: `# Stripe retries webhooks for 72h, so this must be idempotent.`
- **Non-obvious constraints and hazards**: ordering requirements, thread-safety notes, "don't reorder — X depends on Y running first."
- **Workarounds** with context: `// Safari <17 fires resize twice; debounce. See https://…`
- **Surprising choices**: why the obvious approach wasn't used. `# Linear scan beats a dict here; n is always < 8.`
- **Tool directives**: `eslint-disable`, `# type: ignore`, `# noqa`, `@ts-expect-error`, `//go:generate`, `# pragma`, `#region` if the editor relies on it, shebangs, encoding lines. Never touch these.
- **License and copyright headers.**
- **Public API documentation** where the project documents its public surface (library exports, generated docs, OpenAPI annotations). Trim it to what the signature doesn't already say — behavior, errors raised, units, edge cases — but don't delete docstrings a docs pipeline depends on.
- **Regex, bit-twiddling, and math** where a one-line explanation saves real decoding effort.

## Trim rather than delete

Many AI comments bury one useful clause in three sentences of filler. Cut to the clause.

Before:
```python
# Here we are going to sort the items by their timestamp. We need to do this
# because the API returns them in an arbitrary order, and the downstream
# consumer expects them to be chronological.
items.sort(key=lambda i: i.timestamp)
```
After:
```python
# API returns items unordered; consumers expect chronological.
items.sort(key=lambda i: i.timestamp)
```

## When a comment is compensating for a bad name

Sometimes narration exists because the code is unclear: `x = get()  # the user's pending invoices`. The right fix is a better name, not a better comment. Rename freely when the identifier is local (a variable inside a function, a private helper used in one file). For anything exported, public, or used across files, leave it and list it for the user instead — renames ripple.

## Workflow

1. **Establish scope.** If the user named files, a directory, or "my changes," use that. "My changes" means the diff against the base branch (`git diff main...HEAD` or the staged/unstaged diff). If they said "the codebase" and it's large, start with the directories they're most likely to care about and confirm before sweeping everything.
2. **Check project conventions.** Skim `CONTRIBUTING`, `CLAUDE.md`, lint configs (e.g., rules requiring JSDoc on exports, `pydocstyle`, `missing-docstring`), and a few human-written files. If the project mandates docstrings, trim them instead of deleting. The project's rules beat this skill's defaults.
3. **Edit file by file.** Apply the Remove/Keep rules. Remove blank lines left orphaned where a comment used to be, but don't reflow or reformat surrounding code.
4. **Verify nothing but comments changed.** Review the diff: every removed line should be a comment, docstring, or the blank line it left behind, plus any deliberate local renames. Be careful with things that look like comments but aren't — `#` inside strings, URLs, shell heredocs, Markdown in string literals, `/*` in regexes, Python docstrings that are the only statement in a block (deleting them leaves an empty body; replace with `pass` or `...`).
5. **Run the formatter, linter, and type checker.** The diff is comment-only, so they are enough to show the files still parse; skip the test suite unless the diff includes a rename.
6. **Report briefly.** Say roughly how many comments were removed and trimmed, and list anything you deliberately left for the user to decide: exported names that deserve renaming, functions whose step labels suggest they should be split, commented-out code that looked intentional.

## Writing new code and commits

While this skill is active, hold your own output to the same standard: no narration, no step labels, no edit-history notes. Write a comment only when it passes the core test. When you commit the de-ai changes themselves, `style: remove redundant comments` is enough — no body needed.
