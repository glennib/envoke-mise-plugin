--- Returns PATH entries to prepend when this plugin is active
--- Documentation: https://mise.jdx.dev/env-plugin-development.html#misepath-hook
--- @param ctx MisePathCtx Context (options = plugin configuration from mise.toml)
--- @return string[]
function PLUGIN:MisePath(ctx)
    return {}
end
