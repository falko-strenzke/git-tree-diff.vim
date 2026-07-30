" git-tree-diff.vim - browse a git diff as a file tree with side-by-side diffs
" Maintainer: Falko Strenzke
" License: same as the repository (see LICENSE)

if exists('g:loaded_git_tree_diff')
  finish
endif
let g:loaded_git_tree_diff = 1

highlight default link GitTreeDiffSelected Visual
highlight default link GitTreeDiffPrAddSign DiffAdd
highlight default link GitTreeDiffPrDelSign DiffDelete
highlight default link GitTreeDiffPrCommentSign Search
highlight default GitTreeDiffPrLocalSign ctermfg=Red guifg=Red

if exists('*sign_define')
  call sign_define('GitTreeDiffPrAdd',
        \ {'text': '┃', 'texthl': 'GitTreeDiffPrAddSign'})
  call sign_define('GitTreeDiffPrDel',
        \ {'text': '▁', 'texthl': 'GitTreeDiffPrDelSign'})
  call sign_define('GitTreeDiffPrComment',
        \ {'text': 'C', 'texthl': 'GitTreeDiffPrCommentSign'})
  call sign_define('GitTreeDiffPrLocal',
        \ {'text': '┃', 'texthl': 'GitTreeDiffPrLocalSign'})
  call sign_define('GitTreeDiffPrLocalDel',
        \ {'text': '▁', 'texthl': 'GitTreeDiffPrLocalSign'})
endif

" All arguments are handed through to the underlying 'git diff' invocation.
command! -nargs=* FGitTreeDiff call git_tree_diff#run(<q-args>)

" Browse 'git log --graph --decorate'; the optional argument "all" adds --all.
command! -nargs=? -complete=customlist,git_tree_diff#log_complete
      \ FGitLog call git_tree_diff#log(<q-args>)

" GitHub pull requests (require the 'gh' command line tool).
command! FGitPrList call git_tree_diff#pr#list()
command! FGitPrOpenComment call git_tree_diff#pr#open_comment()
command! FGitPrCommentsOpen call git_tree_diff#pr#comments_open()
command! FGitPrCommentsClose call git_tree_diff#pr#comments_close()
command! FGitPrCommentsToggle call git_tree_diff#pr#comments_toggle()
command! FGitPrReply call git_tree_diff#pr#reply()
command! FGitPrNewComment call git_tree_diff#pr#new_comment()
