---
name: chezmoi
description: Work with the local chezmoi dotfiles setup — its custom `crypt/` scheme (hides a file's name/path in git, not just content) and the `chezmoi-cryptpath` / `chezmoi-adopt` CLIs. Use for any chezmoi task - tracking/adopting a new dotfile, secret, or Claude skill/hook/bin script; encrypting, renaming, moving, or forgetting a managed file; changing a file's encryption state; or editing anything under `~/.local/share/chezmoi`. Also load after creating, moving or deleting any file under `~/.claude/skills`, `~/.claude/hooks` or `~/.claude/bin` — those roots are chezmoi-adopted, so a new file there is untracked until `chezmoi adopt` runs and an edited one is unsynced until `chezmoi re-add` runs.
---

# chezmoi setup

Source dir: `~/.local/share/chezmoi`. Encryption: age (identity
`~/.config/chezmoi/key.txt`, recipient in `.chezmoi.toml.tmpl`).
Standard chezmoi source naming applies (`dot_`, `private_`,
`executable_`, `encrypted_*.age`, `*.tmpl`).

The `chezmoi-ops` subagent does the mechanical work: adopting/tracking a
new file, renaming or moving a crypt-managed file, converting a file's
encryption state, forgetting an entry, listing what's managed. Delegate
those there. Keep inline: diagnosing a broken `crypt/` state, anything
touching `.hooks/`, template work, and any repair needing judgement.

A managed file is in one of three states:

| State | Source form | Content in git | Name/path in git |
|---|---|---|---|
| plain | `dot_foo` | visible | visible |
| encrypted | `encrypted_foo.age` | hidden | visible |
| crypt | `crypt/<id>.age` + `crypt/<id>.yaml.age` | hidden | hidden |

`crypt` is the custom scheme: git holds only a random-id blob pair; the
real source path lives in the encrypted `.yaml.age` sidecar and is
materialized locally by a hook (see Internals). Use `crypt` when the
filename/path itself is sensitive, `encrypted` when only the content is.
When unsure, use `crypt` — downgrading later is one command.

Two repo-local pipx CLIs do all the work (auto-installed on
`chezmoi apply`; `chezmoi cryptpath …` ≡ `chezmoi-cryptpath …` via
subcommand dispatch, same for `adopt`). **Both take target paths under
`$HOME`, never chezmoi source paths** — they resolve source paths
themselves, including through the `crypt/` indirection.

**Before operating on an existing file, determine its state** — crypt
commands only work on crypt-state files:

```sh
chezmoi cryptpath list-encrypted <parent-dir>   # listed → crypt
chezmoi cryptpath list-clear <parent-dir>       # '🔒 ' → encrypted; listed plain → plain
```

Listed by neither → unmanaged.

## chezmoi-cryptpath — single files

### Rename / move crypt-managed files

`mv` semantics of `/bin/mv` (multiple sources → existing dir):

```sh
chezmoi cryptpath mv ~/.config/foo ~/.config/bar
chezmoi cryptpath mv ~/.config/a ~/.config/b ~/.config/dir/
```

Moves the target and rewrites the entry's encrypted `dst` metadata.
Never plain-`mv` + `chezmoi re-add` a crypt-managed file — that desyncs
the metadata. Plain/encrypted-state files rename via the normal chezmoi
workflow instead (move target + `chezmoi re-add`, or rename in source).

### Convert between states

```sh
chezmoi cryptpath to-encrypted-path FILE...  # → crypt (adds FILE first if unmanaged)
chezmoi cryptpath to-encrypted FILE...       # → encrypted_*.age, clear path
chezmoi cryptpath to-unencrypted FILE...     # → plain
```

`to-encrypted-path` is the only way *into* crypt; the other two
downgrade out of it (crypt entry dropped, file kept at its clear source
path). `--pattern[1|2|3] P` on `to-encrypted-path` records
`remoteUrlPattern*` metadata for git `includeIf hasconfig:` templating
(e.g. `--pattern1 'remote.*.url:git@github.com:org/**'`; single file
only when any pattern flag is given).

### Inspect / maintain

```sh
chezmoi cryptpath list-encrypted [path]     # crypt targets, recursive (default: cwd or $HOME)
chezmoi cryptpath list-clear [path]         # clear-path targets; '🔒 ' = content-encrypted
chezmoi cryptpath forget FILE...            # drop crypt entry, keep target file
chezmoi cryptpath edit-meta TARGET|ID       # $EDITOR the metadata yaml (dst, remoteUrlPattern*)
chezmoi cryptpath use-existing-path FILE... # repair: repoint dst at existing alt-prefixed source path
```

## chezmoi-adopt — whole directories

Registers directory roots that must stay fully tracked, each with a
policy: `none` → `chezmoi add`, `content` → `chezmoi add --encrypt`,
`all` → crypt scheme. `--levels N` caps descent (0 = unlimited, 1 =
root's own files only); a root nested inside another governs its own
subtree. Config: `~/.config/chezmoi-adopt.toml` (chezmoi-tracked; the
tool rewrites and re-adds it itself).

`~/.claude/{skills,hooks,bin}` are adopted with policy `all` — after
creating anything there, run `chezmoi adopt` rather than converting
files by hand. Use `chezmoi cryptpath` directly only for files outside
adopted roots or to convert/move/forget existing entries.

```sh
chezmoi adopt add {none|content|all} [--levels N] DIR...  # register + adopt now
chezmoi adopt             # TTY: prompt per new file [A]dd/[I]gnore/i[G]nore-pattern/[s]kip/[q]uit
                          # no TTY: dry audit, changes nothing
chezmoi adopt --force     # non-interactive: adopt everything not ignored
chezmoi adopt list ['GLOB']
chezmoi adopt ignore {add|remove|list} [PATTERN] [DIR...]  # no DIR = global; never touches .chezmoiignore
chezmoi adopt remove PATH...   # file → chezmoi forget; exact root path → drop rule + forget its files
```

## Always verify after a mutation

Every one of these commands can leave the metadata and the working tree
disagreeing without saying so. After *any* add/adopt/move/convert/forget,
before reporting success:

```sh
chezmoi status                                  # expect: clean, or only intended entries
chezmoi cryptpath list-encrypted <parent-dir>   # crypt-state files
chezmoi cryptpath list-clear <parent-dir>       # plain + '🔒 ' encrypted
```

Report the state you actually observed, not the state the command
claimed. A file listed by neither is unmanaged — that is a failure, not
a no-op.

## If a command fails

- A `cryptpath` command reports the file isn't crypt-managed → the file
  is in a different state (see the state check above); use the normal
  chezmoi workflow, or convert with `to-encrypted-path` first.
- `chezmoi adopt remove DIR` rejected → `DIR` is inside a root, not the
  root itself; get the exact root path from `chezmoi adopt list`.
- Anything under `crypt/` looks inconsistent → run any chezmoi command
  and retry (see Internals); never hand-edit `crypt/`.

## Internals (debugging only)

`crypt/<id>.yaml.age` decrypts to `dst:` — the real source path, with
normal chezmoi prefixes — plus optional `remoteUrlPattern*`. The
`read-source-state.pre` / `edit.post` hook
(`.hooks/hidden_filenames.bash`) hard-links `<id>.age` to that path so
chezmoi sees an ordinary `encrypted_*.age` file, keeps every
materialized path out of git via `.git/info/exclude`, and regenerates
`crypt/.chezmoidata/` so templates can use
`{{ index .crypt "<id>" "targetPath" }}` etc. Desync symptoms (missing
materialized file, stale leftovers, missing `.crypt.<id>` data) fix
themselves on the next chezmoi run, which re-triggers the hook — never
hand-edit under `crypt/`.

Repo-internal conventions (systemd unit gating, template helpers, lint)
are documented in the source repo's own CLAUDE.md.
