if vim.g.loaded_codex_kitty_bridge then
    return
end
vim.g.loaded_codex_kitty_bridge = true

vim.api.nvim_create_user_command("CodexKittyBridgeStatus", function()
    vim.print(require("codex_kitty_bridge").status())
end, {
    desc = "Show Codex Kitty terminal-image bridge status",
})

vim.api.nvim_create_user_command("CodexKittyBridgeDisable", function()
    require("codex_kitty_bridge").disable()
end, {
    desc = "Disable the Codex Kitty terminal-image bridge",
})
