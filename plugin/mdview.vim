if exists('g:loaded_mdview') || &compatible
  finish
endif

if !exists('*matchaddpos')
  echohl WarningMsg
  echom 'mdview: requires Vim 7.4.330+ (matchaddpos not available)'
  echohl None
  finish
endif

let g:loaded_mdview = 1

" ─── User configuration ─────────────────────────────────────────────────────

if !exists('g:mdview_max_col_width')
  let g:mdview_max_col_width = 20
endif

" F18: override the overall render width (HRs, code fences). -1 = winwidth.
if !exists('g:mdview_max_width')
  let g:mdview_max_width = -1
endif

" F12: buffer placement — 'replace', 'split', 'vsplit', 'tab'
if !exists('g:mdview_open')
  let g:mdview_open = 'replace'
endif

" F10: user colour overrides — {'MdViewBold': 'gui=bold ctermfg=Red', ...}
if !exists('g:mdview_colors')
  let g:mdview_colors = {}
endif

" F20: strip simple HTML tags (<br>, <sub>, <sup>, etc.)
if !exists('g:mdview_strip_html')
  let g:mdview_strip_html = 1
endif

if !exists('g:mdview_auto_refresh')
  let g:mdview_auto_refresh = 1
endif

" ─── Commands ───────────────────────────────────────────────────────────────

command! MdView call mdview#open()
command! MdViewToggle call mdview#toggle()
command! -nargs=1 -complete=file MdViewExport call mdview#export(<q-args>)

" ─── Autocmds ───────────────────────────────────────────────────────────────

augroup mdview_auto
  autocmd!
  autocmd FileType markdown
        \ if !get(b:, 'mdview_auto_done', 0) && !get(b:, 'mdview_active', 0) |
        \   call mdview#open() |
        \ endif
  autocmd VimResized * if get(b:, 'mdview_active', 0) | call mdview#refresh() | endif
  autocmd BufWritePost,FileChangedShellPost *
        \ if g:mdview_auto_refresh |
        \   call mdview#on_source_changed(str2nr(expand('<abuf>'))) |
        \ endif
augroup END
