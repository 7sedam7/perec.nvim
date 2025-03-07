---@class CodeBlock
local State = {
	---@type CodeBlock[]
	code_blocks = {},
	---@type table<number, QueryResult>
	query_results = {},
}

State.set_value = function(key, value)
	State[key] = value
end

State.get_value = function(key)
	return State[key]
end

return State
