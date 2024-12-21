local telescope_builtin = require('telescope.builtin')

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local putils = require('telescope.previewers.utils')
local config = require("telescope.config").values
local make_entry = require("telescope.make_entry")

local scan = require("plenary.scandir")
local log = require("plenary.log"):new()
log.level = "debug"

local PEREC_DIR = vim.fn.expand('$PEREC_DIR')

local M = {}

M.search_files = function(opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR

  local file_entry_maker = make_entry.gen_from_file(opts)

	pickers.new(opts, {
    finder = finders.new_table({
      results = scan.scan_dir(opts.cwd),
      entry_maker = function (entry)
        local file_entry = file_entry_maker(entry)
        --file_entry.value = entry
        file_entry.ordinal = vim.fn.fnamemodify(entry, ":t")
        log.debug(file_entry.ordinal)
        return file_entry
      end
    }),

    previewer = config.file_previewer(opts),

    sorter = config.generic_sorter(opts),
  }):find()
  -- telescope_builtin.find_files(opts)
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

M.data_view = function (opts)
  opts = opts or {}
  opts.cwd = PEREC_DIR
end

M.create_doc = function ()

end

M.create_note = function ()

end

-- log.debug(scan.scan_dir('.', { hidden = true, depth = 5 }))
-- M.search_files()
-- M.grep_files()
M.search_notes()

return M
