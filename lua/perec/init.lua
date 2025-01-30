local telescope_builtin = require('telescope.builtin')

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local config = require("telescope.config").values
local make_entry = require("telescope.make_entry")

local scan = require("plenary.scandir")
local log = require("plenary.log"):new()
log.level = "debug"

local PEREC_DIR = vim.fn.expand(vim.fn.expand("$PEREC_DIR"))

local M = {}

M.search_files = function(opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

  telescope_builtin.find_files(opts)
end

M.grep_files = function(opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

  telescope_builtin.live_grep(opts)
end

M.search_notes = function (opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

end

M.search_queries = function(opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

  local handle = io.popen("krafna --find " .. PEREC_DIR)
  local result = handle:read("*a")
  handle:close()

  local ok, json = pcall(vim.fn.json_decode, result)
  if not ok then
    vim.notify("Failed to parse krafna output", vim.log.levels.ERROR)
    return
  end

  local queries = {}
  for _, item in ipairs(json) do
    table.insert(queries, item)
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
    previewer = previewers.new_buffer_previewer({
      title = "Query Preview",
      define_preview = function(self, entry, status)
        local bufnr = self.state.bufnr
        -- Escape single quotes in the query value
        local escaped_value = entry.value:gsub("'", "'\\''")
        -- Build the command with proper shell escaping
        local query = string.format("krafna '%s' --from 'FRONTMATTER_DATA(\"%s\")'",
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

M.query_files = function ()
end

M.create_doc = function ()
  -- Create a new document in the PEREC_DIR
  local doc_name = vim.fn.input("Enter document name: ")
  local doc_path = PEREC_DIR .. "/" .. doc_name .. ".md"
  local file = io.open(doc_path, "w")
  if file then
    file:write("# " .. doc_name .. "\n")
    file:close()
    print("Document created at " .. doc_path)
  else
    print("Failed to create document")
  end
end

M.create_note = function ()

end

-- log.debug(scan.scan_dir('.', { hidden = true, depth = 5 }))
-- M.search_files()
-- M.grep_files()
-- M.search_notes()
-- M.search_queries()
M.query_queries()
-- M.create_doc()

return M
