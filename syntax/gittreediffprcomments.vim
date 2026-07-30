" Syntax for the pull request comment list of git-tree-diff
" (:FGitPrCommentsOpen)

if exists('b:current_syntax')
  finish
endif

syntax match GitTreeDiffPrCHeader /^↳\?\s*@.*$/
      \ contains=GitTreeDiffPrCAuthor,GitTreeDiffPrCWhere
syntax match GitTreeDiffPrCAuthor /@\S\+/ contained
syntax match GitTreeDiffPrCWhere /·[^·]*$/ contained
syntax match GitTreeDiffPrCPreview /^    .*$/

highlight default link GitTreeDiffPrCHeader Statement
highlight default link GitTreeDiffPrCAuthor Identifier
highlight default link GitTreeDiffPrCWhere Comment
highlight default link GitTreeDiffPrCPreview Normal

let b:current_syntax = 'gittreediffprcomments'
