# Perec Neovim Plugin

![Obsidian in Nvim without depending on Obsidian's existance.](demo.gif)

## Prerequisites
- Neovim 0.9+
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [OPTIONAL] [Which-key.nvim](https://github.com/folke/which-key.nvim)
- [krafna](https://github.com/7sedam7/krafna) CLI tool installed (with `PEREC_DIR` env set leading to your vault directory)

If you are using [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim/tree/4a28c135bc3548e398ba38178fec3f705cb26fe6), it does not conflict with rendering krafna queries. (but it does make the headers have the same color as every other table it renders)

## Installation with Plugin Managers

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

There is a live preview of the query as extmap bellow the query, that get's updated on save and buffer open/enter/...

## Roadmay
(not in priority order, more stuff that benefits this in krafna repo roadmap)
- [ ] Extract picker logic so it can be used by snacks and mini
- [ ] Add templating support
- [ ] Setup working with encrypted files

## Acknowledgements

- [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim/tree/4a28c135bc3548e398ba38178fec3f705cb26fe6) for table formatting inspiration
- [CodeRabbit](https://coderabbit.io) for code reviews
- Various AI tools for help with answering questions faster then me searching on Google/StackOverflow


## Author

[7sedam7](https://github.com/7sedam7)
