local protocol = require("codex_kitty_bridge.protocol")

local M = {}

local defaults = {
    enabled = true,
    force = false,
    notify = true,
    max_chunk_bytes = 8 * 1024,
    max_payload_bytes = 6 * 1024 * 1024,
    max_columns = 512,
    max_rows = 512,
    capability_env = "CODEX_NEOVIM_KITTY_BRIDGE",
    outer_tmux_env = "CODEX_NEOVIM_OUTER_TMUX",
}

local config = vim.deepcopy(defaults)
local request
local buffers = {}
local references = {}
local enabled = false
local previous_env

---@param message string
---@param level integer
local function notify(message, level)
    if config.notify then
        vim.notify(message, level, { title = "codex-kitty-bridge.nvim" })
    end
end

---@param value unknown
---@param minimum number
---@param maximum number
---@return boolean
local function integer_between(value, minimum, maximum)
    return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

---@param buf number
---@return table
local function buffer_state(buf)
    buffers[buf] = buffers[buf] or {
        images = {},
        pending = nil,
    }
    return buffers[buf]
end

---@param buf number
---@param image_id number
local function retain(buf, image_id)
    local state = buffer_state(buf)
    if state.images[image_id] then
        return
    end
    state.images[image_id] = true
    references[image_id] = references[image_id] or {}
    references[image_id][buf] = true
end

---@param buf number
---@param image_id number
---@return boolean
local function release(buf, image_id)
    local state = buffers[buf]
    if state then
        state.images[image_id] = nil
        if state.pending and state.pending.image_id == image_id then
            state.pending = nil
        end
    end
    local refs = references[image_id]
    if not refs then
        return false
    end
    refs[buf] = nil
    if next(refs) then
        return false
    end
    references[image_id] = nil
    return true
end

---@param opts table<string, string|number>
---@return boolean
local function forward(opts)
    local ok, err = pcall(request, opts)
    if not ok then
        notify(("failed to forward terminal image: %s"):format(err), vim.log.levels.ERROR)
        return false
    end
    return true
end

---@param state table
---@param opts table<string, string|number>
---@return boolean
local function validate_start(state, opts)
    if opts.a ~= "T" or opts.t ~= "d" or opts.f ~= 100 or opts.U ~= 1 then
        return false
    end
    if not integer_between(opts.i, 1, 0xFFFFFF) then
        return false
    end
    if not integer_between(opts.c, 1, config.max_columns) then
        return false
    end
    if not integer_between(opts.r, 1, config.max_rows) then
        return false
    end
    if opts.m ~= 0 and opts.m ~= 1 then
        return false
    end
    if not protocol.is_base64(opts.data) or #opts.data > config.max_chunk_bytes then
        return false
    end
    state.pending = opts.m == 1 and {
        image_id = opts.i,
        payload_bytes = #opts.data,
    } or nil
    return true
end

---@param state table
---@param opts table<string, string|number>
---@return boolean
local function validate_continuation(state, opts)
    if not state.pending or opts.a ~= nil or (opts.m ~= 0 and opts.m ~= 1) then
        return false
    end
    if not protocol.is_base64(opts.data) or #opts.data > config.max_chunk_bytes then
        return false
    end
    for key in pairs(opts) do
        if key ~= "m" and key ~= "q" and key ~= "data" then
            return false
        end
    end
    state.pending.payload_bytes = state.pending.payload_bytes + #opts.data
    if state.pending.payload_bytes > config.max_payload_bytes then
        return false
    end
    if opts.m == 0 then
        state.pending = nil
    end
    return true
end

---@param buf number
---@param opts table<string, string|number>
---@return boolean
local function handle_delete(buf, opts)
    if opts.a ~= "d" or opts.d ~= "I" or not integer_between(opts.i, 1, 0xFFFFFF) then
        return false
    end
    local state = buffers[buf]
    if not state or not state.images[opts.i] then
        return true
    end
    if release(buf, opts.i) then
        forward(opts)
    end
    return true
end

---@param buf number
---@param sequence string
---@return boolean handled
function M.handle(buf, sequence)
    if not enabled then
        return false
    end
    local opts = protocol.parse(sequence)
    if not opts then
        return false
    end
    if opts.a == "d" then
        return handle_delete(buf, opts)
    end

    local state = buffer_state(buf)
    if opts.a == "T" then
        state.pending = nil
        if not validate_start(state, opts) then
            return true
        end
        retain(buf, opts.i)
    elseif not validate_continuation(state, opts) then
        state.pending = nil
        return true
    end
    forward(opts)
    return true
end

---@param buf number
function M.cleanup(buf)
    local state = buffers[buf]
    if not state then
        return
    end
    local image_ids = vim.tbl_keys(state.images)
    buffers[buf] = nil
    for _, image_id in ipairs(image_ids) do
        if release(buf, image_id) then
            forward({ a = "d", d = "I", i = image_id })
        end
    end
end

local function restore_environment()
    if not previous_env then
        return
    end
    vim.env[config.capability_env] = previous_env.capability
    vim.env[config.outer_tmux_env] = previous_env.outer_tmux
    previous_env = nil
end

function M.disable()
    for _, buf in ipairs(vim.tbl_keys(buffers)) do
        M.cleanup(buf)
    end
    pcall(vim.api.nvim_del_augroup_by_name, "codex.kitty.bridge")
    restore_environment()
    enabled = false
end

---@param opts? table
function M.setup(opts)
    if enabled then
        M.disable()
    end
    config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

    local injected_request = config.request
    config.request = nil
    local supported = config.force
    if injected_request then
        request = injected_request
        supported = true
    else
        local ok, snacks = pcall(require, "snacks")
        if not ok then
            notify("Snacks.nvim is required", vim.log.levels.ERROR)
            return
        end
        snacks.image.setup()
        local environment = snacks.image.terminal.env()
        supported = snacks.image.supports_terminal() and environment.placeholders == true
        request = snacks.image.terminal.request
    end
    if not config.enabled or not supported then
        notify(
            "outer terminal does not support Kitty Unicode image placeholders",
            vim.log.levels.WARN
        )
        return
    end

    previous_env = {
        capability = vim.env[config.capability_env],
        outer_tmux = vim.env[config.outer_tmux_env],
    }
    vim.env[config.capability_env] = "1"
    vim.env[config.outer_tmux_env] = vim.env.TMUX or ""

    local group = vim.api.nvim_create_augroup("codex.kitty.bridge", { clear = true })
    vim.api.nvim_create_autocmd("TermRequest", {
        group = group,
        desc = "Forward safe Kitty image requests from embedded terminals",
        callback = function(ev)
            local data = ev.data or {}
            M.handle(ev.buf, data.sequence or vim.v.termrequest)
        end,
    })
    vim.api.nvim_create_autocmd({ "TermClose", "BufWipeout" }, {
        group = group,
        desc = "Release terminal images owned by a closed buffer",
        callback = function(ev)
            M.cleanup(ev.buf)
        end,
    })
    enabled = true
end

function M.status()
    return {
        enabled = enabled,
        buffers = vim.tbl_count(buffers),
        images = vim.tbl_count(references),
        capability_env = enabled and vim.env[config.capability_env] or nil,
    }
end

return M
