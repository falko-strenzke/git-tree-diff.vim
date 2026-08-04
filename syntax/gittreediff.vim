" Syntax highlighting for the git-tree-diff tree buffer
if exists('b:current_syntax')
  finish
endif

syntax match GitTreeDiffDir /^\s*\S.*\/$/
syntax match GitTreeDiffHeader /\%1l.*/
syntax match GitTreeDiffRange /\%2l.*/

" files colored by their diff status (icons set in autoload/git_tree_diff.vim,
" colors in plugin/git_tree_diff.vim)
syntax match GitTreeDiffFileAdded /^\s*✚ .*/
syntax match GitTreeDiffFileChanged /^\s*● .*/
syntax match GitTreeDiffFileDeleted /^\s*✖ .*/

highlight default link GitTreeDiffDir Directory
highlight default link GitTreeDiffHeader Title
highlight default link GitTreeDiffRange Comment

let b:current_syntax = 'gittreediff'
