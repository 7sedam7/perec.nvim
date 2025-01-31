local telescope_builtin = require('telescope.builtin')

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local config = require("telescope.config").values
local make_entry = require("telescope.make_entry")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local scan = require("plenary.scandir")
local log = require("plenary.log"):new()
log.level = "debug"

local PEREC_DIR = vim.fn.expand(vim.fn.expand("$PEREC_DIR"))

local M = {}

M.find_files = function(opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

  telescope_builtin.find_files(opts)
end

M.grep_files = function(opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

  telescope_builtin.live_grep(opts)
end

-- M.search_notes = function (opts)
--   opts = opts or {}
--   opts.cwd = PEREC_DIR
--
-- end

M.find_queries = function(opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

  local handle = io.popen("krafna --find " .. PEREC_DIR)
  local result = handle:read("*a")
  handle:close()

  local queries = {}
  for line in result:gmatch("[^\r\n]+") do
     table.insert(queries, line)
  end

  pickers.new(opts, {
    finder = finders.new_table({
      results = queries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry,
          ordinal = entry,
        }
      end
    }),
    sorter = config.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        M.query_files({ default_text = entry.value })
      end)
      return true
    end,
    previewer = previewers.new_buffer_previewer({
      title = "Query Preview",
      define_preview = function(self, entry, status)
        local bufnr = self.state.bufnr
        -- Escape single quotes in the query value
        local escaped_value = entry.value:gsub("'", "'\\''")
        -- Build the command with proper shell escaping
        local query = string.format("krafna '%s' --include-fields 'file_name' --from 'FRONTMATTER_DATA(\"%s\")'",
            escaped_value,
            PEREC_DIR:gsub("'", "'\\''"))
        local handle = io.popen(query)
        local result = handle:read("*a")
        handle:close()

        if result == "" then
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"No output from command"})
          return
        end

        -- Try to parse as TSV first
        local has_tabs = result:find("\t")
        local lines = {}

        if has_tabs then
          local max_lengths = {}
          -- First pass to determine number of columns
          local num_columns = 0
          for line in result:gmatch("[^\r\n]+") do
            local count = select(2, line:gsub("\t", "")) + 1
            num_columns = math.max(num_columns, count)
          end

          -- Parse rows with proper empty cell handling
          for line in result:gmatch("[^\r\n]+") do
            local row = {}
            local prev_pos = 1
            for i = 1, num_columns do
              local pos = line:find("\t", prev_pos) or (#line + 1)
              local field = line:sub(prev_pos, pos - 1)
              table.insert(row, field)
              prev_pos = pos + 1
            end
            -- Track max column widths
            for i, field in ipairs(row) do
              max_lengths[i] = math.max(max_lengths[i] or 0, #field)
            end
            table.insert(lines, row)
          end

          -- Format as aligned table with header separator
          local formatted_lines = {}
          for idx, row in ipairs(lines) do
            local formatted_row = {}
            for i, field in ipairs(row) do
              table.insert(formatted_row, string.format("%-" .. (max_lengths[i] or 0) .. "s", field))
            end
            local line = table.concat(formatted_row, " | ")
            table.insert(formatted_lines, line)
            -- Add separator after header (first line)
            if idx == 1 then
              local sep = {}
              for i = 1, #row do
                table.insert(sep, string.rep("-", max_lengths[i]))
              end
              table.insert(formatted_lines, table.concat(sep, "-+-"))
            end
          end
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted_lines)
        else
          -- Fall back to plain text display
          local plain_lines = {}
          for line in result:gmatch("[^\r\n]+") do
            table.insert(plain_lines, line)
          end
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, plain_lines)
        end
      end
    })
  }):find()
end

M.query_files = function (opts)
  opts = opts or {
    default_text = 'WHERE '
  }
  opts.cwd = PEREC_DIR

  -- -- ``` krafna select * from test ```
  -- local code, lang = extract_code_under_cursor()
  -- print(code)

	local file_entry_maker = make_entry.gen_from_file(opts)

	pickers.new(opts, {
    finder = finders.new_dynamic({
        fn = function(prompt)
           local escaped_value = (prompt or ""):gsub("'", "'\\''")
           if #escaped_value < 7 then -- "WHERE a" is a minimal query of size 7
            return {}
           end
           -- Build the command with proper shell escaping
           local query = string.format("krafna '%s' --include-fields 'file_path' --from 'FRONTMATTER_DATA(\"%s\")'", escaped_value, PEREC_DIR:gsub("'", "'\\''"))
           local handle = io.popen(query)
           if not handle then
             vim.notify("Failed to execute krafna command", vim.log.levels.ERROR)
             return {}
           end

           local results = handle:read("*a")
           handle:close()

           -- Parse TSV results                             
           local files = {}
           for line in results:gmatch("[^\r\n]+") do
             local path = line:match("^[^\t]+")
             if path then
               table.insert(files, path)
             end
           end
        if files and files[1] and files[1] == "file_path" then
          table.remove(files, 1)
          return files
        end
	        -- return scan.scan_dir(opts.cwd)
	        return {}
        end,
	     entry_maker = function (entry)
	       local file_entry = file_entry_maker(entry)
	       file_entry.ordinal = vim.fn.fnamemodify(entry, ":t")
	       log.debug(file_entry.ordinal)
	       return file_entry
	     end
	   }),

	   previewer = config.file_previewer(opts),
	 }):find()
end

M.create_doc = function ()
  -- Create a new document in the PEREC_DIR
  local doc_name = vim.fn.input("Enter document name: ")
  if not doc_name:match("%.md$") then
    doc_name = doc_name .. ".md"
  end
  local doc_path = PEREC_DIR .. "/" .. doc_name

  -- Edit the file
  vim.cmd('edit ' .. vim.fn.fnameescape(doc_path))

  -- Add template content
  local template = {
    "```",
    "```",
    "# " .. vim.fn.fnamemodify(doc_path, ":t:r"),  -- Add filename as title
    "",
    "",
  }

  -- Set the lines in buffer
  vim.api.nvim_buf_set_lines(0, 0, -1, false, template)

  -- Move cursor to the end
  vim.api.nvim_win_set_cursor(0, {5, 0})

  -- Start in insert mode
  vim.cmd('startinsert')
end

-- TODO
local function extract_code_under_cursor()
  -- Get cursor position
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Find the code block boundaries
  local start_line = nil
  local end_line = nil
  local in_block = false

  -- Scan up for start of block
  for i = row, 1, -1 do
    local line = lines[i]
    if line:match("```%s*%w+%s*$") then
      start_line = i
      break
    end
  end

  -- Scan down for end of block
  if start_line then
    for i = row, #lines do
      local line = lines[i]
      if line:match("^```%s*$") then
        end_line = i
        break
      end
    end
  end

  -- If we found a complete block
  if start_line and end_line then
    -- Extract language name from opening line
    local lang = lines[start_line]:match("^```%s*(%w+)%s*$")

    -- Get the code content (excluding the ticks and language)
    local code = table.concat(
      vim.list_slice(lines, start_line + 1, end_line - 1),
      "\n"
    )

    return code, lang
  end

  return nil, nil
end

-- log.debug(scan.scan_dir('.', { hidden = true, depth = 5 }))
-- M.find_files()
-- M.grep_files()
-- M.find_queries()
-- M.query_files()
-- M.create_doc()

local function set_default_keymaps()
  vim.api.nvim_set_keymap('n', '<leader>pf', ':lua require("perec").find_files()<CR>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>pg', ':lua require("perec").grep_files()<CR>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>pp', ':lua require("perec").find_queries()<CR>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>pq', ':lua require("perec").query_files()<CR>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>pa', ':lua require("perec").create_doc()<CR>', { noremap = true, silent = true })
end

-- Function to allow users to override key mappings
M.setup = function(opts)
  opts = opts or {}
  if opts.keymaps ~= false then
    set_default_keymaps()
  end
end

-- Automatically call setup with default options if not called by the user
if not M._setup_called then
  M.setup()
  M._setup_called = true
end

return M
