local M = {}

local APC_PREFIX = "\27_G"

---@param value string
---@return string|number
local function scalar(value)
    if value:match("^%-?%d+$") then
        return tonumber(value) or value
    end
    return value
end

---@param sequence unknown
---@return table<string, string|number>?
---@return string?
function M.parse(sequence)
    if type(sequence) ~= "string" or sequence:sub(1, #APC_PREFIX) ~= APC_PREFIX then
        return nil, "not a Kitty graphics APC request"
    end

    local body = sequence:sub(#APC_PREFIX + 1)
    local separator = body:find(";", 1, true)
    local control = separator and body:sub(1, separator - 1) or body
    local payload = separator and body:sub(separator + 1) or nil
    if control == "" then
        return nil, "missing Kitty graphics control data"
    end

    local request = {}
    for field in control:gmatch("[^,]+") do
        local key, value = field:match("^([%a])=(.*)$")
        if not key or value == "" then
            return nil, ("invalid Kitty graphics field: %s"):format(field)
        end
        if request[key] ~= nil then
            return nil, ("duplicate Kitty graphics field: %s"):format(key)
        end
        request[key] = scalar(value)
    end
    if payload ~= nil then
        request.data = payload
    end
    return request
end

---@param payload unknown
---@return boolean
function M.is_base64(payload)
    return type(payload) == "string" and payload:match("^[A-Za-z0-9+/=]*$") ~= nil
end

return M
