# helpers/

This directory contains reusable helper templates that can be called from other templates using `includeTemplate` / `template`.

## globfilter

`globfilter` takes one or more glob patterns and returns matching paths, filtered by `matchRegex`. Each line is printed as `match|path`, where `match` is capture group 1 from `matchRegex` (unique and sorted).

- `glob` (required): A glob string or a list of glob strings to search.
- `matchRegex` (optional): Regex filter/transform; output uses capture group 1.
- `includeDirs` (optional): Include directory matches as well.

### Arguments

#### `glob` (required)

A single glob string **or** a list of glob strings.

**Single glob:**

```gotemplate
{{ includeTemplate "helpers/globfilter" (dict
  "glob" (joinPath .chezmoi.sourceDir "dot_local/share/fonts/**/*")
  "matchRegex" `^(.*)$`
) }}
```

**Multiple globs:**

```gotemplate
{{ includeTemplate "helpers/globfilter" (dict
  "glob" (list
    (joinPath .chezmoi.sourceDir "dot_local/share/fonts/**/*.ttf")
    (joinPath .chezmoi.sourceDir "dot_local/share/fonts/**/*.otf")
    (joinPath .chezmoi.sourceDir "dot_local/share/fonts/**/*.ttf.age")
    (joinPath .chezmoi.sourceDir "dot_local/share/fonts/**/*.otf.age")
  )
  "matchRegex" `^(.*)$`
) }}
```

#### `matchRegex` (optional, default: `^(.*)$`)

A regex used to filter entries and produce the `match` part of `match|path`, where **capture group 1** becomes `match`.

> NOTE: `matchRegex` must contain a capture group `(…)`.

**Example: extract unit name as `match` while keeping full path after `|`:**

```gotemplate
{{ includeTemplate "helpers/globfilter" (dict
  "glob" (joinPath .chezmoi.sourceDir "dot_config/systemd/user/**/*")
  "matchRegex" `^.*\/(.+\.(service|timer|socket|path|target|mount|automount|slice))(\.tmpl)?$`
) }}
```

Outputs lines like:

- `dropbox.service|/home/kent/.local/share/chezmoi/dot_config/systemd/user/dropbox.service.tmpl`
- `backup.timer|/home/kent/.local/share/chezmoi/dot_config/systemd/user/backup.timer`

#### `includeDirs` (optional, default: `false`)

If `false`, directory entries from glob expansion are ignored.

```gotemplate
{{ includeTemplate "helpers/globfilter" (dict
  "glob" (joinPath .chezmoi.sourceDir "dot_config/systemd/user/**/*")
  "includeDirs" false
  "matchRegex" `^(.*)$`
) }}
```

### Typical caller pattern

Because `globfilter` prints one result per line, callers typically convert it into a list:

```gotemplate
{{- $out := includeTemplate "helpers/globfilter" (dict
  "glob" (joinPath .chezmoi.sourceDir "dot_local/share/fonts/**/*")
  "matchRegex" `^(.*)$`
) -}}
{{- $items := splitList "\n" ($out | trim) -}}
```

And then split each line into `match` and `path`:

```gotemplate
{{- range $items -}}
  {{- $cols := splitList "|" . -}}
  {{- $match := index $cols 0 -}}
  {{- $path := index $cols 1 -}}
{{- end -}}
```
