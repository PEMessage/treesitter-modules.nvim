---@class ts.mod.nodes.Entry
---@field tick integer
---@field ranges ts.mod.Range[]

---@class ts.mod.Nodes
---@field private entries table<integer, ts.mod.nodes.Entry>
local Nodes = {}
Nodes.__index = Nodes

---@return ts.mod.Nodes
function Nodes.new()
    local self = setmetatable({}, Nodes)
    self.entries = {}
    return self
end

---@param buf integer
---@param range ts.mod.Range
function Nodes:push(buf, range)
    local ranges = self:get(buf)
    ranges[#ranges + 1] = range
end

---@param buf integer
---@return ts.mod.Range?
function Nodes:pop(buf)
    local ranges = self:get(buf)
    if #ranges > 0 then
        ranges[#ranges] = nil
    end
    return ranges[#ranges]
end

---@param buf integer
---@return ts.mod.Range?
function Nodes:last(buf)
    local ranges = self:get(buf)
    return ranges[#ranges]
end

---@param buf integer
function Nodes:clear(buf)
    self.entries[buf] = nil
end

---@private
---@param buf integer
---@return ts.mod.Range[]
function Nodes:get(buf)
    -- clear ranges on change tick, calling any methods on invalid nodes causes
    -- neovim to hard crash
    local entry = self.entries[buf]
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    if not entry or entry.tick ~= tick then
        entry = { tick = tick, ranges = {} }
        self.entries[buf] = entry
    end
    return entry.ranges
end

return Nodes
