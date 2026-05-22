if exists('b:current_syntax')
  finish
endif

syn match MdViewH1Under   /^=\{2,}\s*$/
syn match MdViewH2Under   /^-\{2,}\s*$/

syn match MdViewTableBorder /^+[-=+]\+$/

syn region MdViewCodeBlock
      \ matchgroup=MdViewCodeFence
      \ start=/^,--/
      \ end=/^`─\+$/
      \ keepend
      \ contains=NONE

syn match MdViewBlockquote /^│.*/

syn region MdViewFrontMatter
      \ start=/^╭─ Front Matter/
      \ end=/^╰─\+$/
      \ keepend
      \ contains=NONE

syn match MdViewHR /^─\{3,}$/

" F11: link to standard groups so user colorschemes drive appearance
hi def link MdViewH1Under     Comment
hi def link MdViewH2Under     Comment
hi def link MdViewTableBorder Special
hi def link MdViewCodeFence   Comment
hi def link MdViewCodeBlock   Comment
hi def link MdViewBlockquote  Comment
hi def link MdViewFrontMatter Comment
hi def link MdViewHR          Comment
hi def link MdViewCode        String
hi def link MdViewLink        Underlined
hi def link MdViewMath        Identifier
hi def link MdViewFootnote    Type
hi def link MdViewDefTerm     Statement

hi def MdViewH1     gui=bold      cterm=bold
hi def MdViewH2     gui=bold      cterm=bold
hi def MdViewH3     gui=italic    cterm=italic
hi def MdViewBold   gui=bold      cterm=bold
hi def MdViewItalic gui=italic    cterm=italic
hi def MdViewStrike gui=strikethrough cterm=strikethrough

let b:current_syntax = 'mdview'
