local cmd = require("cmd")
local file = require("file")
local json = require("json")
local log = require("log")
local strings = require("strings")

--- Returns environment variables resolved by envoke
--- Documentation: https://mise.jdx.dev/env-plugin-development.html#miseenv-hook
--- @param ctx MiseEnvCtx Context (options = plugin configuration from mise.toml)
--- @return MiseEnvResult
function PLUGIN:MiseEnv(ctx)
    local options = ctx.options or {}

    local template_path = file.join_path(RUNTIME.pluginDirPath, "templates", "env.json.j2")
    if not file.exists(template_path) then
        error("[envoke] JSON template not found at: " .. template_path)
    end

    local config = options.config or "envoke.yaml"
    if not file.exists(config) then
        error("[envoke] Config file not found: " .. config)
    end

    local env_file_parsed = parse_env_file(options)

    local command = "envoke"
        .. " "
        .. shell_quote(env_file_parsed.environment)
        .. " --template "
        .. shell_quote(template_path)
        .. " --config "
        .. shell_quote(config)
        .. " --quiet"

    for _, tag in ipairs(env_file_parsed.tags) do
        command = command .. " --tag " .. shell_quote(tag)
    end

    for _, override in ipairs(env_file_parsed.overrides) do
        command = command .. " --override " .. shell_quote(override)
    end

    log.debug("Running: " .. command)

    local ok, output = pcall(cmd.exec, command)
    if not ok then
        error(
            "[envoke] Failed to run envoke. Ensure envoke is installed"
                .. " and 'tools = true' is set in your mise.toml.\n"
                .. "Command: "
                .. command
                .. "\n"
                .. "Error: "
                .. tostring(output)
        )
    end

    local ok2, env_map = pcall(json.decode, output)
    if not ok2 then
        error(
            "[envoke] Failed to parse envoke JSON output.\n"
                .. "Error: "
                .. tostring(env_map)
                .. "\n"
                .. "Output: "
                .. output:sub(1, 200)
        )
    end

    local env_vars = {}
    for key, value in pairs(env_map) do
        table.insert(env_vars, { key = key, value = value })
    end

    local watch_files = build_watch_files(options, config)

    log.info("Loaded " .. #env_vars .. " variables from envoke (" .. env_file_parsed.environment .. ")")

    return {
        env = env_vars,
        cacheable = true,
        watch_files = watch_files,
    }
end

--- Parse the environment file.
---
--- Format:
---   First line: environment name (required)
---   Subsequent lines (optional):
---     tag:<name>       — passed as --tag to envoke
---     override:<name>  — passed as --override to envoke
---     # comments and blank lines are ignored
---
--- @param options table Plugin options
--- @return {environment: string, tags: string[], overrides: string[]}
function parse_env_file(options)
    local tags = {}
    local overrides = {}

    local env_file = options.environment_file or ".envoke-env"

    if not file.exists(env_file) then
        error("[envoke] Environment file not found: " .. env_file .. "\nSet one with: echo local > " .. env_file)
    end

    local content = strings.trim_space(file.read(env_file))
    if content == "" then
        error("[envoke] Environment file is empty: " .. env_file)
    end

    local lines = strings.split(content, "\n")
    local environment = strings.trim_space(lines[1])

    if environment == "" then
        error("[envoke] Environment file has no environment name on first line: " .. env_file)
    end

    for i = 2, #lines do
        local line = strings.trim_space(lines[i])
        if line ~= "" and not strings.has_prefix(line, "#") then
            if strings.has_prefix(line, "tag:") then
                local tag = strings.trim_space(line:sub(5))
                if tag ~= "" then
                    table.insert(tags, tag)
                end
            elseif strings.has_prefix(line, "override:") then
                local override = strings.trim_space(line:sub(10))
                if override ~= "" then
                    table.insert(overrides, override)
                end
            else
                log.warn("Unknown directive in " .. env_file .. ": " .. line)
            end
        end
    end

    return { environment = environment, tags = tags, overrides = overrides }
end

--- Build the list of files to watch for cache invalidation.
--- @param options table Plugin options
--- @param config string Path to envoke config file
--- @return string[]
function build_watch_files(options, config)
    local watch = { config }

    local env_file = options.environment_file or ".envoke-env"
    if file.exists(env_file) then
        table.insert(watch, env_file)
    end

    if options.watch_files then
        local extra = to_list(options.watch_files)
        for _, f in ipairs(extra) do
            table.insert(watch, f)
        end
    end

    return watch
end

--- Convert a value to a list. If already a table, return as-is.
--- If a string, split on commas.
--- @param value string|string[]
--- @return string[]
function to_list(value)
    if type(value) == "table" then
        return value
    end
    if type(value) == "string" then
        return strings.split(value, ",")
    end
    return {}
end

--- Shell-quote a string for safe inclusion in a command.
--- @param s string
--- @return string
function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end
