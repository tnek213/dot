---
name: chezmoi
description: Work with the local chezmoi dotfiles setup, its custom `crypt/` scheme (hides a file's name and path in git, not just its content) and the `chezmoi-cryptpath` and `chezmoi-adopt` CLIs. Use for any chezmoi task - tracking or adopting a new dotfile, secret, or Claude skill, hook, agent or bin script, encrypting, renaming, moving or forgetting a managed file, changing a file's encryption state, or editing anything under `~/.local/share/chezmoi`. Also load after creating, editing, moving or deleting anything under `~/.claude`, `~/.local/lib/agent-tools` or `~/.local/share/agent-tools`, and after changing files in the `~/ai` repo under `claude/dot_claude/` or `shared/dot_local/`, since those deploy into chezmoi-managed directories and must then be re-added, adopted or forgotten. VS Code settings have their own skill, `vscode-settings`.
---

# chezmoi setup

Follow the shared `PREFERENCES.md` protocol supplied by global agent instructions.

Source dir: `~/.local/share/chezmoi`. Encryption: age (identity
`~/.config/chezmoi/key.txt`, recipient in `.chezmoi.toml.tmpl`).
Standard chezmoi source naming applies (`dot_`, `private_`,
`executable_`, `encrypted_*.age`, `*.tmpl`).

Every chezmoi call, including read-only ones such as `chezmoi status`,
`chezmoi managed` and the `list-*` commands below, runs the crypt hook
and rewrites source state. Run chezmoi from one session at a time (see
[Files deployed from `~/ai`](#files-deployed-from-ai)).

The `chezmoi-ops` subagent does the mechanical work: adopting or
tracking a new file, renaming or moving a crypt-managed file, converting
a file's encryption state, forgetting an entry, listing what's managed.
Delegate those there, with explicit target paths. Run one `chezmoi-ops` at a time, and no inline chezmoi commands while it works. Keep inline:
diagnosing a broken `crypt/` state, anything touching `.hooks/`,
template work, the `cmp` and deploy check of the `~/ai` sync, and any
repair needing judgement.

A managed file is in one of three states:

| State     | Source form                              | Content in git | Name/path in git |
| --------- | ---------------------------------------- | -------------- | ---------------- |
| plain     | `dot_foo`                                | visible        | visible          |
| encrypted | `encrypted_foo.age`                      | hidden         | visible          |
| crypt     | `crypt/<id>.age` + `crypt/<id>.yaml.age` | hidden         | hidden           |

`crypt` is the custom scheme: git holds only a random-id blob pair. The
real source path lives in the encrypted `.yaml.age` sidecar and is
materialized locally by a hook (see Internals). Use `crypt` when the
filename or path itself is sensitive, `encrypted` when only the content
is. When unsure, use `crypt`, since downgrading later is one command.

Two repo-local pipx CLIs do all the work (installed by `chezmoi apply`,
but see the apply rule in [Files deployed from `~/ai`](#files-deployed-from-ai),
and report missing CLIs instead of running apply). `chezmoi cryptpath …` is the same as
`chezmoi-cryptpath …` through subcommand dispatch, and likewise for
`adopt`. **Both take target paths under `$HOME`, never chezmoi source
paths.** They resolve source paths themselves, including through the
`crypt/` indirection.

**Before operating on an existing file, determine its state.**
`mv`, `forget`, `edit-meta` and `use-existing-path` work only on
crypt-state files:

```sh
chezmoi cryptpath list-encrypted <parent-dir>   # listed → crypt
chezmoi cryptpath list-clear <parent-dir>       # '🔒 ' → encrypted, listed plain → plain
```

Listed by neither → unmanaged.

## chezmoi-cryptpath: single files

### Rename or move crypt-managed files

`mv` semantics of `/bin/mv` (multiple sources → existing dir):

```sh
chezmoi cryptpath mv ~/.config/foo ~/.config/bar
chezmoi cryptpath mv ~/.config/a ~/.config/b ~/.config/dir/
```

Moves the target and rewrites the entry's encrypted `dst` metadata.
Never plain-`mv` and `chezmoi re-add` a crypt-managed file, since that
desyncs the metadata. To rename a plain or encrypted file, rename its
source file in the source dir (keeping the prefixes), or move the target,
`chezmoi forget` the old path and `chezmoi add` the new one with the same
state (`--encrypt` for encrypted). `re-add` alone does not pick up a new
path.

### Convert between states

```sh
chezmoi cryptpath to-encrypted-path FILE...  # → crypt (adds FILE first if unmanaged)
chezmoi cryptpath to-encrypted FILE...       # → encrypted_*.age, clear path
chezmoi cryptpath to-unencrypted FILE...     # → plain
```

`to-encrypted-path` is the only way _into_ crypt, and it also accepts
plain, encrypted and unmanaged files. The other two downgrade out of it
(crypt entry dropped, file kept at its clear source path).
`--pattern[1|2|3] P` on `to-encrypted-path` records `remoteUrlPattern*`
metadata for git `includeIf hasconfig:` templating (for example
`--pattern1 'remote.*.url:git@github.com:org/**'`, single file only when
any pattern flag is given).

### Inspect and maintain

```sh
chezmoi cryptpath list-encrypted [path]     # crypt targets, recursive (default: cwd or $HOME)
chezmoi cryptpath list-clear [path]         # clear-path targets, '🔒 ' = content-encrypted
chezmoi cryptpath forget FILE...            # drop crypt entry, keep target file (target may be gone)
chezmoi cryptpath edit-meta TARGET|ID       # $EDITOR the metadata yaml (dst, remoteUrlPattern*)
chezmoi cryptpath use-existing-path FILE... # repair: repoint dst at existing alt-prefixed source path
```

## chezmoi-adopt: whole directories

Registers directory roots that must stay fully tracked, each with a
policy: `none` → `chezmoi add`, `content` → `chezmoi add --encrypt`,
`all` → crypt scheme. `--levels N` caps descent (0 = unlimited, 1 =
root's own files only). A root nested inside another governs its own
subtree. Config: `~/.config/chezmoi-adopt.toml` (chezmoi-tracked, the
tool rewrites and re-adds it itself). `chezmoi adopt list` shows the
current roots.

`~/.claude/{skills,hooks,agents,bin}` are adopted with policy `all`.
After creating anything there, run `chezmoi adopt --force` rather than
converting files by hand, and never `adopt add` an individual skill
directory, since the skills root already covers it. Use
`chezmoi cryptpath` directly only for files outside adopted roots or to
convert, move or forget existing entries.

```sh
chezmoi adopt add {none|content|all} [--levels N] DIR...  # register + adopt now
chezmoi adopt --force     # non-interactive: adopt everything not ignored (use this from agents)
chezmoi adopt             # TTY: prompt per new file [A]dd/[I]gnore/i[G]nore-pattern/[s]kip/[q]uit
                          # no TTY: dry audit, adopts nothing (the hook still runs)
chezmoi adopt list ['GLOB']
chezmoi adopt ignore {add|remove|list} [PATTERN] [DIR...]  # no DIR = global, never touches .chezmoiignore
chezmoi adopt remove PATH...   # file → forget it, exact root path → drop rule + forget all its files
```

### Forget removed or renamed paths

Never widen a removal to an enclosing root: `chezmoi adopt remove` on a
root such as `~/.claude/skills` forgets every file under it. For a
removed directory, first check `chezmoi adopt list`. If the directory is
itself a registered root, `chezmoi adopt remove` that exact path.
Otherwise forget its files one by one, which works after the target is
gone. List them with a literal prefix match, not a regex:

```sh
chezmoi managed --path-style=absolute --include=files | awk -v p="$HOME/.claude/skills/OLD/" 'index($0, p) == 1'
```

Forget each listed file, or a single removed file, by its state: under
an adopted root `chezmoi adopt remove FILE...` (never the directory or
the root), otherwise `chezmoi cryptpath forget FILE...` for crypt state
and `chezmoi forget --force FILE...` for plain or encrypted.

## Files deployed from `~/ai`

The `~/ai` repo is the source of truth for `~/.claude` (from
`claude/dot_claude/`) and for `~/.local/lib/agent-tools` and
`~/.local/share/agent-tools` (from `shared/dot_local/`). Unison deploys
them, and chezmoi is a one-way mirror of what lands there. Never copy
back from chezmoi into `~/ai`. Unison syncs in both directions, so never
run `chezmoi apply`, `update`, `merge` or `edit` on these deployed
targets: a chezmoi write there would be carried back into `~/ai`. A bare
`chezmoi apply` or `update` also writes them, so apply only explicit
targets outside these directories.

After work in `~/ai`, sort the changed deployed paths into added,
modified and deleted, and do the following without asking per file:

1. Check the deployed side first. With `cmp`, check that each added or
   modified deployed copy matches the `~/ai` copy, and that each deleted
   path is gone from the deployed side. If not, deploy from `~/ai`
   first, from the repo root, with
   `python3 scripts/unison_sync.py --once --target T`, where `T` is
   `claude`, `shared` (`~/.local/share/agent-tools`) or `shared-tools`
   (`~/.local/lib/agent-tools`). It returns at once without syncing when
   a running watcher holds the lock, so then wait for one watcher cycle
   and check again. If it still differs, stop and report instead of
   copying by hand. Afterwards check `git status` in `~/ai` for changes
   unison carried back. Unison does not deploy `test_*.py`,
   `review.json`, `review-dependencies.json`, `skills/.trash` or
   `skills/synced`, so those have no deployed copy to check or re-add.
   `~/.claude/bin` is not deployed from `~/ai`.
2. Re-add modified files that chezmoi already manages:
   `chezmoi re-add FILE...`.
3. Adopt added files. Under the adopted roots run `chezmoi adopt --force`.
   Elsewhere add each file in the same state as its managed neighbours,
   checked with the list commands above, or as `crypt` when there are
   none.
4. Forget every deleted managed path, including the old paths of renamed
   skills, as described in
   [Forget removed or renamed paths](#forget-removed-or-renamed-paths).
   Do this only after step 1 confirmed the deployed copy is gone, or the
   next `adopt --force` adopts it again.

Run chezmoi from one session at a time. Each run triggers the crypt
hook, and concurrent runs leave duplicate keys in `crypt/.chezmoidata/`
and a stray `.git/info/exclude.next`. Before a run, check that
`pgrep -x chezmoi` finds nothing, and wait if it does. When several
sessions work on skills, one session does the chezmoi sync for all of
them at the end.

## Always verify after a mutation

Every one of these commands can leave the metadata and the working tree
disagreeing without saying so. After _any_ add, adopt, move, convert or
forget, before reporting success, check the result:

```sh
chezmoi status                                  # expect: clean, or only intended entries
chezmoi cryptpath list-encrypted <parent-dir>   # crypt-state files
chezmoi cryptpath list-clear <parent-dir>       # plain + '🔒 ' encrypted
```

Expected outcome per operation:

- add, adopt or convert: the file is listed in the intended state.
  Listed by neither means it is unmanaged, which is a failure.
- move or rename: only the new path is listed, the old one is gone.
- forget: the path is listed by neither, and the target file is still
  present unless it was already deleted.

Report the state you actually observed, not the state the command
claimed.

## If a command fails

- A `cryptpath` command reports the file isn't crypt-managed → the file
  is in a different state (see the state check above). Use the normal
  chezmoi workflow, or convert with `to-encrypted-path` first.
- `chezmoi adopt remove DIR` rejected because `DIR` is inside a root →
  do not remove the root. Forget the files under `DIR` instead (see
  [Forget removed or renamed paths](#forget-removed-or-renamed-paths)).
- Anything under `crypt/` looks inconsistent → run any chezmoi command
  and retry (see Internals).

## Internals (debugging only)

`crypt/<id>.yaml.age` decrypts to `dst:`, the real source path with
normal chezmoi prefixes, plus optional `remoteUrlPattern*`. The
`read-source-state.pre` / `edit.post` hook
(`.hooks/hidden_filenames.bash`) hard-links `<id>.age` to that path so
chezmoi sees an ordinary `encrypted_*.age` file, keeps every
materialized path out of git via `.git/info/exclude`, and regenerates
`crypt/.chezmoidata/` so templates can use
`{{ index .crypt "<id>" "targetPath" }}` etc. Desync symptoms (missing
materialized file, stale leftovers, missing `.crypt.<id>` data) fix
themselves on the next chezmoi run, which re-triggers the hook. Never
hand-edit under `crypt/`.

Repo-internal conventions (systemd unit gating, template helpers, lint)
are documented in the source repo's own CLAUDE.md.
