" F16: minimal regression harness for mdview.
" Run with:  vim -u NONE -N -e -s -S test/run.vim
" Writes test/results.txt with PASS/FAIL lines.

let s:plugin_root = expand('<sfile>:p:h:h')
execute 'set rtp+=' . s:plugin_root
filetype plugin on
execute 'source ' . s:plugin_root . '/plugin/mdview.vim'
execute 'source ' . s:plugin_root . '/autoload/mdview.vim'

let s:results = []
let s:fail_count = 0

function! s:render(lines)
  return mdview#__test_render(a:lines)
endfunction

" Expose s:render to tests by adding a thin wrapper to autoload at runtime.
function! mdview#__test_render(lines) abort
  " Replicate top-level dispatcher: load via :execute trick.
  " Use a tiny detour: write lines to a scratch buffer, call mdview#open(),
  " then read the rendered scratch back.
  let tmp = tempname() . '.md'
  call writefile(a:lines, tmp)
  execute 'edit ' . fnameescape(tmp)
  set filetype=markdown
  if !get(b:, 'mdview_active', 0)
    call mdview#open()
  endif
  let rendered = getline(1, '$')
  if get(b:, 'mdview_active', 0)
    call mdview#close()
  endif
  silent! execute 'bwipeout! ' . fnameescape(tmp)
  call delete(tmp)
  return rendered
endfunction

function! s:assert(name, cond)
  if a:cond
    call add(s:results, 'PASS  ' . a:name)
  else
    call add(s:results, 'FAIL  ' . a:name)
    let s:fail_count += 1
  endif
endfunction

function! s:contains_line(lines, needle)
  for l in a:lines
    if stridx(l, a:needle) >= 0
      return 1
    endif
  endfor
  return 0
endfunction

" ─── Tests ──────────────────────────────────────────────────────────────────

let r = s:render(['# Hello'])
call s:assert('H1 title', s:contains_line(r, 'Hello'))
call s:assert('H1 underline', s:contains_line(r, '====='))

let r = s:render(['## H2'])
call s:assert('H2 underline', s:contains_line(r, '--'))

let r = s:render(['Some `code_with_underscores` ok'])
call s:assert('code-protects-underscores', s:contains_line(r, 'code_with_underscores'))

let r = s:render(['Identifier some_variable_name stays.'])
call s:assert('italic-skips-word-underscores', s:contains_line(r, 'some_variable_name'))

let r = s:render(['***foo bar***'])
call s:assert('triple-asterisk-stripped', s:contains_line(r, 'foo bar') && !s:contains_line(r, '***'))

let r = s:render(['~~deleted~~'])
call s:assert('strikethrough-stripped', s:contains_line(r, 'deleted') && !s:contains_line(r, '~~'))

let r = s:render(['- [ ] todo', '- [x] done'])
call s:assert('task-list-unchecked', s:contains_line(r, '☐ todo'))
call s:assert('task-list-checked', s:contains_line(r, '☑ done'))

let r = s:render(['![alt](pic.png)'])
call s:assert('image-rendered', s:contains_line(r, 'Image: alt'))

let r = s:render(['Visit <https://example.com>'])
call s:assert('autolink-unwrapped', s:contains_line(r, 'https://example.com') && !s:contains_line(r, '<https'))

let r = s:render(['Setext H1', '========='])
call s:assert('setext-h1-title', s:contains_line(r, 'Setext H1'))

let r = s:render(['| A | B |', '|---|---|', '| 1 | 2 |'])
call s:assert('table-renders-border', s:contains_line(r, '+---'))
call s:assert('table-renders-header-sep', s:contains_line(r, '+==='))

let r = s:render(['| Col |', '|----:|', '| x   |'])
call s:assert('table-right-align', s:contains_line(r, '|   x |'))

let r = s:render(['Try [it][ref] now', '', '[ref]: https://ex.com'])
call s:assert('ref-link-resolved', s:contains_line(r, 'https://ex.com'))

let r = s:render(['Footnote here[^1].', '', '[^1]: the note'])
call s:assert('footnote-section-present', s:contains_line(r, 'Footnotes'))
call s:assert('footnote-def-rendered', s:contains_line(r, 'the note'))

let r = s:render(['---', 'title: foo', '---', '', '# Body'])
call s:assert('front-matter-rendered', s:contains_line(r, 'Front Matter'))
call s:assert('front-matter-body-shown', s:contains_line(r, 'title: foo'))

let r = s:render(['term', ': definition body'])
call s:assert('definition-term', s:contains_line(r, 'term'))
call s:assert('definition-body', s:contains_line(r, '▸ definition body'))

let r = s:render(['Some $x = 1$ math'])
call s:assert('math-inline-stripped', s:contains_line(r, 'x = 1') && !s:contains_line(r, '$x'))

let r = s:render(['Text <br> with <sup>2</sup> tags'])
call s:assert('html-br-stripped', !s:contains_line(r, '<br>'))
call s:assert('html-sup-stripped', !s:contains_line(r, '<sup>'))

call add(s:results, '')
call add(s:results, s:fail_count == 0
      \ ? 'ALL ' . (len(s:results) - 1) . ' TESTS PASSED'
      \ : s:fail_count . ' FAILURES')

call writefile(s:results, s:plugin_root . '/test/results.txt')
qa!
