local M = {}

function M.check()
    vim.health.start("codex-kitty-bridge.nvim")
    if vim.fn.has("nvim-0.11") == 1 then
        vim.health.ok("Neovim supports TermRequest event data")
    else
        vim.health.error("Neovim 0.11 or newer is required")
    end

    local ok, snacks = pcall(require, "snacks")
    if not ok then
        vim.health.error("Snacks.nvim is not available")
        return
    end
    vim.health.ok("Snacks.nvim is available")

    local environment = snacks.image.terminal.env()
    if snacks.image.supports_terminal() and environment.placeholders then
        vim.health.ok(("Kitty placeholders supported via %s"):format(environment.name))
    else
        vim.health.error(("Kitty placeholders unavailable via %s"):format(environment.name))
    end

    local status = require("codex_kitty_bridge").status()
    if status.enabled then
        vim.health.ok("bridge is enabled for new terminal jobs")
    else
        vim.health.warn("bridge is disabled")
    end
end

return M
