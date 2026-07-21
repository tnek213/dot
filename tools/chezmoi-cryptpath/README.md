# chezmoi-cryptpath

Helper for chezmoi entries that use the `crypt/<id>.{age,yaml.age}`
**encrypted-path scheme** materialized by `.hooks/hidden_filenames.bash`: an
entry's filename, content, and source path are all hidden behind a hash-named
pair of age blobs under `crypt/`.

It's a chezmoi-only tool — it operates on *this* repo's crypt store via
`chezmoi source-path`/`chezmoi data`, so it's only useful where chezmoi runs.
That's why it lives in the repo and is installed as part of `chezmoi apply`
(see `.chezmoiscripts/run_onchange_*_pipx_chezmoi_tools.sh.tmpl`).

## Install

Installed automatically on `chezmoi apply` via pipx. Manually:

```sh
pipx install ~/.local/share/chezmoi/tools/chezmoi-cryptpath
```

chezmoi dispatches unknown subcommands to `chezmoi-<name>` on `PATH`, so the
command is usable as either `chezmoi-cryptpath …` or `chezmoi cryptpath …`.

## Commands

- `list-encrypted` / `list-clear` — list crypt-managed / clear-path targets
- `mv` — move/rename a target and rewrite its crypt `dst`
- `forget` — drop crypt entries (leaves the target file)
- `use-existing-path` — repoint an entry's `dst` at an existing source path
- `edit-meta <target-or-id>` — edit an entry's encrypted metadata yaml in
  `$EDITOR` (e.g. to add `remoteUrlPattern[/1/2/3]`)
- `to-encrypted-path [--pattern[1|2|3] P] file…` — convert file(s) into the
  crypt scheme; `--pattern*` records `remoteUrlPattern*` metadata
- `to-encrypted` / `to-unencrypted` — convert to clear-path encrypted / plain

Run `chezmoi-cryptpath <command> --help` for details.
