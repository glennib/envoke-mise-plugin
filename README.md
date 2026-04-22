# envoke-env

A [mise](https://mise.jdx.dev) environment plugin that dynamically loads
environment variables from [envoke](https://github.com/glennib/envoke).

Secrets are resolved at shell activation time via envoke's `sh:` and `cmd:`
sources, which can call any secret provider — HashiCorp Vault, AWS Secrets
Manager, 1Password CLI, `gcloud secrets`, or
[hemli](https://github.com/glennib/hemli) for cached keyring lookups.
No plaintext secrets are written to disk.

## Prerequisites

- [mise](https://mise.jdx.dev) >= 2025.1.0
- [envoke](https://github.com/glennib/envoke) >= 2.0.0

If envoke (and any tools it calls, like hemli) are managed by mise, set
`tools = true` on the plugin directive so their bin paths are available.

## Installation

Declare the plugin in your project's `mise.toml` so teammates pick up the same
version automatically (see the [mise configuration reference][mise-plugins-config]):

```toml
[plugins]
envoke = "https://github.com/glennib/envoke-env#v2.0.0"
```

The `#<ref>` suffix pins to a tag, branch, or commit. Omit it to track the
default branch.

Alternatively, install imperatively (one-off, not shared with the project):

```bash
mise plugin install envoke https://github.com/glennib/envoke-env
```

For local development:

```bash
mise plugin link envoke /path/to/envoke-env
```

[mise-plugins-config]: https://mise.jdx.dev/configuration.html

## Usage

Add the plugin to your project's `mise.toml`:

```toml
[env]
_.envoke = { tools = true }
```

Create an `.envoke-env` file (gitignored) with the environment name:

```
local
```

That's it. When mise activates, the plugin reads `.envoke-env`, runs
`envoke render local` against your `envoke.yaml`, and injects the resolved
variables into your shell.

### Switching environments

```bash
echo apps-test > .envoke-env
```

The plugin watches `.envoke-env` for changes and re-evaluates automatically.

### Tags and overrides

Add `tag:` and `override:` directives after the environment name:

```
apps-test
tag:secrets
tag:infra
override:docker
# this is a comment
```

These are passed as `--tag` and `--override` arguments to envoke.
Blank lines and lines starting with `#` are ignored.

### Graceful failure

The plugin never aborts shell activation. Any problem it encounters is logged
as a warning on stderr and results in no injected variables; subsequent shell
init (prompt, other mise hooks) runs unaffected.

Covered cases:

- **Missing `.envoke-env` or `envoke.yaml`.** Both paths are in `watch_files`,
  so creating the missing file invalidates the cache and the plugin resumes on
  the next shell activation.
- **Malformed `.envoke-env`** (empty, or no environment name on the first
  line). Same recovery path — fix the file and the watched-file invalidation
  picks it up.
- **`envoke` binary missing, too old, or exits non-zero.** Most commonly this
  is a version mismatch — the plugin requires `envoke >= 2.0.0`. The warning
  includes envoke's own stderr plus a hint to run `envoke --version` and
  update. These failures are *not* cached (no watched file tracks the binary),
  so the next shell activation retries automatically once the binary is
  fixed.
- **`envoke` returns non-JSON output.** Also not cached; next activation
  retries.

A fresh shell is sometimes needed after fixing a watched file if mise still
holds a cached result.

## Configuration

Options are set in the `mise.toml` plugin directive:

```toml
[env]
_.envoke = { config = "envoke.yaml", environment_file = ".envoke-env", tools = true }
```

| Option | Type | Default | Description |
|---|---|---|---|
| `environment_file` | string | `".envoke-env"` | Path to the file containing environment name, tags, and overrides. |
| `config` | string | `"envoke.yaml"` | Path to the envoke configuration file. |
| `fallback_environment` | string | -- | Environment name used when `environment_file` is missing. The file wins when both are defined; no tags/overrides are applied in fallback mode. |
| `watch_files` | string or array | -- | Additional files to watch for cache invalidation. |
| `tools` | bool | `false` | Mise-level option. Set to `true` when envoke and its dependencies are mise-managed tools. |

## Caching

The plugin returns `cacheable = true` and watches:

- The envoke config file (`envoke.yaml`)
- The environment file (`.envoke-env`)
- Any extra files specified via `watch_files`

For caching to take effect, enable it in your mise settings:

```toml
[settings]
env_cache = true
```

Without caching enabled, envoke runs on every shell activation. This is
usually fast enough thanks to hemli's keyring cache, but enabling
`env_cache` avoids the invocation entirely when nothing has changed.

## Development

```bash
mise install
mise run lint
mise run lint-fix
```

## Documentation

- [envoke](https://github.com/glennib/envoke)
- [mise environment plugin development](https://mise.jdx.dev/env-plugin-development.html)
- [mise plugin-provided env directives](https://mise.jdx.dev/environments/#plugin-provided-env-directives)
