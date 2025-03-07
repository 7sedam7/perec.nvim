-- local log = require("plenary.log"):new()
-- log.level = "debug"

local PEREC_DIR = vim.fn.expand(vim.fn.expand("$PEREC_DIR"))
local has_whichkey, whichkey = pcall(require, "which-key")

local finders = require("perec.finders")
local renderer = require("perec.renderer")
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
------ Krafna Preview (should extractc this to a separate file) ----------------
--------------------------------------------------------------------------------

local function cleanup_buffer_maps_and_cache()
	if has_whichkey then
		whichkey.add({ { "<leader>pd", nil, desc = "", mode = "n", hidden = true } })
	end
	pcall(vim.keymap.del, "n", "<leader>pd")

	renderer.cleanup_state()
end

local function generate_subtle_highlights(original_fg, original_bg)
	-- Convert integer to RGB
	local function int_to_rgb(int_color)
		if not int_color or int_color == -1 then
			return nil
		end
		return {
			r = bit.band(bit.rshift(int_color, 16), 0xFF),
			g = bit.band(bit.rshift(int_color, 8), 0xFF),
			b = bit.band(int_color, 0xFF),
		}
	end

	-- Convert RGB to integer
	local function rgb_to_int(rgb)
		return bit.bor(bit.lshift(rgb.r, 16), bit.lshift(rgb.g, 8), rgb.b)
	end

	-- Subtle lightness adjustment
	local function adjust_lightness(rgb, factor)
		return {
			r = math.min(255, math.max(0, math.floor(rgb.r * factor))),
			g = math.min(255, math.max(0, math.floor(rgb.g * factor))),
			b = math.min(255, math.max(0, math.floor(rgb.b * factor))),
		}
	end

	local orig_bg_rgb = int_to_rgb(original_bg)
	if not orig_bg_rgb then
		return nil
	end

	-- Create two very subtle variations
	local subtle_lighter = adjust_lightness(orig_bg_rgb, 1.3)
	local subtle_darker = adjust_lightness(orig_bg_rgb, -1.3)

	return {
		fg = original_fg,
		bg = vim.o.background == "light" and rgb_to_int(subtle_darker) or rgb_to_int(subtle_lighter),
	}
end

local function create_similar_highlighter(highlighter)
	local hl = vim.api.nvim_get_hl(0, { name = highlighter })
	if hl == nil or hl.fg == nil or hl.bg == nil then
		hl = vim.api.nvim_get_hl(0, { name = "Normal" })
	end

	return generate_subtle_highlights(hl.fg, hl.bg)
end

local last_called = {}
local render_delay = 500
local function setup_rendering(opts)
	local group = vim.api.nvim_create_augroup("KrafnaPreview", { clear = true })

	vim.api.nvim_set_hl(0, "KrafnaTableNull", { fg = "#FF0000" })
	-- vim.api.nvim_set_hl(0, "KrafnaTableRowEven", { reverse = true })
	vim.api.nvim_set_hl(0, "KrafnaTableRowEven", create_similar_highlighter("Conceal"))
	vim.api.nvim_set_hl(0, "HopNextKey", { fg = "#FFD700", bold = true })
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
						renderer.update_virtual_text(opts)
					end
				end
			end,
		}
	)
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		group = group,
		pattern = { "*.md" },
		callback = function(_)
			cleanup_buffer_maps_and_cache()
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

	setup_keymaps(config)
	setup_rendering(opts)
end

M.setup()

return M
