-- local log = require("plenary.log"):new()
-- log.level = "debug"

local PEREC_DIR = vim.fn.expand(vim.fn.expand("$PEREC_DIR"))
local has_whichkey, whichkey = pcall(require, "which-key")

local krafna = require("perec.krafna")
local QueryResults = require("perec.objects.query_result").QueryResults
local finders = require("perec.finders")
local renderer = require("perec.renderer")
local highlighters = require("perec.highlighters")
local CodeBlock = require("perec.objects.code_block")

local M = {}

M.find_files = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR

	finders.find_files(opts)
end

M.grep_files = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR

	finders.grep_files(opts)
end

M.find_queries = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR

	finders.find_queries(opts)
end

M.query_files = function(opts)
	local code_under_cursor = CodeBlock.get_under_cursor()
	opts = opts or {
		default_text = code_under_cursor and code_under_cursor.content or "WHERE ",
	}
	opts.cwd = opts.cwd or PEREC_DIR

	finders.query_files(opts)
end

M.create_file = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR

	-- Create a new document in the PEREC_DIR
	local filename = vim.fn.input("Enter document name: ")
	if not filename:match("%.md$") then
		filename = filename .. ".md"
	end
	local filepath = opts.cwd .. "/" .. filename

	-- Edit the file
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))

	-- check if file exists
	local stat = vim.loop.fs_stat(filepath)
	if stat and stat.type == "file" then
	else
		-- Add template content
		local template = {
			"---",
			"tags:",
			"---",
			"",
			"# " .. vim.fn.fnamemodify(filepath, ":t:r"), -- Add filename as title
			"",
			"",
		}

		-- Set the lines in buffer
		vim.api.nvim_buf_set_lines(0, 0, -1, false, template)

		-- Move cursor to the end
		vim.api.nvim_win_set_cursor(0, { 6, 0 })

		-- Start in insert mode
		vim.cmd("startinsert")
	end
end

local config = {
	group = {
		key = "<leader>p",
		desc = "Perec functions",
	},
	keymaps = {
		{
			key = "<leader>pf",
			action = M.find_files,
			mode = "n",
			desc = "Find files within Perec vault",
		},
		{
			key = "<leader>pg",
			action = M.grep_files,
			mode = "n",
			desc = "Grep files within Perec vault",
		},
		{
			key = "<leader>pp",
			action = M.find_queries,
			mode = "n",
			desc = "Find krafna queries within Perec vault",
		},
		{
			key = "<leader>pq",
			action = M.query_files,
			mode = "n",
			desc = "Query files within Perec vault",
		},
		{
			key = "<leader>pa",
			action = M.create_file,
			mode = "n",
			desc = "Create a buffer within Perec vault",
		},
	},
}

--------------------------------------------------------------------------------
-------------------------------- Setup -----------------------------------------
--------------------------------------------------------------------------------

--- @type QueryResults
local query_results = nil

local function get_char_with_timeout(timeout_ms)
	local char = nil
	vim.fn.wait(timeout_ms, function()
		local _char = vim.fn.getchar(0)
		if _char ~= 0 then
			char = _char
			return true
		end
		return false
	end)
	return char
end

local function render_quick_access(opts)
	opts = opts or {}

	local lookup_keys = ""
	while true do
		renderer.redraw(query_results, lookup_keys)
		vim.cmd("redraw")

		local key = get_char_with_timeout(1000)
		if key == nil then
			break
		end
		local char = vim.fn.nr2char(key)

		if char == "\27" then -- ESC key
			break
		end

		lookup_keys = lookup_keys .. char
		if query_results:only_match(lookup_keys) then
			break
		end
	end

	renderer.redraw(query_results)

	if query_results.keys_to_paths[lookup_keys] then
		vim.cmd("e " .. query_results.keys_to_paths[lookup_keys])
	end

	return true
end

local function update_virtual_text(opts)
	opts = opts or {}
	opts.from_cache = opts.from_cache or false

	query_results = QueryResults:new()
	local blocks = CodeBlock.find_within_buffer("krafna")

	for _, block in ipairs(blocks) do
		local block_end = block.start_line + block.num_lines

		if not opts.from_cache then
			local query_result = query_results:set(
				block_end,
				krafna.execute(block.content, { cwd = opts.cwd, metadata_fields = { "file.path" } })
			)

			if not query_result:is_empty() then
				-- Set keymaps
				if has_whichkey then
					whichkey.add({
						{ "<leader>pd", nil, desc = "Go to file from query preview", mode = "n", hidden = false },
					})
				end
				vim.keymap.set("n", "<leader>pd", render_quick_access, {
					desc = "Go to file from query preview",
					noremap = true,
					silent = true,
				})
			end
		end
	end
	renderer.redraw(query_results, opts.lookup_keys)
end

local last_called = {}
local render_delay = 500
local function setup_autocmds(opts)
	local group = vim.api.nvim_create_augroup("KrafnaPreview", { clear = true })

	vim.api.nvim_create_autocmd(
		{ "BufEnter", "BufWinEnter", "WinEnter", "TabEnter", "BufNewFile", "BufWritePost", "BufReadPost", "FileType" },
		{
			group = group,
			pattern = { "*.md" },
			callback = function(_)
				local buff_id = vim.api.nvim_get_current_buf()
				local current_time = vim.loop.now()
				local last_time = last_called[buff_id] or 0

				-- Only proceed if enough time has passed since last call
				if (current_time - last_time) >= render_delay then
					-- Only trigger if the buffer is a real file or new file
					local bufnr = vim.api.nvim_get_current_buf()
					local buftype = vim.bo[bufnr].buftype
					local filename = vim.api.nvim_buf_get_name(bufnr)

					if buftype == "" and (filename ~= "" or vim.fn.exists("#BufNewFile<buffer>")) then
						last_called[buff_id] = current_time
						update_virtual_text(opts)
					end
				end
			end,
		}
	)
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		group = group,
		pattern = { "*.md" },
		callback = function(_)
			if has_whichkey then
				whichkey.add({ { "<leader>pd", nil, desc = "", mode = "n", hidden = true } })
			end
			pcall(vim.keymap.del, "n", "<leader>pd")

			query_results:clear()
		end,
	})
end

local function setup_keymaps(config)
	-- Use which-key if available
	if has_whichkey then
		whichkey.add({ { config.group.key, group = config.group.desc } })
	end
	for _, keymap in ipairs(config.keymaps) do
		local mode = keymap.mode or "n"
		local key = keymap.key
		local action = keymap.action
		local desc = keymap.desc

		-- Use which-key if available
		if has_whichkey then
			whichkey.add({ { key, action, desc = desc, mode = mode, hidden = false } })
		else
			-- Fallback to standard vim.keymap
			vim.keymap.set(mode, key, action, {
				desc = desc,
				noremap = keymap.noremap or true,
				silent = keymap.silent or true,
			})
		end
	end
end

-- Check for required CLI tool
local function check_cli_tool()
	local result = vim.fn.system("command -v krafna")

	if result == "" then
		error("CLI tool 'krafna' is not installed. Please install it before using this plugin.")
	end
end

-- Setup function
function M.setup(opts)
	opts = opts or { keys = {} }
	opts.cwd = opts.cwd or PEREC_DIR

	check_cli_tool()

	-- Merge user options with defaults
	config = vim.tbl_deep_extend("force", config, opts.keys)

	highlighters.setup_highlighters()
	setup_keymaps(config)
	setup_autocmds(opts)
end

-- M.setup()

return M
