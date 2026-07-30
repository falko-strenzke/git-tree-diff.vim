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
highlight default link GitTreeDiffPrCommentDoneSign Comment
highlight default GitTreeDiffPrLocalSign ctermfg=Red guifg=Red

" Highlight of the commented code line while its comment is shown, see
" g:git_tree_diff_pr_highlight_style.
let s:style = get(g:, 'git_tree_diff_pr_highlight_style', 'underline')
if s:style ==# 'italic'
  highlight default GitTreeDiffPrCommentLine cterm=italic gui=italic
elseif s:style ==# 'background'
  highlight default link GitTreeDiffPrCommentLine CursorColumn
else
  highlight default GitTreeDiffPrCommentLine cterm=underline gui=underline
endif
unlet s:style

if exists('*sign_define')
  call sign_define('GitTreeDiffPrAdd',
        \ {'text': '┃', 'texthl': 'GitTreeDiffPrAddSign'})
  call sign_define('GitTreeDiffPrDel',
        \ {'text': '▁', 'texthl': 'GitTreeDiffPrDelSign'})
  call sign_define('GitTreeDiffPrComment',
        \ {'text': 'C', 'texthl': 'GitTreeDiffPrCommentSign'})
  call sign_define('GitTreeDiffPrCommentDone',
        \ {'text': 'C', 'texthl': 'GitTreeDiffPrCommentDoneSign'})
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
command! FGitPrCheckoutBranch call git_tree_diff#pr#checkout()
command! FGitPrOpenConversation call git_tree_diff#pr#open_conversation()
command! FGitPrBrowseComment call git_tree_diff#pr#browse_comment()
command! FGitPrCommentCopyLink call git_tree_diff#pr#copy_link()
command! FGitPrResolve call git_tree_diff#pr#resolve()
command! FGitPrUnresolve call git_tree_diff#pr#unresolve()
