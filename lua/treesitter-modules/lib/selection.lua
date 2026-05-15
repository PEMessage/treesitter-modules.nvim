local Range = require('treesitter-modules.lib.range')
local util = require('treesitter-modules.lib.util')

---@class ts.mod.Selection
local M = {}

---@private
M.nodes = require('treesitter-modules.lib.nodes').new()

---@param buf integer
---@param language string
function M.init_selection(buf, language)
    local parser = M.parse(buf, language)
    if not parser then
        return
    end
    local node = vim.treesitter.get_node({
        bufnr = buf,
        ignore_injections = false,
    })
    if node then
        M.nodes:push(buf, Range.node(node))
        M.select(Range.node(node))
    end
end

---@private
---@param node TSNode
---@return TSNode?
---@return TSNode?
function M.same_type_sibling_range(node)
    local parent = node:parent()
    if not parent then
        return nil, nil
    end
    local node_type = node:type()
    local index = -1
    for i = 0, parent:named_child_count() - 1 do
        if parent:named_child(i):id() == node:id() then
            index = i
            break
        end
    end
    if index < 0 then
        return nil, nil
    end

    local first = index
    while first > 0 do
        local sibling = parent:named_child(first - 1)
        if not sibling or sibling:type() ~= node_type then
            break
        end
        first = first - 1
    end

    local last = index
    while last < parent:named_child_count() - 1 do
        local sibling = parent:named_child(last + 1)
        if not sibling or sibling:type() ~= node_type then
            break
        end
        last = last + 1
    end

    return parent:named_child(first), parent:named_child(last)
end


---@param buf integer
---@param language string
function M.node_incremental(buf, language)
    M.incremental(buf, language, function(parser, node)
        return node:parent()
    end)
end

---@param buf integer
---@param language string
function M.scope_incremental(buf, language)
    M.incremental(buf, language, function(parser, node)
        if language ~= parser:lang() then
            -- only handle scope for root language
            return nil
        end
        local scopes = M.scopes(buf, language, parser:trees()[1]:root())
        if #scopes == 0 then
            return nil
        end
        local result = node:parent()
        while result and not vim.tbl_contains(scopes, result) do
            result = result:parent()
        end
        assert(result ~= node, 'infinite loop')
        return result
    end)
end

---@private
---@param buf integer
---@param language string
---@param parent fun(parser: vim.treesitter.LanguageTree, node: TSNode): TSNode?
function M.incremental(buf, language, parent)
    local parser = M.parse(buf, language)
    if not parser then
        return
    end

    local range = Range.visual()
    local last = M.nodes:last(buf)
    local node = nil ---@type TSNode?


    if not last or not range:same(last) then
        -- handle re-initialization
        node = parser:named_node_for_range(range:ts(), {
            ignore_injections = false,
        })
        M.nodes:clear(buf)
        if node then
            M.nodes:push(buf, Range.node(node))
            M.select(Range.node(node))
        end
        return
    end

    local rnode = parser:named_node_for_range(last:ts(), {
        ignore_injections = false,
    })
    local first_sibling, last_sibling = M.same_type_sibling_range(rnode)

    if rnode and first_sibling and last_sibling then
        if first_sibling:id() ~= rnode:id() or last_sibling:id() ~= rnode:id() then
            local start_range = Range.node(first_sibling)
            local end_range = Range.node(last_sibling)
            vim.print(start_range:cursor_start())
            vim.print(end_range:cursor_end())
            local expanded = Range.new({
                start_range.range[1],
                start_range.range[2],
                end_range.range[3],
                end_range.range[4],
            })
            M.nodes:push(buf, expanded)
            M.select(expanded)
            return
        end
    end

    -- iterate through parent parsers and nodes until we find a node with
    -- a different range
    parser = parser:language_for_range(range:ts())
    while parser and not node do
        node = parser:named_node_for_range(range:ts())
        while node and range:same(Range.node(node)) do
            node = parent(parser, node)
        end
        parser = parser:parent()
    end
    if node then
        M.nodes:push(buf, Range.node(node))
        M.select(Range.node(node))
    end
end

---@private
---@param buf integer
---@param language string
---@param root TSNode
---@return TSNode[]
function M.scopes(buf, language, root)
    if not util.has_query(language, 'locals') then
        return {}
    end
    local query = vim.treesitter.query.get(language, 'locals')
    if not query then
        return {}
    end
    local result = {} ---@type TSNode[]
    local start, _, stop, _ = root:range()
    for _, match in query:iter_matches(root, buf, start, stop + 1) do
        for id, nodes in pairs(match) do
            local capture = query.captures[id]
            if capture == 'local.scope' then
                for _, node in ipairs(nodes) do
                    result[#result + 1] = node
                end
            end
        end
    end
    return result
end

---@param buf integer
---@param language string
function M.node_decremental(buf, language)
    -- NOTE: if a user does incremental selection, moves the cursor, enters
    -- visual mode, then triggers this function, they will still jump back to
    -- their previous selection, this behavior matches the original.
    local range = M.nodes:pop(buf)
    if range then
        M.select(range)
    end
end

---@private
---@param buf integer
---@param language string
---@return vim.treesitter.LanguageTree?
function M.parse(buf, language)
    local has, parser = pcall(vim.treesitter.get_parser, buf, language)
    if not has or not parser then
        return nil
    end
    -- 1-indexed inclusive -> 0-indexed exclusive
    local first, last = vim.fn.line('w0'), vim.fn.line('w$')
    parser:parse({ first - 1, last })
    return parser
end

---@private
---@param range ts.mod.Range
function M.select(range)
    if vim.api.nvim_get_mode().mode ~= 'v' then
        vim.cmd.normal({ 'v', bang = true })
    end
    vim.api.nvim_win_set_cursor(0, range:cursor_start())
    vim.cmd.normal({ 'o', bang = true })
    vim.api.nvim_win_set_cursor(0, range:cursor_end())
end

return M
