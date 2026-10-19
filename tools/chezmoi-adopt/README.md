# chezmoi-adopt

Keep declared directory trees fully tracked by chezmoi. Register a directory as
an *adopted root* with an encryption policy, and new files under it get added
with the right encryption — so a new Claude skill, `.bashrc.d` script, etc. is
never silently missed.

See [SPEC.md](SPEC.md) for the full specification.

## Install

Auto-installed on `chezmoi apply` (the `run_onchange_*_pipx_chezmoi_tools`
installer picks up every `tools/*/` package). Manually:

```sh
pipx install ~/.local/share/chezmoi/tools/chezmoi-adopt
```

Usable as `chezmoi-adopt …` or `chezmoi adopt …` (chezmoi subcommand dispatch).

## Config

`~/.config/chezmoi-adopt.toml` (chezmoi-tracked; the mutating commands rewrite it
and re-add it to the chezmoi source). Quote `~` paths so the shell doesn't
expand them — the tool stores roots in portable `~/…` form regardless.

```toml
ignore = ["*.swp", "*~"]          # global ignore globs

[[root]]
path       = "~/.claude/skills"
encryption = "all"                # none | content | all
levels     = 0                    # 0 = unlimited depth

[[root]]
path       = "~/.bashrc.d"
encryption = "none"
levels     = 1
ignore     = ["scratch_*.bash"]   # root-scoped globs
```

## Commands

```sh
chezmoi-adopt add {none|content|all} [--levels N] DIR...   # register + adopt now
chezmoi-adopt                       # dry audit (no TTY) or interactive (TTY)
chezmoi-adopt --force               # adopt everything not ignored (no TTY)
chezmoi-adopt list ['*.md' ...]     # what's adopted (quote globs)
chezmoi-adopt ignore add PATTERN [DIR...]
chezmoi-adopt ignore remove PATTERN [DIR...]
chezmoi-adopt ignore list [DIR...]
chezmoi-adopt remove PATH...        # un-adopt a root (+ forget its files) / forget a file
```

- **encryption** — `none` = `chezmoi add`; `content` = `chezmoi add --encrypt`;
  `all` = `chezmoi-cryptpath to-encrypted-path` (hidden filename + content).
- Interactive reconcile prompts per new file/dir: **[A]dd / [I]gnore /
  i[G]nore-pattern / [s]kip / [q]uit**.

Testing tip: point `CHEZMOI_ADOPT_CONFIG` at a scratch file to try it without
touching your real config.
