# git mechanics for adversarial-review

Read this before the first fixup (§7) and before the per-commit walk (§8).
Rewriting git history needs explicit authorization in the current session
(SKILL.md §8). Creating fixup commits does not; squashing them does.

## Reverting a failed fix

`git restore <paths>` discards edits to tracked files, but it does not remove
files the fix created. Run `git status --porcelain`, delete the new files that
belong to the fix by name, and check again. Avoid a blanket `git clean`: it also
deletes the user's own untracked files.

## Finding the originating commit

For each hunk of the fix, find the commit in the stack that last touched those
lines:

```
git blame <base>..HEAD -L <start>,<end> -- <path>
```

Lines older than `<base>` show a `^` prefix, meaning the defect predates the
change. Report that instead of fixing it inside the stack. For added lines, blame
the neighbouring lines and use judgement, since the right home is the commit
that introduced the code being fixed, not whichever one touched the line above.
If `git absorb` (third-party) is installed, it automates this, but review its
choices the same way.

A fix whose hunks belong to different commits needs one fixup commit per
target. Stage selectively with `git add -p`.

## Absorbing a fix

1. `git commit --fixup=<sha>` per target commit.
2. Once the user has authorized the rewrite, squash them all in one pass:

   ```
   GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <base>
   ```

3. `git log --oneline <base>..HEAD` — confirm no `fixup!` commits remain and the
   stack shape is as expected. If the rebase stops on a conflict, resolve it or
   `git rebase --abort` and report.

Until authorization, leave the fixups in place and say so in the report. They
are correct and green, but not yet "applied" in the SKILL.md §7 sense.

## Per-commit walk (§8)

Read-only form, always allowed:

```
for sha in $(git rev-list --reverse <base>..HEAD); do
  git checkout --quiet "$sha" && <baseline cmd> || echo "FAILED at $sha"
done
git checkout <branch>
```

Delete any artifacts the runs left behind before returning to the branch. If the
working tree was dirty, stash first, because `git checkout` will refuse or carry
changes along.

With authorization, `git rebase -x '<baseline cmd>' <base>` does the same walk
in one command and stops at the first failing commit. When every commit already
sits on `<base>` it replays them unchanged and hashes stay the same, but it is
still a rebase, so it follows the same authorization rule.
