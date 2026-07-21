# Chat directory

This directory holds one conversation with Claude. Files here are the
conversation's working memory: notes, summaries, references, examples, code —
anything worth keeping so the thread can be resumed later.

## Standard files

- `.aictx` — metadata. Line 1: space-separated lowercase tags. Line 2: one-sentence summary.
- `CLAUDE.md` — per-chat instructions, layered on top of `../CLAUDE.md` (shared).
- `README.md` — this file. Describes what each file in the directory is for.

## Topic files

As the chat produces material worth keeping, Claude adds files here and lists
them below with a one-line description. Naming convention:

- A CLI tool or program → `<program>.md`
- A single concept → `<concept>.md`
- Multiple subjects → one file per subject

<!-- claude: keep the list below in sync with the files in this directory -->

(no topic files yet)
