# User data

User data is an interface for user-specific values kept outside distributed skills. Values live in scopes and are reached through a configured provider, which owns storage and synchronization. The interface does not assume any particular storage. Preferences are the kind of user data defined below.

## Preferences

Each skill declares its scope, keys, requirements, defaults, sensitive keys, and any shared fallbacks.

A user's preference value is used as a preference everywhere. Refer to it only by its `scope:key` reference and obtain it through this protocol when it is needed. Never write a stored or user-supplied value into reusable material: skill instructions, scripts, tests, examples, comments, bundled references, other skills, agent memory, or documentation shipped with skills. This holds for every skill and file that uses the value, not only the skill that declares it. A skill's documented default is a generic value for all users, declared only in its preference table, never a user's own value. Generic defaults, allowed-value lists, and other values not specific to a user are not duplicates, even when they equal a stored value. When a user-specific written value turns out to duplicate a preference, replace it with the reference. The rule does not cover authorized deliverables, previews, or private temporary handoff files removed after use. Deliverables and previews follow the masking rules below.

Scripts follow the same rule. A script contains no preference values and no defaults for them, in code, constants, argument defaults, shipped configuration, or tests, which use placeholders. The agent resolves each preference and passes the value to the script as an argument, or for sensitive values through stdin or a private temporary input file. A script may also read the provider directly for a key with no documented default, applying the key's declared shared fallback itself. Such a script also accepts the value as an argument, which takes precedence, and the agent passes it whenever an override or answer applies. When a needed value is missing, the script exits with an error naming the missing key and any fallback checked, instead of using a built-in value.

## Provider discovery

Read `~/.config/agent-tools/config.json` as a JSON object. Its only setting, `user_data_helper`, is a non-empty executable path, either absolute or starting with `~/`. Ignore unknown settings. Other path forms or value types are configuration errors. Expand `~` and invoke the helper directly with separate arguments, never as a shell command. All user data belongs in the provider's store.

If the file or setting is missing, or `user_data_helper` is null, ask for the helper path. Save the supplied path in `config.json`, creating its directory as needed. Never guess the path. If none is supplied, use answers for the current run only and explain they cannot be saved. Report configuration write failures.

Malformed configuration or an unavailable helper is a provider error. During a preference preview, report configuration problems without asking setup questions or writing files.

## Command contract

```text
<helper> get --scope SCOPE --key KEY
<helper> set --scope SCOPE --key KEY --value-json JSON
<helper> list --scope SCOPE
<helper> delete --scope SCOPE --key KEY
```

Scopes and keys are non-empty, case-sensitive identifiers, never filesystem paths. A skill's scope is its name. Reserve `global` for explicitly shared preferences.

In documentation, write preference references as `scope:key`, for example `global:language` or `se-bookkeeping:reports.language`. Dots group related names within a literal key, not nested JSON fields. Pass scope and key separately to the helper. Declare shared fallbacks explicitly, such as `se-bookkeeping:reports.language` falling back to `global:language`. Similar names do not imply a fallback.

Values may be any JSON value. False, zero, empty strings, and null are stored values, not missing keys. For `--value-json`, pass valid JSON as one argument, including JSON quotation marks around string values.

Commands write one JSON object followed by a newline to stdout, with diagnostics on stderr:

| Command  | Success output                                 | Behavior                                                                                                |
| -------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `get`    | `{"scope":"SCOPE","key":"KEY","value":VALUE}`  | Read the exact key without fallback or modification.                                                    |
| `set`    | `{"scope":"SCOPE","key":"KEY"}`                | Create missing scopes and keys or replace existing values. Succeed only after saving.                   |
| `list`   | `{"scope":"SCOPE","values":{"KEY":VALUE}}`     | Return the exact scope's keys. A missing scope returns an empty object in `values` without creating it. |
| `delete` | `{"scope":"SCOPE","key":"KEY","deleted":true}` | Remove the exact key. Missing keys or scopes succeed with `deleted: false`.                             |

Exit codes:

- `0`: success.
- `1`: `get` found no such scope or key. Output `{"scope":"SCOPE","key":"KEY","missing":true}`.
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

When asked what preferences a skill would use, apply the same resolution order and show each effective value and its source, plus missing required or invalid values. Show defaults when selected. Do not execute the workflow, ask setup or missing-value questions, or change configuration or preferences.

Use `set` and `delete` for requested corrections and removals. Keep secrets in a credential store, with only credential references in preferences. Omit credential details and mask skill-declared sensitive values and sensitive account identifiers in previews. Never echo or log secret values.
