-- local log = require("plenary.log"):new()
-- log.level = "debug"

---@class QueryResultRow
---@field data table {string}
---@field metadata table
local QueryResultRow = {}
QueryResultRow.__index = QueryResultRow

function QueryResultRow:new(data, metadata)
	local obj = setmetatable({}, self)

	obj.data = data
	obj.metadata = metadata

	return obj
end

---@class QueryResult
---@field header table {string}
---@field rows QueryResultRow[]
local QueryResult = {}
QueryResult.__index = QueryResult

function QueryResult:new(header, data)
	local obj = setmetatable({}, self)

	obj.header = header
	obj.rows = data
	-- obj.data = vim.fn.slice(data, 2, #data)

	return obj
end

function QueryResult:is_empty()
	return self.rows == nil or #self.rows == 0
end

return { QueryResult = QueryResult, QueryResultRow = QueryResultRow }
