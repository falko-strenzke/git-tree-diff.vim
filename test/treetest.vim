" Tests for the :FGitTreeDiff tree view: file status icons in repo3, which
" has a modified, a deleted, an added and a renamed file between HEAD~1
" and HEAD.
set nocompatible
let s:here = expand('<sfile>:p:h')
let &runtimepath = fnamemodify(s:here, ':h') . ',' . &runtimepath
filetype on
runtime plugin/git_tree_diff.vim

let s:res = []
function! Check(name, cond) abort
  call add(g:gtd_test_res, (a:cond ? 'PASS ' : 'FAIL ') . a:name)
endfunction
let g:gtd_test_res = s:res
let s:S = $GTD_TEST_DIR

try
  FGitTreeDiff HEAD~1..HEAD
  call win_gotoid(t:gtd.tree_win)
  " icons: e.txt appears via rename, a modified, b deleted, d added
  call Check('tree icons', getline(4, '$') ==#
        \ ['sub/', '  ✚ e.txt', '● a.txt', '✖ b.txt', '✚ d.txt'])
  call Check('map status', map(filter(copy(b:gtd_map),
        \ '!empty(v:val) && !v:val.isdir'), 'v:val.path . ":" . v:val.status')
        \ ==# ['sub/e.txt:A', 'a.txt:M', 'b.txt:D', 'd.txt:A'])
  " selecting an icon-carrying entry still opens the right diff: the deleted
  " file shows its old content on the left and nothing on the right
  call cursor(7, 1)
  call git_tree_diff#select()
  call Check('deleted file diff',
        \ getbufline(winbufnr(win_id2win(t:gtd.left_win)), 1, '$') ==# ['bee']
        \ && getbufline(winbufnr(win_id2win(t:gtd.right_win)), 1, '$') ==# [''])
catch
  call add(s:res, 'EXCEPTION: ' . v:exception . ' @ ' . v:throwpoint)
endtry

call writefile(s:res, s:S . '/results3.txt')
qa!
