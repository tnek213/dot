# User data

User data is an interface for user-specific values kept outside distributed skills. Values live in scopes and are reached through a configured provider, which owns storage and synchronization. The interface does not assume any particular storage. Preferences and state are the kinds of user data defined below.

## Preferences

Each skill declares its scope, keys, requirements, defaults, sensitive keys, and any shared fallbacks.

A user's preference value is used as a preference everywhere. Refer to it only by its `scope:key` reference and obtain it through this protocol when it is needed. Never write a stored or user-supplied value into reusable material: skill instructions, scripts, tests, examples, comments, bundled references, other skills, agent memory, or documentation shipped with skills. This holds for every skill and file that uses the value, not only the skill that declares it. A skill's documented default is a generic value for all users, declared only in its preference table, never a user's own value. Generic defaults, allowed-value lists, and other values not specific to a user are not duplicates, even when they equal a stored value. When a user-specific written value turns out to duplicate a preference, replace it with the reference. The rule does not cover authorized deliverables, previews, or private temporary handoff files removed after use. Deliverables and previews follow the masking rules below.

Scripts follow the same rule. A script contains no preference values and no defaults for them, in code, constants, argument defaults, shipped configuration, or tests, which use placeholders. The agent resolves each preference and passes the value to the script as an argument, or for sensitive values through stdin or a private temporary input file. A script may also read the provider directly for a key with no documented default, applying the key's declared shared fallback itself. Such a script also accepts the value as an argument, which takes precedence, and the agent passes it whenever an override or answer applies. When a needed value is missing, the script exits with an error naming the missing key and any fallback checked, instead of using a built-in value.

## State

State is user data a skill writes itself to remember what happened, such as the last run, cursors or what was fetched. It is the second kind of user data, reached with `--kind state`. A skill writes state without asking. State has no defaults and no fallback, and a missing state key just means nothing was recorded.

Each skill declares its state keys in a table like its preference table, with the columns Key, Meaning, Requirements and Sensitive. State lives in the skill's scope, like its preferences, but in a separate store, so state never mixes with preferences.

State values are user specific and follow the same rule as preference values: never write one into skills, scripts, tests or documentation. Refer to a state value only by its `scope:key` reference.

Keep secrets out of state, and keep out bulk data or caches that can be rebuilt. Keep one key per independent thing (one per service, not one shared blob), so two machines rarely write the same key.

State is listed only when asked for, separately from preferences. Previews of preferences leave it out.

## Declarations

Every skill that reads or writes user data keeps `user-data.json` beside its `SKILL.md`, a machine readable copy of the keys in its tables:

```json
{ "keys": [{ "scope": "SCOPE", "key": "KEY", "kind": "preference" }] }
```

Each entry has `scope`, `kind` (`preference` or `state`) and either `key`, an exact key, or `pattern`, where `{name}` matches one segment without dots, such as `{service}.next_run`. Entries have no other fields. List the skill's own keys and the `global` keys it reads as a shared fallback. Every key a skill reads or writes must be declared. The report tool `~/.local/lib/agent-tools/user-data-orphans.py` compares these declarations with the store and lists the stored keys no skill declares.

Run the report with `~/.local/lib/agent-tools/user-data-orphans.py`, which reads the installed skills in `~/.claude/skills` and `~/.agents/skills` unless `--skills-dir` names others. It prints one JSON object with `unknown_scopes`, `undeclared_keys`, `kind_mismatch` and `invalid_declarations`, naming keys but never values. It exits 0 when it finds nothing, 1 when it finds something and 2 on a provider or configuration error. The report never deletes anything: removing a leftover is a separate step the user confirms.

## Provider discovery

Read `~/.config/agent-tools/config.json` as a JSON object. Its only setting, `user_data_helper`, is a non-empty executable path, either absolute or starting with `~/`. Ignore unknown settings. Other path forms or value types are configuration errors. Expand `~` and invoke the helper directly with separate arguments, never as a shell command. All user data belongs in the provider's store.

If the file or setting is missing, or `user_data_helper` is null, ask for the helper path. Save the supplied path in `config.json`, creating its directory as needed. Never guess the path. If none is supplied, use answers for the current run only and explain they cannot be saved. Report configuration write failures.

Malformed configuration or an unavailable helper is a provider error. During a preference preview, report configuration problems without asking setup questions or writing files.

## Command contract

```text
<helper> get [--kind preference|state] --scope SCOPE --key KEY
<helper> set [--kind preference|state] --scope SCOPE --key KEY --value-json JSON
<helper> list [--kind preference|state] --scope SCOPE
<helper> delete [--kind preference|state] --scope SCOPE --key KEY
<helper> scopes [--kind preference|state]
```

`--kind` defaults to `preference`. Each kind is stored separately, so the same scope and key can hold different values in both kinds.

Scopes and keys are non-empty, case-sensitive identifiers, never filesystem paths. A skill's scope is its name. Reserve `global` for explicitly shared preferences.

In documentation, write preference references as `scope:key`, for example `global:language` or `se-bookkeeping:reports.language`. Dots group related names within a literal key, not nested JSON fields. Pass scope and key separately to the helper. Declare shared fallbacks explicitly, such as `se-bookkeeping:reports.language` falling back to `global:language`. Similar names do not imply a fallback.

Values may be any JSON value. False, zero, empty strings, and null are stored values, not missing keys. For `--value-json`, pass valid JSON as one argument, including JSON quotation marks around string values.

Commands write one JSON object followed by a newline to stdout, with diagnostics on stderr:

| Command  | Success output                                               | Behavior                                                                                                |
| -------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `get`    | `{"scope":"SCOPE","kind":"KIND","key":"KEY","value":VALUE}`  | Read the exact key without fallback or modification.                                                    |
| `set`    | `{"scope":"SCOPE","kind":"KIND","key":"KEY"}`                | Create missing scopes and keys or replace existing values. Succeed only after saving.                   |
| `list`   | `{"scope":"SCOPE","kind":"KIND","values":{"KEY":VALUE}}`     | Return the exact scope's keys. A missing scope returns an empty object in `values` without creating it. |
| `delete` | `{"scope":"SCOPE","kind":"KIND","key":"KEY","deleted":true}` | Remove the exact key. Missing keys or scopes succeed with `deleted: false`.                             |
| `scopes` | `{"kind":"KIND","scopes":["SCOPE"]}`                         | Return the names of all stored scopes of the kind, sorted. Nothing stored returns an empty list.        |

Exit codes:

- `0`: success.
- `1`: `get` found no such scope or key. Output `{"scope":"SCOPE","kind":"KIND","key":"KEY","missing":true}`.
- `2`: invalid arguments or configuration, unavailable storage, detected conflicts, or another provider error. Leave stdout empty and write a diagnostic to stderr.

Unexpected exit codes or invalid output are provider errors. Failed writes must preserve prior values. Concurrent local mutations must not lose unrelated changes. Report detected conflicts rather than silently choosing a value. Concurrency and synchronization guarantees depend on the provider.

## Resolve and save

Resolve each preference in order:

1. An explicit value in the current request.
2. A saved value in the skill's scope.
3. A saved value in `global`, only for a fallback key explicitly declared by the skill.
4. The skill's documented default.
5. Ask for a required value still missing.

Fallback applies to missing values, never provider errors. Validate stored values, request overrides, answers, and defaults against the skill's requirements. An invalid value blocks resolution of that preference. Explain why and ask for a valid replacement rather than silently falling back. In previews, mark it invalid without asking.

Save answers to missing-preference questions in the skill's scope, creating the scope or key as needed. Save to `global` only when the user explicitly requests a shared preference. Request-specific overrides apply only to the current run unless the user asks to remember them. Never persist answers marked as temporary or infer preferences from incidental information.

On provider errors, report the problem and stop further provider access for the run. Retain values already resolved successfully. Obtain remaining required values from the user for this run only and explain they cannot be saved. Report failed saves.

## Preview and manage

When asked what preferences a skill would use, apply the same resolution order and show each effective value and its source, plus missing required or invalid values. Show defaults when selected. Do not execute the workflow, ask setup or missing-value questions, or change configuration or preferences. A preference preview never shows state.

Use `set` and `delete` for requested corrections and removals. Keep secrets in a credential store, with only credential references in preferences. Omit credential details and mask skill-declared sensitive values and sensitive account identifiers in previews. Never echo or log secret values.
