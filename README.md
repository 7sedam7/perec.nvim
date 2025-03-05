# Perec Neovim Plugin

![Obsidian in Nvim without depending on Obsidian's existance.](demo.gif)

## Prerequisites
- Neovim 0.9+
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [OPTIONAL] [Which-key.nvim](https://github.com/folke/which-key.nvim)
- [krafna](https://github.com/7sedam7/krafna) CLI tool installed (with `PEREC_DIR` env set leading to your vault directory)

If you are using [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim/tree/4a28c135bc3548e398ba38178fec3f705cb26fe6), it does not conflict with rendering krafna queries. (but it does make the headers have the same color as every other table it renders)

## Features

- Find files within Perec vault
- Execute [krafna](https://github.com/7sedam7/krafna) queries (read more about queries at [krafna](kttps://github.com/7sedam7/krafna))
  - You can query FRONTMATTER data (`FROM FRONTMATTER_DATA('<PEREC_DIR>')`)
  - You can query LINKS (`FROM MD_LINKS('<PEREC_DIR>')`)
  - You can query TASKS (`FROM MD_TASKS('<PEREC_DIR>')`)
- There is a live render of queryies withinr Markdown files if in ``` krafna ``` code block.
  - If cells are "too wide" they will be folded to the next line. Default is 80 characters, but can be changed in options. (`defaults: { max_width = 80 }`)
- If FROM is not specified, default is `FROM FORNTMATTER_DATA('<PEREC_DIR>')`.

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
    defaults = {
        max_width = 80,
        alternate_highlighter = "KrafnaTableRowEven",
    },
    keys = {
        group = {
          key = "<leader>p",
          desc = "Perec functions",
        },
        keymaps = {
          {
            mode = "n",
            key = "<leader>fx",
            action = require('perec').find_files,
            desc = "your desc"
          }
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
- `<leader>pd`: [render_quick_access] Renders quick access letters over the rows of the rendered table. Pressing them will open a file associated with that row in a new buffer.
- Customize by passing custom keymaps in `.setup()`

![Quick Access Demo](quick_access_demo.mp4)

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
