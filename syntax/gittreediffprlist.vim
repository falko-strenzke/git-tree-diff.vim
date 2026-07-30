" Syntax for the pull request list of git-tree-diff (:FGitPrList)

if exists('b:current_syntax')
  finish
endif

syntax match GitTreeDiffPrListNumber /^#\d\+/
syntax match GitTreeDiffPrListMeta /\[[^]]*\]$/

highlight default link GitTreeDiffPrListNumber Identifier
highlight default link GitTreeDiffPrListMeta Comment

let b:current_syntax = 'gittreediffprlist'
