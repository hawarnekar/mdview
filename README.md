# mdview

A standalone Vim plugin that renders markdown files in a read-only scratch
buffer with properly formatted headers, tables, lists, code blocks, and
inline styling. Pure Vimscript, no external dependencies, works in Vim 8+
and Neovim.

## Install

Using your favorite plugin manager, point it at this directory or repo.
With vim-plug:

```vim
Plug 'hawarnekar/mdview'
```

Or copy the `plugin/`, `autoload/`, `syntax/`, and `doc/` folders into your
`~/.vim/` (Vim) or `~/.config/nvim/` (Neovim).

After install:

```vim
:helptags ALL
```

## Usage

Open any `.md` file — the formatted view appears automatically. Inside the
view:

| Key      | Action                              |
|----------|-------------------------------------|
| `q a i`  | Close view, return to raw markdown  |
| `gx`     | Open the URL near the cursor        |
| `]]`     | Jump to next header                 |
| `[[`     | Jump to previous header             |
| `zo zc`  | Open/close fold at cursor           |
| `zM zR`  | Fold all / open all                 |

Commands:

```vim
:MdView                 " open the view
:MdViewToggle           " toggle on/off
:MdViewExport out.txt   " save rendered output to file
```

## Configuration

```vim
let g:mdview_max_col_width = 20       " max chars per table column
let g:mdview_max_width = -1           " overall width; -1 = winwidth
let g:mdview_open = 'replace'         " 'replace'|'split'|'vsplit'|'tab'
let g:mdview_strip_html = 1           " strip <br>, <sup>, etc.
let g:mdview_auto_refresh = 1         " re-render when source changes
let g:mdview_colors = {}              " override highlight groups
```

User hooks:

```vim
autocmd User MdViewPreRender  echo 'about to render'
autocmd User MdViewPostRender echo 'render complete'
```

## Supported markdown

- ATX headers (`#`–`######`) and Setext (`===`/`---` underlines)
- Tables with column alignment (`|:---:|---:|:---|`) and cell wrapping
- Fenced code blocks with language label
- Bold (`**` / `__`), italic (`*` / `_`), strikethrough (`~~`),
  inline code (`` ` ``)
- Triple emphasis `***bold italic***`
- Inline links `[text](url)`, reference links `[text][ref]`, auto-links
  `<http://example.com>`, images `![alt](url)`
- Bullet lists (`-`, `*`, `+`), numbered, nested
- Task lists (`- [ ]`, `- [x]`)
- Blockquotes (`>`)
- Horizontal rules (`---`, `***`, `___`)
- YAML/TOML front matter (between `---` or `+++` at top of file)
- Footnotes (`[^N]` and `[^N]: definition`)
- Definition lists (`term\n: definition`)
- Math `$inline$` and `$$display$$`

## License

MIT.
