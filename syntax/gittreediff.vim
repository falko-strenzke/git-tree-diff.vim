" Syntax highlighting for the git-tree-diff tree buffer
if exists('b:current_syntax')
  finish
endif

syntax match GitTreeDiffDir /^\s*\S.*\/$/
syntax match GitTreeDiffHeader /\%1l.*/
syntax match GitTreeDiffRange /\%2l.*/

highlight default link GitTreeDiffDir Directory
highlight default link GitTreeDiffHeader Title
highlight default link GitTreeDiffRange Comment

let b:current_syntax = 'gittreediff'
