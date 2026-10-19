# CLAUDE.md

This is a **chezmoi source directory**. Files here are *source state*; chezmoi
renders them into the target (`$HOME`). This file is chezmoi-ignored (see
`.chezmoiignore`) so it is git-tracked but never deployed.

## Source-name conventions (attributes are prefixes on the filename)

- `dot_foo` → `~/.foo`
- `private_` → target mode `0600`
- `executable_` → target is executable
- `encrypted_foo.age` → age-encrypted; decrypts to `~/.foo`
- `*.tmpl` → Go-template rendered at apply time
- `<name>-uses/` → a helper dir tightly coupled to the unit `<name>.{service,timer,…}`

## chezmoi-ignore is not git-ignore

`.chezmoiignore` only stops chezmoi from *deploying* a path; git still tracks it.
We use this for repo-local files that must live in the repo but not in `$HOME`:
`CLAUDE.md`, and machine-local Claude runtime/secrets
(`.claude/.credentials.json`, `history.jsonl`, `stats-cache.json`).

## Encryption

age, recipient in `.chezmoi.toml.tmpl`, identity at
`~/.config/chezmoi/key.txt`. Two encryption uses:

1. Inline `encrypted_*.age` source files.
2. `crypt/` — a content-addressed encrypted store. `crypt/.chezmoiignore`
   ignores everything except `.chezmoidata/`. Only the `<hash>.age` /
   `<hash>.yaml.age` blobs are git-tracked; the decrypted plaintext under
   `crypt/.chezmoidata/*.yaml` is git-ignored (`crypt/.gitignore`) and exists
   only at chezmoi-time.

## systemd user units

Units live under `dot_config/systemd/user/`. Its `.chezmoiignore` gates units on
`lookPath` so a unit is only deployed when its backing binary is installed
(e.g. `mbsync@.service` is skipped without `mbsync`). The root `.chezmoiignore`
self-cleaningly ignores any `<name>-uses/` helper dir whose matching unit is
absent from source.

## Other

- `.hooks/hidden_filenames.bash` runs on `read-source-state.pre` and `edit.post`.
- Markdown is linted via `.markdownlint-cli2.jsonc`.
- Shell config is split into `dot_bashrc` + numbered drop-ins in
  `dot_bashrc.d/`, sourced in filename order.
- `dot_config/aictx/` configures the `aictx` tool (defined in
  `dot_bashrc.d/private_50_aictx.bash`): `types/` is the chat-type taxonomy,
  `template/` is the per-chat scaffold, `parts-rules.md`/`slug-rules.md` are
  splitting/naming rules.
