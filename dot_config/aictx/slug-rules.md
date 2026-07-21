Shared slug-tidy rules. The `__aictx_process_tidyitem` shell function includes this
file in the prompt it sends to Claude. Eligibility filtering, candidate
selection, and output format live in the caller — this file is rules only.

## Strong rename signals

When one of these applies, the rename is almost always clearly better
(overrides the "borderline → skip" default):

- **Obsolete name in the slug.** The slug references a program, tool, or
  solution that has since been renamed (e.g. `aichat-*` when the solution
  is now called `aictx`). Detect by checking whether the name still
  resolves: `command -v <name>` or `ls ~/Documents/aictx/<name>*`
  returning nothing, or by reading the workspace CLAUDE.md for the
  current canonical name. Replace the obsolete name with the current one
  and keep the rest of the slug.
- **Verb-first sentence dump.** Slug starts with a generic verb
  (`improve`, `develop`, `fix`, `setup`, `do`) followed by what the chat
  is actually about. The dominant subject is usually one of the later
  words — promote it to main word, drop the verb.
- **Real-command exception triggers.** A real command/file with dashes
  exists (per the slug rules) and the current slug doesn't use it.

## Slug rules

A good slug:

- **Starts with a single main word** — no internal dashes in the first
  token. The main word is the dominant subject of the chat: usually a
  program name (`nnn`, `chezmoi`, `kitty`, `beeper`, `bash`, `claude`,
  `systemd`), or a common-purpose noun if the chat covers multiple tools
  with one shared purpose (`mail` for an email workflow across clients,
  `attendance` for filling attendance sheets, `calendar` for a calendar
  workflow). The main word makes chats about the same thing sort next to
  each other under `ls ~/Documents/aictx/`.

  **Exception — real command or filename:** if the chat is centred on a
  specific command that exists on PATH or a specific file that exists in
  the chat dir, and that command/file's name contains dashes, the whole
  name (dashes and all) is the main word. The dash-free rule only applies
  when you're picking a label; a real identifier wins over a stylistic
  rule. To confirm a candidate main word is a real command, check with
  `command -v <name>` or look for `<name>.py`/`<name>.sh` etc. in the
  chat dir. Examples: `serve-file` (a script in the chat dir on PATH),
  `claude-project` (CLI at `~/.local/bin/claude-project`).
- Has **0–3 clarifying words** after the main word, dash-separated, in
  order of specificity. Two words is often enough.
- Is **lowercase ASCII** with single dashes. No underscores, no double
  dashes, no trailing dashes.
- Contains no filler — drop `for`, `and`, `the`, `with`, `etc`, `using`,
  `about`. They add length, not information.
- Total length **≤ 5 words**, usually 2–3.
- Does **not** collide with any existing slug under `~/Documents/aictx/`.

When two candidate main words are roughly equal in dominance, prefer the
one that already groups well with other chats in the workspace — the
purpose of a stable main word is consolidation, not novelty.

When borderline, leave the slug alone. "Different and maybe nicer" is not
enough; the new name must be clearly better.

## Examples

**Clear rename** —
`beeper-for-sms-fb-msg-lnk-msg-x-msg-etc` → `beeper-matrix`
The summary names Beeper using the Matrix protocol; the long original is a
sentence dump with filler (`for`, `etc`) and abbreviations. `beeper` is the
obvious main word; `matrix` is the one clarifying word that matters.

**Clear rename, common-purpose main word** —
`improve-check-feedback` (hypothetical: chat is about iterating on email
reply prompts) → `mail-feedback-tuning`
`check` isn't a real tool name and adds nothing; the dominant subject is
mail workflow.

**Borderline skip** —
`android-sms-from-cli` → would consider `sms-android-cli`, but neither
ordering is obviously better and the existing slug is already short and
clear. Skip.

**Clear skip** —
`nnn-file-manager` — already main-word-first, two clarifiers, accurately
labelled. Don't touch.

**Clear skip** —
`bash-history-details` — main-word-first, descriptive. Don't touch.

**Rename to a real command name** —
`simple-cmd-expose-file-http` → `serve-file`
The chat produced a real script `serve-file.py` in the chat dir (and on
PATH as `serve-file`). The command name *is* the main word — its dashes
are part of the identifier, not stylistic. No clarifier is needed because
the command name is already specific.

## How to rename (per chat)

For each chat you've decided to rename, do **exactly** this:

1. Compute the new slug. Verify `~/Documents/aictx/<new-slug>` does not
   exist (`test -e ...`). If it does, skip this chat — don't pick a
   slightly-different alternative.
2. Run `claude-project move ~/Documents/aictx/<old-slug>
   ~/Documents/aictx/<new-slug>`. This handles both the on-disk rename and
   the Claude project-state migration (renames
   `~/.claude/projects/<old-slug-slug>/` and rewrites `"cwd":"…"` inside
   every transcript). Do **not** rename the directory any other way.
3. Edit `~/Documents/aictx/<new-slug>/.aictx`:
   - **Line 1:** keep the leading creation-date tag (the first
     YYYY-MM-DD token). Then list the new slug's words (dashes → spaces),
     one tag per word. Preserve any tags from the original line 1 that
     were not slug-derived (i.e. extra topic tags the user added later
     beyond the slug). Don't change the date tag.
   - **Line 2:** leave the summary alone. Only rewrite it if it's clearly
     wrong (describes the wrong subject); if you do rewrite, keep it to
     one short sentence and don't expand the scope.

## Reading context for a candidate

For each candidate slug `<slug>` you evaluate, sample cheaply:

- `~/Documents/aictx/<slug>/.aictx` — line 1 tags, line 2 summary.
- `~/Documents/aictx/<slug>/README.md` if present — curated topic list.
- The first 50 lines of the most recently modified jsonl under
  `~/.claude/projects/-home-kent-Documents-aictx-<slug>/`. Don't read
  entire transcripts; the opening usually pins the topic.

## Forbidden

- Do **not** rename anything outside `~/Documents/aictx/<slug>/`.
- Do **not** call `claude-project consume` or `claude-project purge`.
- Do **not** touch `.template`, `.last`, the root `CLAUDE.md`, or any
  per-chat `CLAUDE.md`.
- Do **not** create new files. Editing `.aictx` is the only write.
- Do **not** delete anything.
- Do **not** prompt the user. Headless runs have no one to answer.
