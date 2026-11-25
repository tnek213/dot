# chezmoi-adopt — CLI specification

Status: agreed design (v1), pending implementation.

## Purpose

Keep declared directory trees fully tracked by chezmoi. New files under an
*adopted root* are added automatically with that root's encryption policy, so
nothing is silently missed. It is run on demand — never by `chezmoi apply`.

Invoked as `chezmoi-adopt …`, or `chezmoi adopt …` via chezmoi's subcommand
dispatch.

## Concepts

- **Adopted root** — a directory registered with a policy; its subtree is kept
  tracked.
- **Policy** — `(encryption, levels)`.
  - **encryption**
    - `none` → `chezmoi add`
    - `content` → `chezmoi add --encrypt` (age content, clear filename)
    - `all` → `chezmoi-cryptpath to-encrypted-path` (hidden filename + content)
  - **levels** — descent depth (see below).
- **Nested root** — a root inside another root. It governs its own subtree; the
  parent stops at its boundary regardless of the parent's `levels`.
- **Ignore pattern** — a glob excluding paths from adoption. Stored in the tool
  config (below), **never** written into `.chezmoiignore` files. A path is also
  skipped if chezmoi itself ignores it (`chezmoi unmanaged` already filters
  those).

## `--levels N`

Maximum directory depth to descend when adding, counting files directly in the
root as depth 1.

- `0` (default) — unlimited (descend until a nested root or the leaves).
- `1` — the root's own files only; do not enter subdirectories.
- `2` — root + one level of subdirectories; etc.

Descent always stops at a nested root, which then applies its own policy —
regardless of the parent's `levels`.

## Configuration

Single TOML file, chezmoi-tracked, at `~/.config/chezmoi-adopt.toml`
(source `dot_config/chezmoi-adopt.toml`).

```toml
# Global ignore patterns — apply under every root.
ignore = ["*.swp", "*~", "*.tmp"]

[[root]]
path       = "~/.claude/skills"
encryption = "all"      # none | content | all
levels     = 0

[[root]]
path       = "~/.claude/hooks"
encryption = "all"
levels     = 0

[[root]]
path       = "~/.bashrc.d"
encryption = "none"
levels     = 1
ignore     = ["scratch_*.bash"]   # additional, root-scoped patterns
```

The tool reads and rewrites this file for the mutating commands (`add`,
`remove`, `ignore add/remove`). Because the file is itself chezmoi-tracked, the
tool re-adds it to the source after mutating it, keeping source and target in
sync.

## Commands

### `chezmoi-adopt add {none|content|all} [--levels N] DIR...`
Register each `DIR` as an adopted root with the given policy (updating the rule
if it already exists), then **immediately** adopt its current unmanaged,
non-ignored files up to `levels`. Every `DIR` must be an existing directory —
otherwise a usage error, and nothing is changed.

### `chezmoi-adopt remove PATH...`
- **File** → `chezmoi forget PATH` (removes from source, leaves the target
  file).
- **Root dir** → must be the *exact* registered root; a subdirectory of a root
  is rejected with a pointer to the owning root. Deletes the root's rule **and
  `chezmoi forget`s every file it manages under that tree**.

### `chezmoi-adopt list [PATTERN...]`
Show what is adopted, disregarding everything else.
- No args → every registered root with its policy.
- A managed **file** → shown if managed.
- A **directory** → the adopted roots at or under it, recursively, **roots only**
  (not their managed files), to highlight what has been adopted.
- **Patterns** (e.g. `'*.md'`) are interpreted by the tool and matched against
  managed files and adopted roots — quote them so the shell doesn't expand them
  first.

### `chezmoi-adopt ignore <list|add|remove> …`
- `ignore list [DIR...]` — list patterns for the given roots, or all roots +
  global when no `DIR` is given.
- `ignore add PATTERN [DIR...]` — add `PATTERN`, scoped to the given roots, or
  global when no `DIR` is given.
- `ignore remove PATTERN [DIR...]` — remove `PATTERN` from the given roots, or
  from the global list when no `DIR` is given.

### `chezmoi-adopt [--force]`  (no command — *reconcile*)
Walk every adopted root, honoring each root's encryption, `levels`, nested
roots, and ignore patterns, and handle each unmanaged, non-ignored entry.

- **Interactive (a TTY is attached):** prompt per entry —
  **[A]dd / [I]gnore / i[G]nore-with-pattern**.
  - *Add* — adopt it; a new subdirectory is added recursively per the governing
    root's `levels`.
  - *Ignore* — write an exact-path ignore entry to the config (scoped to the
    governing root).
  - *Ignore with pattern* — open the path prefilled for editing into a glob; on
    Enter the pattern **must** match the entry being ignored, otherwise it is an
    error and the [A]/[I]/[G] prompt is shown again.
- **No TTY + `--force`:** adopt every non-ignored entry.
- **No TTY, no `--force`:** dry audit — print what *would* be adopted, change
  nothing.

## Exit codes
- `0` — success, or nothing to do.
- `1` — runtime error.
- `2` — usage error.

## Examples
```sh
chezmoi-adopt add all ~/.claude/skills ~/.claude/hooks
chezmoi-adopt add none --levels 1 ~/.bashrc.d
chezmoi-adopt                       # dry audit (no TTY) or interactive (TTY)
chezmoi-adopt --force               # adopt everything not ignored
chezmoi-adopt list '*.md'
chezmoi-adopt ignore add '*.tmp' ~/.claude/skills
chezmoi-adopt remove ~/.bashrc.d    # un-adopt + forget its files
```

## Implementation notes
- Lives in `tools/chezmoi-adopt/` as a pipx-installed package (Python fits the
  TOML config, subcommands, interactive prompts, glob matching, and depth-aware
  walking).
- Primitives: `chezmoi unmanaged` (find untracked, already respects
  `.chezmoiignore`), `chezmoi managed`, `chezmoi add [--encrypt]`,
  `chezmoi forget`, and `chezmoi-cryptpath to-encrypted-path` for `all`.
- Operates on target paths under `$HOME`, like chezmoi itself.
- "Ignored" during a walk = chezmoi-ignored **or** matched by a governing
  root's global/root-scoped patterns.
