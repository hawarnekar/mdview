" autoload/mdview.vim — core rendering engine for mdview plugin

" ─── Public API ─────────────────────────────────────────────────────────────

function! mdview#open() abort
  if get(b:, 'mdview_active', 0)
    return
  endif

  " U10: warn when invoked on a non-markdown buffer
  if &filetype !=# 'markdown' && &filetype !=# ''
    echohl WarningMsg
    echom 'mdview: rendering buffer with filetype "' . &filetype . '" as markdown'
    echohl None
  endif

  let l:orig_buf = bufnr('%')
  let l:orig_pos = getpos('.')
  let l:orig_name_raw = bufname('%')
  let l:orig_name = empty(l:orig_name_raw) ? '[No Name]' : l:orig_name_raw

  " F14: pre-render hook
  silent doautocmd User MdViewPreRender

  try
    let lines = getline(1, '$')
    let [rendered, highlights, r2s, s2r, header_positions] = s:render(lines)
  catch
    echohl ErrorMsg
    echom 'mdview: render failed — ' . v:exception
    echohl None
    return
  endtry

  let b:mdview_auto_done = 1

  " F12: buffer placement
  call s:open_scratch_buffer()

  call clearmatches()

  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=mdview

  setlocal modifiable
  silent %delete _
  call setline(1, rendered)
  setlocal nomodifiable

  let b:mdview_active = 1
  let b:mdview_orig_buf = l:orig_buf
  let b:mdview_orig_pos = l:orig_pos
  let b:mdview_orig_name = l:orig_name
  let b:mdview_r2s = r2s
  let b:mdview_s2r = s2r
  let b:mdview_header_positions = header_positions
  let b:mdview_header_dict = {}
  for pos in header_positions
    let b:mdview_header_dict[pos[0]] = pos[1]
  endfor

  " U3: per-buffer statusline indicator
  setlocal statusline=[MdView]\ %{b:mdview_orig_name}

  " U9: section folding (open by default)
  setlocal foldmethod=expr
  setlocal foldexpr=mdview#foldlevel(v:lnum)
  setlocal foldlevel=99

  " Buffer-local mappings
  nnoremap <buffer> <silent> <nowait> q :<C-u>call mdview#close()<CR>
  nnoremap <buffer> <silent> <nowait> a :<C-u>call mdview#close()<CR>
  nnoremap <buffer> <silent> <nowait> i :<C-u>call mdview#close()<CR>
  nnoremap <buffer> <silent> gx :<C-u>call mdview#open_link()<CR>
  nnoremap <buffer> <silent> ]] :<C-u>call mdview#next_header()<CR>
  nnoremap <buffer> <silent> [[ :<C-u>call mdview#prev_header()<CR>

  " F10: apply user colour overrides
  call s:apply_user_colors()

  for item in highlights
    call matchaddpos(item[3], [[item[0], item[1], item[2]]])
  endfor

  " U4: position cursor on render line mapped from source cursor
  let target_line = 1
  let src_idx_0 = l:orig_pos[1] - 1
  if src_idx_0 >= 0 && src_idx_0 < len(s2r) && s2r[src_idx_0] >= 0
    let target_line = s2r[src_idx_0] + 1
  endif
  if target_line > line('$')
    let target_line = line('$')
  endif
  call cursor(target_line, 1)
  let b:mdview_initial_view_pos = getpos('.')

  " F14: post-render hook
  silent doautocmd User MdViewPostRender
endfunction

function! mdview#close() abort
  let view_pos = getpos('.')
  let orig_buf = get(b:, 'mdview_orig_buf', -1)
  let orig_pos = get(b:, 'mdview_orig_pos', [])
  let r2s = get(b:, 'mdview_r2s', [])
  let initial_view_pos = get(b:, 'mdview_initial_view_pos', [])
  call clearmatches()
  if orig_buf > 0 && bufexists(orig_buf)
    execute 'buffer' orig_buf
    if view_pos == initial_view_pos && !empty(orig_pos)
      call setpos('.', orig_pos)
    else
      let target_src_line = !empty(orig_pos) ? orig_pos[1] : 1
      let render_idx_0 = view_pos[1] - 1
      if render_idx_0 >= 0 && render_idx_0 < len(r2s)
        let target_src_line = r2s[render_idx_0] + 1
      endif
      call cursor(target_src_line, 1)
    endif
  else
    bdelete!
  endif
endfunction

function! mdview#toggle() abort
  if get(b:, 'mdview_active', 0)
    call mdview#close()
  else
    call mdview#open()
  endif
endfunction

function! mdview#refresh() abort
  if !get(b:, 'mdview_active', 0)
    return
  endif
  let l:view_pos = getpos('.')
  let l:orig_buf = get(b:, 'mdview_orig_buf', -1)
  if l:orig_buf < 0 || !bufexists(l:orig_buf)
    return
  endif

  silent doautocmd User MdViewPreRender
  try
    let lines = getbufline(l:orig_buf, 1, '$')
    let [rendered, highlights, r2s, s2r, header_positions] = s:render(lines)
  catch
    return
  endtry

  call clearmatches()
  setlocal modifiable
  silent %delete _
  call setline(1, rendered)
  setlocal nomodifiable

  let b:mdview_r2s = r2s
  let b:mdview_s2r = s2r
  let b:mdview_header_positions = header_positions
  let b:mdview_header_dict = {}
  for pos in header_positions
    let b:mdview_header_dict[pos[0]] = pos[1]
  endfor

  for item in highlights
    call matchaddpos(item[3], [[item[0], item[1], item[2]]])
  endfor

  if l:view_pos[1] > line('$')
    let l:view_pos[1] = line('$')
  endif
  call setpos('.', l:view_pos)
  silent doautocmd User MdViewPostRender
endfunction

" F13: export rendered output to a file
function! mdview#export(fname) abort
  let l:orig_buf = bufnr('%')
  if get(b:, 'mdview_active', 0)
    let l:orig_buf = get(b:, 'mdview_orig_buf', l:orig_buf)
  endif
  if !bufexists(l:orig_buf)
    echohl ErrorMsg | echom 'mdview: source buffer not found' | echohl None
    return
  endif
  try
    let lines = getbufline(l:orig_buf, 1, '$')
    let [rendered, _, _, _, _] = s:render(lines)
  catch
    echohl ErrorMsg | echom 'mdview: export failed — ' . v:exception | echohl None
    return
  endtry
  call writefile(rendered, a:fname)
  echo 'mdview: wrote ' . len(rendered) . ' lines to ' . a:fname
endfunction

" U8: header navigation
function! mdview#next_header() abort
  let positions = get(b:, 'mdview_header_positions', [])
  let cur = line('.')
  for pos in positions
    if pos[0] > cur
      call cursor(pos[0], 1)
      return
    endif
  endfor
  echo 'mdview: no more headers'
endfunction

function! mdview#prev_header() abort
  let positions = get(b:, 'mdview_header_positions', [])
  let cur = line('.')
  let prev = -1
  for pos in positions
    if pos[0] < cur
      let prev = pos[0]
    else
      break
    endif
  endfor
  if prev > 0
    call cursor(prev, 1)
  else
    echo 'mdview: no previous header'
  endif
endfunction

" U9: foldexpr
function! mdview#foldlevel(lnum) abort
  let d = get(b:, 'mdview_header_dict', {})
  if has_key(d, a:lnum)
    return '>' . d[a:lnum]
  endif
  return '='
endfunction

" U6: open URL under cursor
function! mdview#open_link() abort
  let line = getline('.')
  let col = col('.')
  let pat = '(\([^)]*\(://\|@\|www\.\)[^)]*\))'
  let pos = 0
  let candidates = []
  while 1
    let m = matchstrpos(line, pat, pos)
    if m[1] < 0
      break
    endif
    let url = substitute(m[0], '^(\|)$', '', 'g')
    call add(candidates, [m[1], m[2], url])
    let pos = m[2]
  endwhile
  if empty(candidates)
    echo 'mdview: no link on this line'
    return
  endif
  let best = candidates[0]
  for c in candidates
    if c[0] <= col - 1 && col - 1 < c[1]
      let best = c
      break
    endif
  endfor
  call s:open_url(best[2])
endfunction

function! s:open_url(url) abort
  if has('mac')
    call system('open ' . shellescape(a:url))
  elseif has('unix')
    call system('xdg-open ' . shellescape(a:url) . ' >/dev/null 2>&1 &')
  elseif has('win32') || has('win64')
    call system('cmd /c start "" ' . shellescape(a:url))
  endif
  echo 'mdview: opened ' . a:url
endfunction

" U7: refresh visible scratch view when source changes
function! mdview#on_source_changed(changed_buf) abort
  if a:changed_buf <= 0
    return
  endif
  let current_winid = win_getid()
  try
    for tabnr in range(1, tabpagenr('$'))
      let buflist = tabpagebuflist(tabnr)
      let winnr = 1
      for bufnr in buflist
        if getbufvar(bufnr, 'mdview_active', 0)
              \ && getbufvar(bufnr, 'mdview_orig_buf', -1) == a:changed_buf
          let winid = win_getid(winnr, tabnr)
          if winid > 0
            call win_gotoid(winid)
            call mdview#refresh()
          endif
        endif
        let winnr += 1
      endfor
    endfor
  finally
    call win_gotoid(current_winid)
  endtry
endfunction

" ─── Internal helpers ───────────────────────────────────────────────────────

function! s:get_max_width() abort
  let w = get(g:, 'mdview_max_width', -1)
  if w > 0
    return w
  endif
  return max([winwidth(0) - 2, 20])
endfunction

" F12: open scratch buffer in placement defined by g:mdview_open
function! s:open_scratch_buffer() abort
  let mode = get(g:, 'mdview_open', 'replace')
  let l:saved_hidden = &hidden
  set hidden
  try
    if mode ==# 'split'
      noautocmd new
    elseif mode ==# 'vsplit'
      noautocmd vnew
    elseif mode ==# 'tab'
      noautocmd tabnew
    else
      noautocmd enew
    endif
  finally
    let &hidden = l:saved_hidden
  endtry
endfunction

" F10: apply g:mdview_colors over highlight defaults
function! s:apply_user_colors() abort
  let colors = get(g:, 'mdview_colors', {})
  if type(colors) != type({})
    return
  endif
  for [group, spec] in items(colors)
    execute 'hi ' . group . ' ' . spec
  endfor
endfunction

" ─── Renderer ───────────────────────────────────────────────────────────────

function! s:render(lines) abort
  let lines = a:lines

  " F6: extract front matter
  let [front_lines, lines] = s:extract_front_matter(lines)
  " F5: collect reference link definitions
  let [ref_defs, lines] = s:collect_reference_defs(lines)
  " F7: collect footnote definitions
  let [foot_defs, foot_order, lines] = s:collect_footnote_defs(lines)

  let output = []
  let highlights = []
  let n = len(lines)
  let r2s = []
  let s2r = repeat([-1], n)
  let header_positions = []

  " F6: render front matter at top
  if !empty(front_lines)
    let [fm_rendered, fm_hl] = s:render_front_matter(front_lines, 0)
    call extend(output, fm_rendered)
    call extend(highlights, fm_hl)
  endif

  let render_offset_for_fm = len(output)
  let i = 0

  while i < n
    let source_start = i
    let render_start = len(output)
    let line = lines[i]

    if line =~# '^\s*```'
      let [block, i] = s:collect_code_block(lines, i)
      let [rendered, hl] = s:render_code_block(block, len(output))
      call extend(output, rendered)
      call extend(highlights, hl)
    elseif line =~# '^\s*|'
      let [rows, i] = s:collect_table(lines, i)
      let [rendered, hl] = s:render_table(rows, len(output))
      call extend(output, rendered)
      call extend(highlights, hl)
    elseif i + 1 < n && lines[i + 1] =~# '^=\{2,}\s*$'
          \ && line !~# '^\s*$' && line !~# '^#'
          \ && line !~# '^\s*```' && line !~# '^\s*|' && line !~# '^>'
      let header_lnum = len(output) + 1
      let [rendered, hl] = s:render_setext_header(line, 1, len(output), ref_defs)
      call extend(output, rendered)
      call extend(highlights, hl)
      call add(header_positions, [header_lnum, 1])
      let i += 2
    elseif i + 1 < n && lines[i + 1] =~# '^-\{2,}\s*$'
          \ && line !~# '^\s*$' && line !~# '^#' && line !~# '^>'
          \ && line !~# '^\s*[-*+]\s' && line !~# '^\s*\d\+\.\s'
          \ && line !~# '^\s*|' && line !~# '^\s*```'
      let header_lnum = len(output) + 1
      let [rendered, hl] = s:render_setext_header(line, 2, len(output), ref_defs)
      call extend(output, rendered)
      call extend(highlights, hl)
      call add(header_positions, [header_lnum, 2])
      let i += 2
    " F8: definition list
    elseif i + 1 < n && lines[i + 1] =~# '^:\s\+\S'
          \ && line !~# '^\s*$' && line !~# '^#' && line !~# '^>'
          \ && line !~# '^\s*[-*+]\s' && line !~# '^\s*\d\+\.\s'
          \ && line !~# '^\s*|' && line !~# '^\s*```'
      let [rendered, hl, consumed] = s:render_definition(lines, i, len(output), ref_defs)
      call extend(output, rendered)
      call extend(highlights, hl)
      let i += consumed
    elseif line =~# '^#'
      let level = len(matchstr(line, '^#\+'))
      if level > 6
        let level = 6
      endif
      let header_lnum = len(output) + 1
      let [rendered, hl] = s:render_header(line, len(output), ref_defs)
      call extend(output, rendered)
      call extend(highlights, hl)
      call add(header_positions, [header_lnum, level])
      let i += 1
    elseif line =~# '^\s*\(---\+\|===\+\|\*\*\*\+\|___\+\)\s*$'
      let w = s:get_max_width()
      call add(output, repeat('─', w))
      let i += 1
    elseif line =~# '^>'
      let [rendered, hl] = s:render_blockquote(line, len(output), ref_defs)
      call extend(output, rendered)
      call extend(highlights, hl)
      let i += 1
    elseif line =~# '^\s*[-*+]\s' || line =~# '^\s*\d\+\.\s'
      let [rendered, hl] = s:render_list_item(line, len(output), ref_defs)
      call extend(output, rendered)
      call extend(highlights, hl)
      let i += 1
    else
      let [processed, hl] = s:process_inline(line, len(output) + 1, ref_defs)
      call add(output, processed)
      call extend(highlights, hl)
      let i += 1
    endif

    let source_end = i
    let render_end = len(output)

    let si = source_start
    while si < source_end && si < n
      let s2r[si] = render_start
      let si += 1
    endwhile
    let ri = render_start
    while ri < render_end
      call add(r2s, source_start)
      let ri += 1
    endwhile
  endwhile

  " F7: append footnotes at end
  if !empty(foot_order)
    let [fn_rendered, fn_hl] = s:render_footnotes(foot_defs, foot_order, len(output))
    call extend(output, fn_rendered)
    call extend(highlights, fn_hl)
  endif

  return [output, highlights, r2s, s2r, header_positions]
endfunction

" ─── F6: Front matter ───────────────────────────────────────────────────────

function! s:extract_front_matter(lines) abort
  if empty(a:lines)
    return [[], a:lines]
  endif
  let first = a:lines[0]
  if first ==# '---' || first ==# '+++'
    let delim = first
    let i = 1
    while i < len(a:lines)
      if a:lines[i] ==# delim
        return [a:lines[1 : i - 1], a:lines[i + 1 :]]
      endif
      let i += 1
    endwhile
  endif
  return [[], a:lines]
endfunction

function! s:render_front_matter(fm_lines, base_lnum) abort
  let output = []
  let highlights = []
  let w = s:get_max_width()
  let top = '╭─ Front Matter ' . repeat('─', max([w - 17, 0]))
  let bot = '╰' . repeat('─', w - 1)
  call add(output, top)
  call add(highlights, [a:base_lnum + len(output), 1, strlen(top), 'MdViewFrontMatter'])
  for line in a:fm_lines
    let lline = '│ ' . line
    call add(output, lline)
    call add(highlights, [a:base_lnum + len(output), 1, strlen(lline), 'MdViewFrontMatter'])
  endfor
  call add(output, bot)
  call add(highlights, [a:base_lnum + len(output), 1, strlen(bot), 'MdViewFrontMatter'])
  call add(output, '')
  return [output, highlights]
endfunction

" ─── F5: Reference link definitions ─────────────────────────────────────────

function! s:collect_reference_defs(lines) abort
  let refs = {}
  let remaining = []
  for line in a:lines
    let m = matchlist(line, '^\s*\[\([^]]\+\)\]:\s*\(\S\+\)\s*$')
    if !empty(m)
      let refs[tolower(m[1])] = m[2]
    else
      call add(remaining, line)
    endif
  endfor
  return [refs, remaining]
endfunction

" ─── F7: Footnote definitions ───────────────────────────────────────────────

function! s:collect_footnote_defs(lines) abort
  let defs = {}
  let order = []
  let remaining = []
  for line in a:lines
    let m = matchlist(line, '^\s*\[\^\([^]]\+\)\]:\s*\(.*\)$')
    if !empty(m)
      let defs[m[1]] = m[2]
      if index(order, m[1]) < 0
        call add(order, m[1])
      endif
    else
      call add(remaining, line)
    endif
  endfor
  return [defs, order, remaining]
endfunction

function! s:render_footnotes(defs, order, base_lnum) abort
  let output = []
  let highlights = []
  let w = s:get_max_width()
  call add(output, '')
  call add(output, repeat('─', w))
  call add(output, 'Footnotes')
  call add(highlights, [a:base_lnum + len(output), 1, strlen('Footnotes'), 'MdViewH3'])
  call add(output, '')
  let n = 1
  for key in a:order
    let line = '[' . n . '] ' . a:defs[key]
    call add(output, line)
    call add(highlights, [a:base_lnum + len(output), 1, strlen('[' . n . ']'), 'MdViewFootnote'])
    let n += 1
  endfor
  return [output, highlights]
endfunction

" ─── F8: Definition list ────────────────────────────────────────────────────

function! s:render_definition(lines, start, base_lnum, ref_defs) abort
  let output = []
  let highlights = []
  let i = a:start
  let term = a:lines[i]
  let [proc_term, term_hl] = s:process_inline(term, a:base_lnum + 1, a:ref_defs)
  call add(output, proc_term)
  call extend(highlights, term_hl)
  call add(highlights, [a:base_lnum + len(output), 1, strlen(proc_term), 'MdViewDefTerm'])
  let i += 1
  while i < len(a:lines) && a:lines[i] =~# '^:\s\+'
    let dline = substitute(a:lines[i], '^:\s\+', '', '')
    let [proc, hl] = s:process_inline(dline, a:base_lnum + len(output) + 1, a:ref_defs)
    let prefix = '  ▸ '
    let col_offset = strlen(prefix)
    let shifted = map(hl, '[v:val[0], v:val[1] + col_offset, v:val[2], v:val[3]]')
    call add(output, prefix . proc)
    call extend(highlights, shifted)
    let i += 1
  endwhile
  return [output, highlights, i - a:start]
endfunction

" ─── Headers ────────────────────────────────────────────────────────────────

function! s:render_header(line, base_lnum, ref_defs) abort
  let level = len(matchstr(a:line, '^#\+'))
  let title_raw = substitute(a:line, '^#\+\s*', '', '')
  let [title, hl] = s:process_inline(title_raw, a:base_lnum + 1, a:ref_defs)
  let output = []
  let highlights = []
  call extend(highlights, hl)

  if level == 1
    let under = repeat('=', strwidth(title))
    call add(output, title)
    call add(output, under)
    call add(highlights, [a:base_lnum + 1, 1, strlen(title), 'MdViewH1'])
  elseif level == 2
    let under = repeat('-', strwidth(title))
    call add(output, title)
    call add(output, under)
    call add(highlights, [a:base_lnum + 1, 1, strlen(title), 'MdViewH2'])
  else
    let indent = repeat('  ', level - 2)
    call add(output, indent . title)
    call add(highlights, [a:base_lnum + 1, strlen(indent) + 1, strlen(title), 'MdViewH3'])
  endif

  return [output, highlights]
endfunction

function! s:render_setext_header(line, level, base_lnum, ref_defs) abort
  let [title, hl] = s:process_inline(a:line, a:base_lnum + 1, a:ref_defs)
  let output = []
  let highlights = []
  call extend(highlights, hl)
  if a:level == 1
    let under = repeat('=', strwidth(title))
    call add(output, title)
    call add(output, under)
    call add(highlights, [a:base_lnum + 1, 1, strlen(title), 'MdViewH1'])
  else
    let under = repeat('-', strwidth(title))
    call add(output, title)
    call add(output, under)
    call add(highlights, [a:base_lnum + 1, 1, strlen(title), 'MdViewH2'])
  endif
  return [output, highlights]
endfunction

" ─── Tables (F9 alignment) ──────────────────────────────────────────────────

function! s:collect_table(lines, start) abort
  let result = []
  let i = a:start
  while i < len(a:lines) && a:lines[i] =~# '^\s*|'
    call add(result, a:lines[i])
    let i += 1
  endwhile
  return [result, i]
endfunction

function! s:parse_table_row(line) abort
  let line = substitute(a:line, '\\|', "\x02", 'g')
  let stripped = substitute(line, '^\s*|\(.*\)|\s*$', '\1', '')
  if stripped ==# line
    let stripped = substitute(line, '^\s*\|\s*$', '', 'g')
  endif
  let cells = split(stripped, '|', 1)
  call map(cells, 'substitute(v:val, ''^\s*\|\s*$'', '''', ''g'')')
  call map(cells, 'substitute(v:val, "\x02", "|", "g")')
  return cells
endfunction

function! s:is_separator_row(cells) abort
  for cell in a:cells
    if cell !~# '^:*-\+:*$'
      return 0
    endif
  endfor
  return 1
endfunction

" F9: parse alignment from separator row
function! s:parse_alignments(cells) abort
  let aligns = []
  for cell in a:cells
    let left = cell =~# '^:'
    let right = cell =~# ':$'
    if left && right
      call add(aligns, 'c')
    elseif right
      call add(aligns, 'r')
    else
      call add(aligns, 'l')
    endif
  endfor
  return aligns
endfunction

function! s:pad_align(text, width, align) abort
  let pad = a:width - strwidth(a:text)
  if pad <= 0
    return a:text
  endif
  if a:align ==# 'r'
    return repeat(' ', pad) . a:text
  elseif a:align ==# 'c'
    let l = pad / 2
    let r = pad - l
    return repeat(' ', l) . a:text . repeat(' ', r)
  endif
  return a:text . repeat(' ', pad)
endfunction

function! s:render_table(rows, base_lnum) abort
  if empty(a:rows)
    return [[], []]
  endif

  let parsed = map(copy(a:rows), 's:parse_table_row(v:val)')

  let ncols = 0
  for row in parsed
    if len(row) > ncols
      let ncols = len(row)
    endif
  endfor

  let aligns = repeat(['l'], ncols)
  for row in parsed
    if s:is_separator_row(row)
      let parsed_aligns = s:parse_alignments(row)
      let i = 0
      while i < len(parsed_aligns) && i < ncols
        let aligns[i] = parsed_aligns[i]
        let i += 1
      endwhile
      break
    endif
  endfor

  let widths = repeat([0], ncols)
  for row in parsed
    if s:is_separator_row(row)
      continue
    endif
    let ci = 0
    while ci < len(row)
      let w = strwidth(row[ci])
      if w > widths[ci]
        let widths[ci] = w
      endif
      let ci += 1
    endwhile
  endfor
  let max_w = g:mdview_max_col_width
  let widths = map(widths, 'v:val > max_w ? max_w : (v:val < 1 ? 1 : v:val)')

  let border = '+' . join(map(copy(widths), 'repeat(''-'', v:val + 2)'), '+') . '+'
  let header_border = '+' . join(map(copy(widths), 'repeat(''='', v:val + 2)'), '+') . '+'

  let output = []
  let highlights = []
  let is_first_row = 1

  call add(output, border)
  call add(highlights, [a:base_lnum + len(output), 1, strlen(border), 'MdViewTableBorder'])

  for row in parsed
    if s:is_separator_row(row)
      continue
    endif

    let cells_wrapped = []
    let ci = 0
    while ci < ncols
      let cell = ci < len(row) ? row[ci] : ''
      call add(cells_wrapped, s:wrap_text(cell, widths[ci]))
      let ci += 1
    endwhile

    let nlines = 1
    for wc in cells_wrapped
      if len(wc) > nlines
        let nlines = len(wc)
      endif
    endfor

    let li = 0
    while li < nlines
      let parts = []
      let ci = 0
      while ci < ncols
        let seg = li < len(cells_wrapped[ci]) ? cells_wrapped[ci][li] : ''
        call add(parts, s:pad_align(seg, widths[ci], aligns[ci]))
        let ci += 1
      endwhile
      let row_line = '| ' . join(parts, ' | ') . ' |'
      call add(output, row_line)
      let li += 1
    endwhile

    if is_first_row
      call add(output, header_border)
      call add(highlights, [a:base_lnum + len(output), 1, strlen(header_border), 'MdViewTableBorder'])
      let is_first_row = 0
    endif
  endfor

  call add(output, border)
  call add(highlights, [a:base_lnum + len(output), 1, strlen(border), 'MdViewTableBorder'])

  return [output, highlights]
endfunction

" ─── Code blocks ────────────────────────────────────────────────────────────

function! s:collect_code_block(lines, start) abort
  let result = [a:lines[a:start]]
  let i = a:start + 1
  while i < len(a:lines)
    call add(result, a:lines[i])
    if a:lines[i] =~# '^\s*```\s*$'
      let i += 1
      break
    endif
    let i += 1
  endwhile
  return [result, i]
endfunction

function! s:render_code_block(block, base_lnum) abort
  let output = []
  let highlights = []

  let fence = a:block[0]
  let lang = substitute(fence, '^\s*```\s*', '', '')
  let lang = substitute(lang, '\s*$', '', '')

  let w = s:get_max_width()
  let label = empty(lang) ? '' : (' ' . lang . ' ')
  let top = ',--' . label . repeat('─', max([w - 3 - strwidth(label), 0]))
  let bot = '`' . repeat('─', w - 1)

  call add(output, top)

  let body_end = len(a:block) - 1
  if body_end >= 1 && a:block[body_end] =~# '^\s*```\s*$'
    let body_end -= 1
  endif
  let i = 1
  while i <= body_end
    call add(output, '| ' . a:block[i])
    let i += 1
  endwhile

  call add(output, bot)

  return [output, highlights]
endfunction

" ─── Blockquotes ────────────────────────────────────────────────────────────

function! s:render_blockquote(line, base_lnum, ref_defs) abort
  let content = substitute(a:line, '^>\+\s*', '', '')
  let [processed, hl] = s:process_inline(content, a:base_lnum + 1, a:ref_defs)
  let prefix = '│ '
  let col_offset = strlen(prefix)
  let shifted = map(hl, '[v:val[0], v:val[1] + col_offset, v:val[2], v:val[3]]')
  return [[prefix . processed], shifted]
endfunction

" ─── Lists (F1 task lists) ──────────────────────────────────────────────────

function! s:render_list_item(line, base_lnum, ref_defs) abort
  let indent_str = matchstr(a:line, '^\s*')
  let level = strwidth(indent_str) / 2
  let rest = substitute(a:line, '^\s*', '', '')

  if rest =~# '^[-*+]\s'
    let content = substitute(rest, '^[-*+]\s\+', '', '')
    " F1: task list checkboxes
    if content =~# '^\[ \]\s'
      let marker = '☐'
      let content = substitute(content, '^\[ \]\s\+', '', '')
    elseif content =~# '^\[[xX]\]\s'
      let marker = '☑'
      let content = substitute(content, '^\[[xX]\]\s\+', '', '')
    else
      let marker = level == 0 ? '•' : '◦'
    endif
    let prefix = repeat('  ', level) . marker . ' '
  else
    let num = matchstr(rest, '^\d\+')
    let content = substitute(rest, '^\d\+\.\s\+', '', '')
    let prefix = repeat('  ', level) . num . '. '
  endif

  let [processed, hl] = s:process_inline(content, a:base_lnum + 1, a:ref_defs)
  let col_offset = strlen(prefix)
  let shifted = map(hl, '[v:val[0], v:val[1] + col_offset, v:val[2], v:val[3]]')
  return [[prefix . processed], shifted]
endfunction

" ─── Inline processing ──────────────────────────────────────────────────────

function! s:process_inline(text, lnum, ref_defs) abort
  " Tokenize alternating regular / code segments (code spans are opaque)
  let segments = []
  let pos = 0
  let text = a:text
  let tlen = strlen(text)
  while pos < tlen
    let m = matchstrpos(text, '`\([^`]\+\)`', pos)
    if m[1] < 0
      call add(segments, ['r', strpart(text, pos)])
      break
    endif
    if m[1] > pos
      call add(segments, ['r', strpart(text, pos, m[1] - pos)])
    endif
    let content = substitute(m[0], '`\([^`]\+\)`', '\1', '')
    call add(segments, ['c', content])
    let pos = m[2]
  endwhile

  let out = ''
  let highlights = []
  for seg in segments
    let stype = seg[0]
    let scontent = seg[1]
    if stype ==# 'c'
      let col_start = strlen(out) + 1
      call add(highlights, [a:lnum, col_start, strlen(scontent), 'MdViewCode'])
      let out .= scontent
    else
      let [processed, hl] = s:process_non_code(scontent, a:lnum, a:ref_defs)
      let offset = strlen(out)
      for h in hl
        call add(highlights, [h[0], h[1] + offset, h[2], h[3]])
      endfor
      let out .= processed
    endif
  endfor
  return [out, highlights]
endfunction

function! s:process_non_code(text, lnum, ref_defs) abort
  let text = a:text

  " F20: strip simple HTML tags
  if get(g:, 'mdview_strip_html', 1)
    let text = substitute(text, '<br\s*/\?>', ' ', 'g')
    let text = substitute(text, '<\/\?\(sub\|sup\|em\|strong\|i\|b\|u\|span\|div\)\s*[^>]*>', '', 'g')
  endif

  " F3: images ![alt](url) - convert to [Image: alt] (url)
  let text = substitute(text, '!\[\([^]]\{-}\)\](\([^)]\{-}\))', '[Image: \1] (\2)', 'g')

  " F4: autolinks <url> -> url
  let text = substitute(text, '<\(\(https\?\|ftp\|mailto\):[^>]\+\)>', '\1', 'g')

  " F5: reference links [text][ref] -> text (url)
  if !empty(a:ref_defs)
    let text = s:expand_ref_links(text, a:ref_defs)
  endif

  " F7: footnote references [^N] -> [N] - replace in-place
  let text = s:expand_footnote_refs(text)

  " F19: math — keep $..$ as-is but highlight will be added later
  " (handled in highlight pass below)

  let highlights = []
  let [text, link_hl] = s:process_links(text, a:lnum)
  call extend(highlights, link_hl)

  " Math: $..$ and $$..$$ — leave content but highlight the inner text and strip $s
  let text = s:strip_inline(text, '\$\$\([^$]\+\)\$\$', a:lnum, 'MdViewMath', highlights)
  let text = s:strip_inline(text, '\$\([^$]\+\)\$', a:lnum, 'MdViewMath', highlights)

  let text = s:strip_inline_dual(text, '\*\*\*\([^*]\+\)\*\*\*', a:lnum, ['MdViewBold', 'MdViewItalic'], highlights)
  let text = s:strip_inline_dual(text, '___\([^_]\+\)___', a:lnum, ['MdViewBold', 'MdViewItalic'], highlights)
  let text = s:strip_inline(text, '\*\*\(.\{-}\)\*\*', a:lnum, 'MdViewBold', highlights)
  let text = s:strip_inline(text, '__\(.\{-}\)__', a:lnum, 'MdViewBold', highlights)
  " F2: strikethrough
  let text = s:strip_inline(text, '\~\~\([^~]\+\)\~\~', a:lnum, 'MdViewStrike', highlights)
  let text = s:strip_inline(text, '\*\([^*]\+\)\*', a:lnum, 'MdViewItalic', highlights)
  let text = s:strip_inline(text, '\%(^\|\W\)\zs_\([^_]\+\)_\ze\%($\|\W\)', a:lnum, 'MdViewItalic', highlights)
  return [text, highlights]
endfunction

" F5: expand [text][ref] -> text (url)
function! s:expand_ref_links(text, ref_defs) abort
  let result = ''
  let pos = 0
  let text = a:text
  while 1
    let m = matchstrpos(text, '\[\([^]]\+\)\]\[\([^]]*\)\]', pos)
    if m[1] < 0
      let result .= strpart(text, pos)
      break
    endif
    let result .= strpart(text, pos, m[1] - pos)
    let link_text = substitute(m[0], '\[\([^]]\+\)\]\[\([^]]*\)\]', '\1', '')
    let ref_key = substitute(m[0], '\[\([^]]\+\)\]\[\([^]]*\)\]', '\2', '')
    if empty(ref_key)
      let ref_key = link_text
    endif
    let url = get(a:ref_defs, tolower(ref_key), '')
    if !empty(url)
      let result .= '[' . link_text . '](' . url . ')'
    else
      let result .= m[0]
    endif
    let pos = m[2]
  endwhile
  return result
endfunction

" F7: replace [^N] with [n] numerically
function! s:expand_footnote_refs(text) abort
  return substitute(a:text, '\[\^\([^]]\+\)\]', '[\1]', 'g')
endfunction

function! s:process_links(text, lnum) abort
  let result = ''
  let pos = 0
  let highlights = []
  let pat = '\[\([^]]\{-}\)\](\([^)]\{-}\))'
  while 1
    let m = matchstrpos(a:text, pat, pos)
    if m[1] < 0
      let result .= strpart(a:text, pos)
      break
    endif
    let result .= strpart(a:text, pos, m[1] - pos)
    let link_text = substitute(m[0], pat, '\1', '')
    let link_url  = substitute(m[0], pat, '\2', '')
    let replacement = link_text . ' (' . link_url . ')'
    let col_start = strlen(result) + 1
    call add(highlights, [a:lnum, col_start, strlen(link_text), 'MdViewLink'])
    let result .= replacement
    let pos = m[2]
  endwhile
  return [result, highlights]
endfunction

function! s:strip_inline(text, pat, lnum, group, highlights) abort
  let result = ''
  let pos = 0
  let prior_count = len(a:highlights)
  let strips = []

  while 1
    let m = matchstrpos(a:text, a:pat, pos)
    if m[1] < 0
      let result .= strpart(a:text, pos)
      break
    endif
    let result .= strpart(a:text, pos, m[1] - pos)
    let content = substitute(m[0], a:pat, '\1', '')
    let removed = strlen(m[0]) - strlen(content)
    let marker_len = removed / 2
    let col_start = strlen(result) + 1
    call add(a:highlights, [a:lnum, col_start, strlen(content), a:group])
    if marker_len > 0
      call add(strips, [m[1], m[1] + marker_len, marker_len])
      call add(strips, [m[2] - marker_len, m[2], marker_len])
    endif
    let result .= content
    let pos = m[2]
  endwhile

  call s:apply_strips(a:highlights, prior_count, strips)
  return result
endfunction

function! s:strip_inline_dual(text, pat, lnum, groups, highlights) abort
  let result = ''
  let pos = 0
  let prior_count = len(a:highlights)
  let strips = []

  while 1
    let m = matchstrpos(a:text, a:pat, pos)
    if m[1] < 0
      let result .= strpart(a:text, pos)
      break
    endif
    let result .= strpart(a:text, pos, m[1] - pos)
    let content = substitute(m[0], a:pat, '\1', '')
    let removed = strlen(m[0]) - strlen(content)
    let marker_len = removed / 2
    let col_start = strlen(result) + 1
    for g in a:groups
      call add(a:highlights, [a:lnum, col_start, strlen(content), g])
    endfor
    if marker_len > 0
      call add(strips, [m[1], m[1] + marker_len, marker_len])
      call add(strips, [m[2] - marker_len, m[2], marker_len])
    endif
    let result .= content
    let pos = m[2]
  endwhile

  call s:apply_strips(a:highlights, prior_count, strips)
  return result
endfunction

function! s:apply_strips(highlights, prior_count, strips) abort
  if empty(a:strips) || a:prior_count == 0
    return
  endif
  let idx = 0
  while idx < a:prior_count
    let hl_start_0 = a:highlights[idx][1] - 1
    let hl_end_0 = hl_start_0 + a:highlights[idx][2]
    let new_start = s:input_to_result(hl_start_0, a:strips)
    let new_end = s:input_to_result(hl_end_0, a:strips)
    if new_end < new_start
      let new_end = new_start
    endif
    let a:highlights[idx][1] = new_start + 1
    let a:highlights[idx][2] = new_end - new_start
    let idx += 1
  endwhile
endfunction

function! s:input_to_result(input_pos, strips) abort
  let shift = 0
  for strip in a:strips
    let s_start = strip[0]
    let s_end = strip[1]
    let s_removed = strip[2]
    if a:input_pos <= s_start
      break
    elseif a:input_pos >= s_end
      let shift += s_removed
    else
      let shift += a:input_pos - s_start
      break
    endif
  endfor
  return a:input_pos - shift
endfunction

" ─── Text utilities ─────────────────────────────────────────────────────────

function! s:wrap_text(text, width) abort
  if strwidth(a:text) <= a:width
    return [a:text]
  endif
  let words = split(a:text, ' ', 1)
  let lines = []
  let current = ''
  for word in words
    if empty(current)
      if strwidth(word) > a:width
        let lines += s:break_word(word, a:width)
        let current = ''
      else
        let current = word
      endif
    else
      let candidate = current . ' ' . word
      if strwidth(candidate) <= a:width
        let current = candidate
      else
        call add(lines, current)
        if strwidth(word) > a:width
          let lines += s:break_word(word, a:width)
          let current = ''
        else
          let current = word
        endif
      endif
    endif
  endfor
  if !empty(current)
    call add(lines, current)
  endif
  return lines
endfunction

function! s:break_word(word, width) abort
  let result = []
  let w = a:word
  while strwidth(w) > a:width
    call add(result, strcharpart(w, 0, a:width))
    let w = strcharpart(w, a:width)
  endwhile
  if !empty(w)
    call add(result, w)
  endif
  return result
endfunction

function! s:pad_right(text, width) abort
  let pad = a:width - strwidth(a:text)
  if pad > 0
    return a:text . repeat(' ', pad)
  endif
  return a:text
endfunction
