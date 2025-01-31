# Perec Neovim Plugin

Obsidian in Nvim without depending on Obsidian's existance.

## Prerequisites
- Neovim 0.9+
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [OPTIONAL] [Which-key.nvim](https://github.com/folke/which-key.nvim)
- [krafna](https://github.com/7sedam7/krafna) CLI tool installed (with `PEREC_DIR` env set leading to your vault directory)

## Plugin Managers

### Lazy.nvim
```lua
{
  '7sedam7/perec.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'folke/which-key.nvim' -- optional
  }
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
-- Minimal setup, works out of the box
require('perec')
```

### Custom Configuration
```lua
-- Optional: Override default keymaps
require('perec').setup({
  debug = true,
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
- `<leader>pf`: Find files within Perec vault
- `<leader>pg`: Grep files within Perec vault
- `<leader>pp`: Find krafna queries within Perec vault
- `<leader>pq`: Query files within Perec vault (opens query within cursor if there is one)
- `<leader>pa`: Create a new buffer within Perec vault
- Customize by passing custom keymaps in `.setup()`
