# Chat type taxonomy

Canonical reference for classifying an aictx chat. Used by the post-exit
`__aictx_process_tidyitem` pass to set the `type:` tag and load the matching guidance
fragment into the chat's `./CLAUDE.md`.

Two independent axes:

- **`type:`** — kind of material (one value). Files `tool.md`, `concept.md`,
  `workflow.md`, `project.md`, `reference.md` are the guidance fragments.
- **`stage:`** — lifecycle. Omitted = durable (default). `incubating` = an idea
  space that will move to its own repo once real; see `incubating.md`.
  `incubating` is the only stage value — chats that are simply finished or
  retired get the `archived` tag (via the fzf manage view), not a new stage.

## Decision aid

1. About operating one named program/command/service? → **`tool`**
2. A recipe you'll re-run the same way? → **`workflow`**
3. Ongoing work on one specific entity/goal (an org, property, course, product)? → **`project`**
4. Settled facts/principles/docs you'll consult? → **`reference`**
5. One idea you're reasoning about (when to use, trade-offs)? → **`concept`**
6. Will it move to its own repo once real? → also mark **`stage:incubating`**

Borderline → pick the one matching what you'll mostly *come back for*. Unclear
→ leave `type:` unset.

## Discriminators (the confusable pairs)

- **tool vs workflow** — tool = one program; workflow = steps (often several
  tools) toward a recurring task.
- **concept vs reference** — concept = one idea you reason about; reference =
  a body of settled facts you consult.
- **project vs workflow** — project = history of *this one* effort; workflow =
  the reusable recipe.
- **project vs reference** — project is active and accrues decisions; reference
  is largely static.

## Examples (by current slug)

- `tool` — chezmoi, aerc, gcalcli, nnn-file-manager, docker-management
- `concept` — communication-channels, bash-history-details
- `workflow` — mail-triage, bokforing, check-feedback, debian-vm-install
- `project` — board-work, home-renovation
- `reference` — konsult-villkor, communication principles, course material
