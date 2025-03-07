local bit = require("bit")

local M = {}

--- Generate subtle highlights based on foreground and background colors
--- @param original_fg number|nil The original foreground color as an integer
--- @param original_bg number|nil The original background color as an integer
--- @return table|nil The generated highlight attributes or nil if background is invalid
local function generate_subtle_highlights(original_fg, original_bg)
	-- Convert integer to RGB
	--- @param int_color number|nil The color as an integer
	--- @return table|nil The RGB components or nil if color is invalid
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
	--- @param rgb table The RGB components {r,g,b}
	--- @return number The integer representation of the RGB color
	local function rgb_to_int(rgb)
		return bit.bor(bit.lshift(rgb.r, 16), bit.lshift(rgb.g, 8), rgb.b)
	end

	-- Subtle lightness adjustment
	--- @param rgb table The RGB components {r,g,b}
	--- @param factor number The adjustment factor for lightness
	--- @return table The adjusted RGB components
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

--- Create a set of subtle highlights based on an existing highlighter
--- @param highlighter string The name of the highlight group to base new highlights on
--- @return table|nil The generated highlight attributes or nil if unable to generate highlights
local function create_similar_highlighter(highlighter)
	local hl = vim.api.nvim_get_hl(0, { name = highlighter })
	if hl == nil or hl.fg == nil or hl.bg == nil then
		hl = vim.api.nvim_get_hl(0, { name = "Normal" })
	end

	return generate_subtle_highlights(hl.fg, hl.bg)
end

--- Set up all custom highlighters
--- @return nil
M.setup_highlighters = function()
	vim.api.nvim_set_hl(0, "KrafnaTableNull", { fg = "#FF0000" })
	-- vim.api.nvim_set_hl(0, "KrafnaTableRowEven", { reverse = true })
	vim.api.nvim_set_hl(0, "KrafnaTableRowEven", create_similar_highlighter("Conceal"))
	vim.api.nvim_set_hl(0, "HopNextKey", { fg = "#FFD700", bold = true })
end

return M
