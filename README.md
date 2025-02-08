# Perec Neovim Plugin

![Obsidian in Nvim without depending on Obsidian's existance.](demo.gif)

## Prerequisites
- Neovim 0.9+
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [OPTIONAL] [Which-key.nvim](https://github.com/folke/which-key.nvim)
- [krafna](https://github.com/7sedam7/krafna) CLI tool installed (with `PEREC_DIR` env set leading to your vault directory)

## Plugin Managers

> [!Note]
> You have to call `require('perec').setup()` for plugin to be set up.

### Lazy.nvim
```lua
{
  '7sedam7/perec.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim', -- if Telescope is loaded otherwise, remove from here for faster startup.
    'folke/which-key.nvim' -- optional
  },
  init = function()
    require("perec").setup()
  end,
}
```

### Packer.nvim
```lua
use {
  '7sedam7/perec.nvim',
  requires = {
    'nvim-telescope/telescope.nvim',
    'folke/which-key.nvim' -- optional
  }
}
```

### vim-plug
```lua
call plug#begin()
Plug '7sedam7/perec.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'folke/which-key.nvim' -- optional
call plug#end()
```

## Configuration

### Default Usage
No setup required. The plugin will automatically configure itself.

```lua
-- Minimal setup
require('perec').setup()
```

### Custom Configuration
```lua
-- Optional: Override default keymaps
require('perec').setup({
  cwd = $env.PEREC_DIR,
  keymaps = {
    {
      mode = "n",
      key = "<leader>fx",
      action = require('perec').find_files,
      desc = "your desc"
    }
  }
})
```

## Default Keymaps
- `<leader>pf`: [find_files] Find files within Perec vault
- `<leader>pg`: [grep_files] Grep files within Perec vault
- `<leader>pp`: [find_queries] Find krafna queries within Perec vault
- `<leader>pq`: [query_files] Query files within Perec vault (opens query within cursor if there is one)
- `<leader>pa`: [create_file] Create a new buffer within Perec vault
- Customize by passing custom keymaps in `.setup()`

## Roadmay
(not in priority order, more stuff that benefits this in krafna repo roadmap)
[ ] Add templating support
[ ] Setup working with encrypted files
