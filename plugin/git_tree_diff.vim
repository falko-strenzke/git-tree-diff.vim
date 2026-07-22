" git-tree-diff.vim - browse a git diff as a file tree with side-by-side diffs
" Maintainer: Falko Strenzke
" License: same as the repository (see LICENSE)

if exists('g:loaded_git_tree_diff')
  finish
endif
let g:loaded_git_tree_diff = 1

highlight default link GitTreeDiffSelected Visual

" All arguments are handed through to the underlying 'git diff' invocation.
command! -nargs=* FGitTreeDiff call git_tree_diff#run(<q-args>)

" Browse 'git log --graph --decorate'; the optional argument "all" adds --all.
command! -nargs=? -complete=customlist,git_tree_diff#log_complete
      \ FGitLog call git_tree_diff#log(<q-args>)
