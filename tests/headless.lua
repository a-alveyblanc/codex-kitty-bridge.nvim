local bridge = require("codex_kitty_bridge")
local protocol = require("codex_kitty_bridge.protocol")

local function equal(actual, expected, message)
    if not vim.deep_equal(actual, expected) then
        error(("%s\nexpected: %s\nactual: %s"):format(
            message,
            vim.inspect(expected),
            vim.inspect(actual)
        ))
    end
end

local requests = {}
local old_capability = vim.env.CODEX_NEOVIM_KITTY_BRIDGE
local old_tmux = vim.env.CODEX_NEOVIM_OUTER_TMUX
bridge.setup({
    force = true,
    notify = false,
    request = function(opts)
        requests[#requests + 1] = vim.deepcopy(opts)
    end,
})

local parsed = assert(protocol.parse(
    "\27_Ga=T,t=d,f=100,i=42,U=1,c=2,r=1,q=2,m=1;YWJj"
))
equal(parsed.i, 42, "numeric controls are parsed")
equal(parsed.data, "YWJj", "payload is preserved")

assert(bridge.handle(11, "\27_Ga=T,t=d,f=100,i=42,U=1,c=2,r=1,q=2,m=1;YWJj"))
assert(bridge.handle(11, "\27_Gm=0;ZA=="))
equal(#requests, 2, "a chunked image is forwarded")
equal(bridge.status().images, 1, "the image is retained")

assert(bridge.handle(12, "\27_Ga=T,t=d,f=100,i=42,U=1,c=2,r=1,q=2,m=0;YWJjZA=="))
assert(bridge.handle(11, "\27_Ga=d,d=I,i=42,q=2;"))
equal(#requests, 3, "deletion is suppressed while another buffer uses the image")
assert(bridge.handle(12, "\27_Ga=d,d=I,i=42,q=2;"))
equal(#requests, 4, "the last owner forwards deletion")
equal(requests[4].a, "d", "the forwarded request is a deletion")

assert(bridge.handle(13, "\27_Ga=T,t=f,f=100,i=7,U=1,c=2,r=1,m=0;YWJj"))
equal(#requests, 4, "filename transmission is rejected")

vim.cmd("enew")
vim.fn.termopen({
    "sh",
    "-c",
    [[printf '\033_Ga=T,t=d,f=100,i=99,U=1,c=2,r=1,m=0;YWJjZA==\033\\'; sleep 0.1]],
})
assert(vim.wait(1000, function()
    return vim.iter(requests):any(function(item)
        return item.a == "T" and item.i == 99
    end)
end), "TermRequest autocmd forwards a child APC packet")

bridge.disable()
equal(vim.env.CODEX_NEOVIM_KITTY_BRIDGE, old_capability, "capability env is restored")
equal(vim.env.CODEX_NEOVIM_OUTER_TMUX, old_tmux, "tmux env is restored")

print("codex-kitty-bridge.nvim headless tests passed")
