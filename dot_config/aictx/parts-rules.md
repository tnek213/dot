Rules for tracking a chat's **parts** and proposing/executing **splits**. Two
callers include this file: the exit-pass parts evaluation (`__aictx_eval_parts`,
maintains `parts.md` + proposes splits) and `aictx-split` (executes a confirmed
split). Sections below are labelled by which caller they serve.

## What is a part

A **part** is a coherent sub-thread of the chat — a distinct task, question, or
topic with its own arc (the thing you'd give a heading). Derive parts from the
chat's durable **files** (README, topic `.md` files, code), not from the raw
conversation. Aim for a handful per chat; merge trivially-related threads. Not
every message is a part.

Each part has a status:

- **open** — still being worked, or has unresolved next steps.
- **closed** — concluded: decided, shipped, or abandoned; no pending action.

## Maintaining `parts.md` (parts-eval caller)

Create/update `parts.md` in the chat dir. Format — a flat list, status tag
first so a human can flip it in place and a machine can parse it; open items
sorted before closed:

```markdown
# Parts

Sub-threads in this chat. `[open]` = active · `[closed]` = concluded.
Maintained by the exit pass; edit freely.

- [open] <short-title> — <one-line current state>. files: <a.md, b.md>
- [closed] <short-title> — <one-line outcome>.
```

Rules:

- **Add** parts that have newly emerged in the chat's files.
- **Flip** a part to `closed` when the content shows it concluded/abandoned.
- Keep each description to **one line**, reflecting the *latest* state.
- The `<short-title>` is the part's id (used by splits) — keep it stable.
- **Don't churn** wording, reorder needlessly, or re-open closed parts on
  borderline signals.
- Do **not** manage the `<!-- parts-eval: ... -->` marker — the command sets it.

## Split trigger (parts-eval caller)

After updating `parts.md`, decide whether the chat has grown hard to track.
Flag a split when **any** of these applies:

- there are **≥ 5 open parts**, or
- the open parts span **clearly unrelated** topics (low cohesion), or
- the chat's scope has **drifted across subjects** (see below).

Borderline on the first two → don't flag. Closed parts alone never trigger a
split. Scope drift is not borderline: when the signal below is present, flag
it — don't downgrade because the parts share a tool or domain.

**Scope drift across subjects.** A chat founded on one specific subject (one
machine, one product, one document, one association/client) that has grown a
second body of work centred on a *different* subject is structurally two
chats. Treat each distinct concrete subject the chat now acts upon as its own
candidate child, even if the tooling overlaps. Shared *tools* (Ansible, Bash,
chezmoi) and shared *domains* (sysadmin, mail, dotfiles) do not make two
subjects one chat — the subjects are the things being acted upon, not the
tools used.

**Detecting scope drift — be literal, not impressionistic.** Before
concluding "all parts share the founding subject", inspect each open part's
description and files for explicit *target indicators*: host groups, host
classes, additional machines, products, recipients, environments. If any
open part names targets the founding subject does **not** include, that is
scope drift — flag it. Don't override that signal with a high-level vibe
("the chat is *about* X") when the part's own text lists other targets.

Multi-host config-management infrastructure (Ansible roles, playbooks, group
inventories, host-group `site.yml`s) that operates on more than the founding
subject is **its own subject**, not part of the founding one — even when
some of its roles happen to apply to the founding subject too.

Example — `debian-server-containers-backup` was founded on one PN41 home
server (containers + backups). It now contains Ansible roles plus a
`site.yml` covering `servers/laptops/gaming` host groups, with dedicated
`gnome` and `gaming` roles for the laptop and gaming hosts. The
`os-install` part's own description lists those host groups. That is scope
drift even though "Ansible" and "Debian" sound related to "Debian server":
the targets are different machines. Split into a chat for the PN41 server
(founding subject, with its containers/backup/hardware threads) and one for
the Ansible cross-machine workflow (with the OS-install/roles/site.yml
threads).

If triggered, append (or refresh) a `SPLIT-SUGGESTED` block at the end of
`parts.md`. If not triggered, **remove** any stale block and add nothing —
do not write a sentence noting that no block was added. (Same for the merge
block below.) The block must be a real `## SPLIT-SUGGESTED` heading, never
prose mentioning the term. Format:

```markdown
## SPLIT-SUGGESTED (<YYYY-MM-DD>)

This chat is hard to track. To split it, run `aictx-split <this-slug>`.

- → `<child-slug-a>`: parts [title1, title2] — <why these group together>
- → `<child-slug-b>`: parts [title3] — isolated
```

Group open parts by cohesion: each cohesive cluster → one child; a part that
fits nothing else → its own child. Parts not listed stay in the parent. Choose
each `<child-slug>` per the slug rules in `slug-rules.md`, and avoid collisions
with the existing slugs you're given.

## Merge trigger (parts-eval caller)

After the split decision, consider the inverse: should this chat **merge** with
a sibling? Using the workspace overview (and reading a sibling's `parts.md` /
files when its summary looks related), look for another chat whose **content
overlaps or directly continues** this one's — two chats that are really one
thread, or one body of work, split apart.

Merge is **propose-then-confirm**, so bias toward *proposing*. A wrong suggestion
costs only a glance-and-decline; a missed one leaves the workspace sprawling. You
don't need certainty — if two chats clearly share the same subject and their
content overlaps or one continues the other, suggest it and let the user judge.

- **Do suggest:** same subject, overlapping or continuing content — e.g. an
  `obsidian` chat on vault layout + an `obsidian-organization` chat on folder
  structure; a `beeper-matrix` chat + a `beeper-mcp` chat both about accessing
  Beeper programmatically.
- **Don't suggest:** same tool or topic *area* but genuinely distinct, parallel
  tasks — e.g. separate one-off `mail-*` chats (a lookup vs. drafting one email
  vs. a triage workflow), or unrelated `gnome-*` chats. Same area ≠ same thread.

**Small forks fold into the canonical chat.** A narrow problem/spike chat that
branched off a broader subject (e.g. `obsidian-git-problem` off `obsidian`)
should merge **into the bigger/canonical chat** — that chat is the `target`,
the fork is absorbed. This holds **even if the fork's problem is already
solved**: its conclusion (the config change, the lesson) is exactly what belongs
centralized in the main chat. A concluded fork is a reason to merge, not to skip.

**Propose from the absorbed side only.** Write the `MERGE-SUGGESTED` block in the
chat that should be *absorbed* (the fork / the narrower or lesser chat), pointing
`target:` at the canonical chat. A chat that is itself the natural recipient does
**not** propose — its forks will, each with their own block pointing at it. This
keeps one block per merge (no both-sides duplication) and lets a canonical chat
collect several fork-side proposals. If the two chats are genuinely co-equal with
no clear canonical, the one being evaluated may propose itself as absorbed.

A chat carries **at most one** of `SPLIT-SUGGESTED` or `MERGE-SUGGESTED`; if both
seem to apply, prefer the split (reduce first).

**Near-duplicate slug — investigate, don't assume.** If two slugs differ only
by a trailing number or minor suffix (e.g. `foo` / `foo2`), it *may* be a second
chat about the same subject (the first slug was taken) — or two genuinely
different things whose real names differ, where the number is part of the actual
name (a "2" can be real: "Brf Vikingen 2" is a distinct association from "Brf
Vikingen"). Decide from the **files/content**, not the slug or the summaries;
a summary may be imprecise in either direction. When unsure, leave them
separate. Suggest the merge only if the content clearly shows one same subject.

If found, append (or refresh) a `MERGE-SUGGESTED` block to this chat's
`parts.md`:

```markdown
## MERGE-SUGGESTED (<YYYY-MM-DD>)

This chat is tightly coupled with sibling chat(s). To merge, run
`aictx-merge <this-slug>`.

- target: `<target-slug>` — the chat that stays active (this one, a sibling, or a new slug)
- absorb: `<sibling-a>`, `<sibling-b>` — folded into the target, then archived
- why: <one line on the coupling>
```

## Executing a split (aictx-split caller)

Carry out the `SPLIT-SUGGESTED` block exactly. For each proposed child:

1. **Create the child dir** `<root>/<child-slug>` by copying the template
   (given as a path). Don't collide with an existing slug.
2. **Write its `.aictx`:** line 1 = `<today> <slug words as tags> origin:<parent-slug>`
   (add `type:<kind>` if obvious); line 2 = a one-sentence summary drawn from
   the child's parts.
3. **Move the files** mapped to the child's parts from the parent into the child
   (`mv`). **Closed parts travel with their cluster** — move a closed part's
   files into the child whose thread it belongs to (it's that thread's context).
4. **Seed the child's `parts.md`** with the parts it carries (open + their
   context closed parts). Omit the eval marker — the next exit pass sets it.
5. **Provenance in the child:** add a line at the top of its `README.md`:
   `Split from <parent-slug> on <today>; carries parts: <titles>.`

Then in the **parent**:

- Add/refresh a `## Splits` section in `parts.md`:
  `- <today> → \`<child-slug>\`: parts [titles]`
- Mark each moved part in the list, e.g. `- [closed→split] <title> → <child-slug>`.
- **Remove** the `SPLIT-SUGGESTED` block.
- **If the split leaves the parent with no reason to exist** — no content files
  and no remaining open parts — archive it: add the tag `archived` to its
  `.aictx` line 1. The `## Splits` block already records where everything went.

Keep both `README.md` files in sync with the files they now contain. Don't
duplicate content across parent and child — moved files leave the parent.

### No information loss (hard requirement)

The split must never destroy content:

- Move whole files with `mv` — never rewrite, summarise, truncate, or recreate
  a topic file or code file during the move. Bytes that leave the parent must
  arrive in the child **unchanged**.
- Every content file in the parent must end up in exactly one place afterwards:
  still in the parent, or moved into one child. **Never delete a content file.**
- The only text you *remove* is the `SPLIT-SUGGESTED` block in the parent's
  `parts.md`.
- The only files you may *rewrite* are the bookkeeping ones — `README.md`,
  `parts.md`, `.aictx`. Topic files and code are moved, never edited.
- If you're unsure which child a file belongs to, **leave it in the parent**.
  A misplaced-but-present file is fine; a lost file is not.

## Executing a merge (aictx-merge caller)

Carry out the `MERGE-SUGGESTED` block. Let **target** be the chat that stays
active and **absorb** be the chats folded into it.

1. If `target` is a new slug, create it from the template (like a split child)
   and write its `.aictx` (line 1: `<today> <slug words> [type:...]`; line 2:
   one-sentence summary). If `target` is an existing chat, use it as-is.
2. **Distil the fork's useful conclusions into the target** — don't bulk-copy.
   Edit the target's notes so they state how things *should* be (the correct
   end-state) with a short note on *why*, incorporating the fork's outcome. Drop
   the trial-and-error: troubleshooting steps, dead ends, "we tried X then Y" —
   none of that belongs in the target. A standalone topic the target doesn't
   cover at all can be brought in, but still as a clean statement, not a log.
   (The fork's full detail is preserved in its archive — step 4 — so be ruthless
   about keeping the target clean.)
3. Merge the parts: fold each absorbed chat's *concluded* threads into the
   target's `parts.md` as needed (drop the absorbed chats' SPLIT/MERGE blocks).
4. **Archive each absorbed chat, keeping its content.** Add `archived` and
   `successor:<target-slug>` to its `.aictx` line 1, and prepend one line to its
   `README.md`: `Merged into <target-slug> on <today>.` **Leave all its other
   files intact** — they are the preserved full record (the "branch history").
   The `archived` tag keeps it out of the everyday picker (out of sight).
5. **Bookkeeping in the target:** add a `## Merged-in` section to its `parts.md`
   (`- <today> ← \`<absorb-slug>\`: distilled into <where>`), remove the
   MERGE-SUGGESTED block, and keep `README.md` in sync.

**Think of it like a git branch merging into main.** The target is `main`; each
absorbed chat is a branch. Merging integrates the branch's changes into main and
brings main up to date, then the branch is closed — no work is lost, and main
reflects all of it.

**No information loss — of conclusions, not detail (the real invariant).** A
merge *changes* the target; that is expected. What must not be lost is the useful
**conclusions**: the facts, decisions, and correct end-states the fork arrived
at must be reflected in the target. Detailed history — how you got there, what
was tried and discarded — has no value in the target and should be dropped; the
target states how things *should* be, briefly why, and no more. (And the fork's
raw detail is retained in its archive regardless, so nothing is truly gone.)

For a solved fork (e.g. `obsidian-git-problem` → `obsidian`): weave its problem
**and** its solution into the target's central notes (e.g. the obsidian config),
so the canonical chat is genuinely up to date — not a loose, untouched copy
sitting beside the old notes. Record the thread as a `closed` part in the target.
