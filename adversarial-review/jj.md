# jj mechanics for adversarial-review

Read this before the first absorb (§7) and before the per-commit walk (§8).

## Stray files

jj snapshots every untracked, non-ignored file into the working-copy change `@`
on the next jj command. Test runs, builds, and scratch scripts all create such
files. Anything in `@` when you absorb or squash travels with the fix, and
anything in a probe change keeps that change alive. Run `jj status` before every
absorb and after every test run, and delete or ignore what doesn't belong.

## Immutable commits

jj refuses to rewrite commits in `immutable_heads()` (by default trunk, tags,
and untracked remote bookmarks). If absorb or squash fails for that reason, the
target commit is not the user's to rewrite without discussion: stop, report the
fix as blocked, and ask. Do not pass `--ignore-immutable` on your own.

Commits on a tracked remote bookmark are mutable but already pushed. Rewriting
them means a force push later, so treat them as needing explicit authorization
(SKILL.md §8).

## Reverting a failed fix

`jj undo` reverses the last operation. If the fix was never committed and is
still only in `@`, `jj restore <paths>` discards it. Confirm with `jj status`.

## Absorbing a fix

Work from an empty change on top of the stack (`jj new <tip>` if `@` is not
already one). Then:

1. `jj status` — clear stray files first (see above).
2. `jj absorb` — each hunk moves to the nearest mutable ancestor that last
   modified those lines.
3. `jj op show -p` — read where each hunk landed. Absorb places hunks by
   *neighbouring* lines, so an added line next to old code lands in whichever
   commit last touched the neighbour, which may be the wrong one. Move a
   misplaced hunk with `jj squash --from <wrong> --into <right> <paths>`
   (add `-i` or a fileset if only part of a file should move). Move anything
   absorb left in `@` (a new file, an ambiguous hunk) with
   `jj squash --into <change-id> <paths>`.
4. `jj log -r '<base>..'` — confirm the stack shape and that no descendant
   shows `(conflict)`. Auto-rebase makes conflicts possible, not loud. If one
   appears, `jj undo` and place the hunks by hand instead.

`jj undo` reverses any of this if it went wrong.

## Per-commit walk (§8)

For each change in `jj log -r '<base>..<tip>'`, oldest first:

1. `jj new <change>` — creates a probe change on top of it.
2. Run the baseline.
3. `jj abandon @` — discards the probe along with any artifacts the run left in
   it. Do not rely on "moving away from an empty change abandons it": a test run
   that created untracked files makes the probe non-empty, and it would then
   stay in the repo as a stray child.

Finish with `jj new <tip>` and confirm with `jj log` that the stack is exactly
as it was before the walk, with no leftover probe changes.
