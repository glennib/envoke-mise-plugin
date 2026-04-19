# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`envoke-mise-plugin` is a [mise](https://mise.jdx.dev) **environment plugin** (vfox-style, Lua-based) that injects variables resolved by [envoke](https://github.com/glennib/envoke) into the shell at `mise` activation time. It is published as `mise plugin install envoke …` and used via the `_.envoke = { … }` plugin directive in a consumer project's `mise.toml`. No plaintext secrets are written to disk — envoke's `sh:` / `cmd:` sources resolve them on every (cacheable) activation.

The Rust CLI this plugin shells out to lives at [glennib/envoke](https://github.com/glennib/envoke). Consult its README when the plugin's behaviour depends on envoke CLI semantics (tags, overrides, `--template`, exit codes, JSON output shape). If a local checkout exists alongside this repo, prefer reading it over fetching — ask the user for the path.

## Architecture

Mise loads this plugin via two hook files that each define a method on the global `PLUGIN` table:

- `hooks/mise_env.lua` — `PLUGIN:MiseEnv(ctx)`. The workhorse. Reads plugin options from `ctx.options` (set by the consumer in `mise.toml`), parses `.envoke-env` (see format below), builds an `envoke <env> --template templates/env.json.j2 --config <cfg> --quiet [--tag …] [--override …]` command, executes it via the injected `cmd` module, parses the resulting JSON, and returns `{ env = [...], cacheable = true, watch_files = [...] }`. All errors are raised with `error("[envoke] …")` so mise surfaces them with context.
- `hooks/mise_path.lua` — `PLUGIN:MisePath(ctx)`. Returns `{}`; kept as a stub because the hook is required by the plugin contract but this plugin adds nothing to `PATH`.
- `templates/env.json.j2` — one-liner `{{ v | tojson }}`. `v` is envoke's flat `name → value` map; serialising it yields a JSON object the Lua hook can `json.decode`. This is why the plugin is decoupled from envoke's default shell output format.
- `metadata.lua` — plugin manifest (`PLUGIN` table with name/version/minMiseVersion).
- `types/mise-plugin.lua` — LuaCATS type definitions for the mise hook API (`RUNTIME`, `PLUGIN`, `MiseEnvCtx`, `MiseEnvResult`, etc.), referenced by `.luarc.json` as a workspace library so `lua-language-server` can type-check hooks against the mise contract.

### `.envoke-env` file format (parsed by `parse_env_file`)

First non-blank line is the environment name. Subsequent lines may be `tag:<name>`, `override:<name>`, `# comment`, or blank. Unknown directives log a warning but don't fail. This is the plugin's *only* project-local configuration surface beyond the options in `mise.toml`.

### Plugin options (passed via `_.envoke = { … }` in consumer `mise.toml`)

`environment_file` (default `.envoke-env`), `config` (default `envoke.yaml`), `watch_files` (string or array; comma-split if string), `tools` (mise-level, not read by the plugin — set `true` so envoke itself resolves from the mise shim path).

### Caching

The hook returns `cacheable = true` and `watch_files = [config, env_file, …extra]`. Cache invalidation on file change is mise's responsibility — the consumer must also set `[settings] env_cache = true` in their global mise config for caching to actually take effect.

### Available Lua modules in hooks

Only the modules mise injects into the sandboxed Lua runtime: `cmd`, `file`, `json`, `log`, `strings` (see `require(...)` at the top of `hooks/mise_env.lua`). Lua runtime is 5.1 (per `.luarc.json`) even though `mise.toml` installs Lua 5.4 for tooling (stylua/lua-language-server). Don't assume standard Lua stdlib availability; prefer the mise-provided modules.

## Commands

```sh
mise install            # install tool deps (hk, stylua, lua-language-server, actionlint, pkl, lua)
mise run lint           # run all hk linters (stylua --check, lua-language-server --check, actionlint)
mise run lint-fix       # run hk fix (auto-fixes stylua)
hk check                # same as `mise run lint`
hk fix                  # same as `mise run lint-fix`
```

CI (`.github/workflows/ci.yml`) runs only `mise run lint`; there is no test runner in this repo — behaviour is verified by linking the plugin into a real project (`mise plugin link envoke /path/to/envoke-mise-plugin`) and activating it.

### Local end-to-end testing

To exercise the hook against a real project:

```sh
mise plugin link envoke /home/glenn/devel/glennib/envoke-mise-plugin
# in a project with envoke.yaml and .envoke-env:
mise env            # triggers MiseEnv, should print resolved vars
mise env --json     # JSON form, easier to diff
```

Use `log.debug` / `log.info` calls in the hook and run mise with `MISE_DEBUG=1` or `MISE_LOG_LEVEL=debug` to see hook logs.

## Code style

- Stylua: 4-space indent, 120 col, `AutoPreferDouble` quotes, always parens on calls (`stylua.toml`).
- Lua runtime target: 5.1 (in hooks). Don't use 5.2+ syntax (`goto`, bitwise ops, integer division `//`).
- Keep hook functions annotated with LuaCATS (`---@param`, `---@return`) pointing at the types in `types/mise-plugin.lua` — the `.luarc.json` workspace library makes these type-check.
- Errors from hooks use the `[envoke] …` prefix so mise output is greppable.

## Keeping this file current (self-updating)

Treat this file as living documentation. When you make changes that would invalidate anything above, update this file in the same change. Specifically:

1. **Hook contract or option surface changes** — if you add/rename/remove a plugin option, change `.envoke-env` syntax, change the `envoke` invocation, or add a new `PLUGIN:` hook, update the corresponding Architecture subsection and the option table.
2. **New Lua module use** — if a hook starts requiring a new mise-provided module, add it to the "Available Lua modules" list.
3. **Tooling changes** — if `mise.toml` gains/loses a tool or task, or `hk.pkl` gains/loses a linter, update the Commands section.
4. **Lua runtime bump** — if `.luarc.json` moves off Lua 5.1, update the Code style note.
5. **Anything that surprised you** — if you had to read multiple files to figure something out that isn't captured here, add a short note under the relevant section so the next Claude doesn't have to repeat that archaeology.

When updating: keep the file tight. Don't enumerate file structure that `ls` reveals; capture the *why* and the cross-file invariants. If a section grows beyond what's useful, trim it rather than layering.
