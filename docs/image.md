# 🍿 image

![Image](https://github.com/user-attachments/assets/4e8a686c-bf41-4989-9d74-1641ecf2835f)

## ✨ Features

- Image viewer using the [Kitty Graphics Protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/).
- open images in a wide range of formats:
  `pdf`, `png`, `jpg`, `jpeg`, `gif`, `bmp`, `webp`, `tiff`, `heic`, `avif`, `mp4`, `mov`, `avi`, `mkv`, `webm`
- Supports inline image rendering in:
  `markdown`, `html`, `norg`, `tsx`, `javascript`, `css`, `vue`, `svelte`, `scss`, `latex`, `typst`
- LaTex math expressions in `markdown` and `latex` documents

Terminal support:

- [kitty](https://sw.kovidgoyal.net/kitty/)
- [ghostty](https://ghostty.org/)
- [wezterm](https://wezfurlong.org/wezterm/)
  Wezterm has only limited support for the kitty graphics protocol.
  Inline image rendering is not supported.
- [tmux](https://github.com/tmux/tmux)
  Snacks automatically tries to enable `allow-passthrough=on` for tmux,
  but you may need to enable it manually in your tmux configuration.
- [zellij](https://github.com/zellij-org/zellij) is **not** supported,
  since they don't have any support for passthrough

Image will be transferred to the terminal by filename or by sending the image
date in case `ssh` is detected.

In some cases you may need to force snacks to detect or not detect a certain
environment. You can do this by setting `SNACKS_${ENV_NAME}` to `true` or `false`.

For example, to force detection of **ghostty** you can set `SNACKS_GHOSTTY=true`.

In order to automatically display the image when opening an image file,
or to have imaged displayed in supported document formats like `markdown` or `html`,
you need to enable the `image` plugin in your `snacks` config.

[ImageMagick](https://imagemagick.org/index.php) is required to convert images
to the supported formats (all except PNG).

In case of issues, make sure to run `:checkhealth snacks`.

<!-- docgen -->

## 📦 Setup

```lua
-- lazy.nvim
{
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    image = {
      -- your image configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    }
  }
}
```

## ⚙️ Config

```lua
---@class snacks.image.Config
---@field enabled? boolean enable image viewer
---@field wo? vim.wo|{} options for windows showing the image
---@field bo? vim.bo|{} options for the image buffer
---@field formats? string[]
--- Resolves a reference to an image with src in a file (currently markdown only).
--- Return the absolute path or url to the image.
--- When `nil`, the path is resolved relative to the file.
---@field resolve? fun(file: string, src: string): string?
---@field convert? snacks.image.convert.Config
{
  formats = {
    "png",
    "jpg",
    "jpeg",
    "gif",
    "bmp",
    "webp",
    "tiff",
    "heic",
    "avif",
    "mp4",
    "mov",
    "avi",
    "mkv",
    "webm",
    "pdf",
  },
  force = false, -- try displaying the image, even if the terminal does not support it
  doc = {
    -- enable image viewer for documents
    -- a treesitter parser must be available for the enabled languages.
    enabled = true,
    -- render the image inline in the buffer
    -- if your env doesn't support unicode placeholders, this will be disabled
    -- takes precedence over `opts.float` on supported terminals
    inline = true,
    -- render the image in a floating window
    -- only used if `opts.inline` is disabled
    float = true,
    max_width = 80,
    max_height = 40,
    -- Set to `true`, to conceal the image text when rendering inline.
    -- (experimental)
    ---@param lang string tree-sitter language
    ---@param type snacks.image.Type image type
    conceal = function(lang, type)
      -- only conceal math expressions
      return type == "math"
    end,
  },
  img_dirs = { "img", "images", "assets", "static", "public", "media", "attachments" },
  -- window options applied to windows displaying image buffers
  -- an image buffer is a buffer with `filetype=image`
  wo = {
    wrap = false,
    number = false,
    relativenumber = false,
    cursorcolumn = false,
    signcolumn = "no",
    foldcolumn = "0",
    list = false,
    spell = false,
    statuscolumn = "",
  },
  cache = vim.fn.stdpath("cache") .. "/snacks/image",
  debug = {
    request = false,
    convert = false,
    placement = false,
  },
  env = {},
  -- icons used to show where an inline image is located that is
  -- rendered below the text.
  icons = {
    math = "󰪚 ",
    chart = "󰄧 ",
    image = " ",
  },
  ---@class snacks.image.convert.Config
  convert = {
    notify = true, -- show a notification on error
    ---@type snacks.image.args
    mermaid = function()
      local theme = vim.o.background == "light" and "neutral" or "dark"
      return { "-i", "{src}", "-o", "{file}", "-b", "transparent", "-t", theme, "-s", "{scale}" }
    end,
    ---@type table<string,snacks.image.args>
    magick = {
      default = { "{src}[0]", "-scale", "1920x1080>" }, -- default for raster images
      vector = { "-density", 192, "{src}[0]" }, -- used by vector images like svg
      math = { "-density", 192, "{src}[0]", "-trim" },
      pdf = { "-density", 192, "{src}[0]", "-background", "white", "-alpha", "remove", "-trim" },
    },
  },
  math = {
    enabled = true, -- enable math expression rendering
    -- in the templates below, `${header}` comes from any section in your document,
    -- between a start/end header comment. Comment syntax is language-specific.
    -- * start comment: `// snacks: header start`
    -- * end comment:   `// snacks: header end`
    typst = {
      tpl = [[
        #set page(width: auto, height: auto, margin: (x: 2pt, y: 2pt))
        #show math.equation.where(block: false): set text(top-edge: "bounds", bottom-edge: "bounds")
        #set text(size: 12pt, fill: rgb("${color}"))
        ${header}
        ${content}]],
    },
    latex = {
      font_size = "Large", -- see https://www.sascha-frank.com/latex-font-size.html
      -- for latex documents, the doc packages are included automatically,
      -- but you can add more packages here. Useful for markdown documents.
      packages = { "amsmath", "amssymb", "amsfonts", "amscd", "mathtools" },
      tpl = [[
        \documentclass[preview,border=0pt,varwidth,12pt]{standalone}
        \usepackage{${packages}}
        \begin{document}
        ${header}
        { \${font_size} \selectfont
          \color[HTML]{${color}}
        ${content}}
        \end{document}]],
    },
  },
}
```

## 🎨 Styles

Check the [styles](https://github.com/folke/snacks.nvim/blob/main/docs/styles.md)
docs for more information on how to customize these styles

### `snacks_image`

```lua
{
  relative = "cursor",
  border = "rounded",
  focusable = false,
  backdrop = false,
  row = 1,
  col = 1,
  -- width/height are automatically set by the image size unless specified below
}
```

## 📚 Types

```lua
---@alias snacks.image.Size {width: number, height: number}
---@alias snacks.image.Pos {[1]: number, [2]: number}
---@alias snacks.image.Loc snacks.image.Pos|snacks.image.Size|{zindex?: number}
---@alias snacks.image.Type "image"|"math"|"chart"
```

```lua
---@class snacks.image.Env
---@field name string
---@field env table<string, string|true>
---@field supported? boolean default: false
---@field placeholders? boolean default: false
---@field setup? fun(): boolean?
---@field transform? fun(data: string): string
---@field detected? boolean
---@field remote? boolean this is a remote client, so full transfer of the image data is required
```

```lua
---@class snacks.image.Opts
---@field pos? snacks.image.Pos (row, col) (1,0)-indexed. defaults to the top-left corner
---@field range? Range4
---@field conceal? boolean
---@field inline? boolean render the image inline in the buffer
---@field width? number
---@field min_width? number
---@field max_width? number
---@field height? number
---@field min_height? number
---@field max_height? number
---@field on_update? fun(placement: snacks.image.Placement)
---@field on_update_pre? fun(placement: snacks.image.Placement)
---@field type? snacks.image.Type
---@field auto_resize? boolean
```

## 📦 Module

```lua
---@class snacks.image
---@field terminal snacks.image.terminal
---@field image snacks.Image
---@field placement snacks.image.Placement
---@field util snacks.image.util
---@field buf snacks.image.buf
---@field doc snacks.image.doc
---@field convert snacks.image.convert
---@field inline snacks.image.inline
Snacks.image = {}
```

### `Snacks.image.hover()`

Show the image at the cursor in a floating window

```lua
Snacks.image.hover()
```

### `Snacks.image.langs()`

```lua
---@return string[]
Snacks.image.langs()
```

### `Snacks.image.supports()`

Check if the file format is supported and the terminal supports the kitty graphics protocol

```lua
---@param file string
Snacks.image.supports(file)
```

### `Snacks.image.supports_file()`

Check if the file format is supported

```lua
---@param file string
Snacks.image.supports_file(file)
```

### `Snacks.image.supports_terminal()`

Check if the terminal supports the kitty graphics protocol

```lua
Snacks.image.supports_terminal()
```
