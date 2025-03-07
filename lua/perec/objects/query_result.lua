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

---@return boolean
function QueryResult:is_empty()
	return self.rows == nil or #self.rows == 0
end

---@class QueryResults
---@field results table<number, QueryResult>
---@field keys_to_paths table<string, string>
---@field subkeys_exist table<string, boolean>
local QueryResults = {}
QueryResults.__index = QueryResults

---@param query_results table<number, QueryResult>|nil
function QueryResults:new(query_results)
	local obj = setmetatable({}, self)

	obj.results = query_results or {}
	obj.keys_to_paths = {}
	obj.subkeys_exist = {}

	return obj
end

function QueryResults:is_empty()
	return self.results == nil or next(self.results) == nil
end

---@param keys string
function QueryResults:only_match(keys)
	return self.subkeys_exist[keys] ~= true
end

function QueryResults:clear()
	self.results = {}
	self.keys_to_paths = {}
	self.subkeys_exist = {}
end

-- helper
---@param num number
---@return string
local function generate_keymap_keys(num)
	local s = ""
	while num > 0 do
		num = num - 1
		local remainder = num % 26
		s = string.char(97 + remainder) .. s -- 'a' is ASCII 97
		num = math.floor(num / 26)
	end
	return s
end

---@param keys string
---@param file_path string
function QueryResults:add_quck_keys(keys, file_path)
	self.keys_to_paths[keys] = file_path

	local subkeys = keys:sub(1, #keys - 1)
	for i = 1, #subkeys do
		local prefix = subkeys:sub(1, i)
		self.subkeys_exist[prefix] = true
	end
end

--- Set the quick access keymaps
function QueryResults:set_quick_access_keys()
	if self:is_empty() then
		return
	end

	local line_nums = {}
	for k in pairs(self.results) do
		table.insert(line_nums, k)
	end
	table.sort(line_nums)

	-- Generate key
	local i = 1
	for _, line_num in ipairs(line_nums) do
		local query_result = self.results[line_num]
		for _, row in ipairs(query_result.rows) do
			if row.metadata then
				row.metadata.keys = generate_keymap_keys(i)
				self:add_quck_keys(row.metadata.keys, row.metadata["file.path"])
				i = i + 1
			end
		end
	end
end

---@param line_number number
---@param qr QueryResult
---@return QueryResult
function QueryResults:set(line_number, qr)
	self.results[line_number] = qr
	self:set_quick_access_keys()
	return qr
end

return { QueryResult = QueryResult, QueryResultRow = QueryResultRow, QueryResults = QueryResults }
