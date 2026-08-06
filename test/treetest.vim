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
  " icons: e.txt appears via rename, a modified, b deleted, d added, f modified
  call Check('tree icons', getline(4, '$') ==#
        \ ['sub/', '  ✚ e.txt', '● a.txt', '✖ b.txt', '✚ d.txt', '● f.c'])
  call Check('map status', map(filter(copy(b:gtd_map),
        \ '!empty(v:val) && !v:val.isdir'), 'v:val.path . ":" . v:val.status')
        \ ==# ['sub/e.txt:A', 'a.txt:M', 'b.txt:D', 'd.txt:A', 'f.c:M'])
  " selecting an icon-carrying entry still opens the right diff: the deleted
  " file shows its old content on the left and nothing on the right
  call cursor(7, 1)
  call git_tree_diff#select()
  call Check('deleted file diff',
        \ getbufline(winbufnr(win_id2win(t:gtd.left_win)), 1, '$') ==# ['bee']
        \ && getbufline(winbufnr(win_id2win(t:gtd.right_win)), 1, '$') ==# [''])

  " opening a diff adds the readability items to the global 'diffopt'
  call Check('diffopt items', &diffopt =~# 'algorithm:histogram'
        \ && &diffopt =~# 'linematch:60')

  " f.c: bar() moved above foo(), foo() edited.  The unique common lines of
  " the two versions - 'int foo() {', '    return n;', 'int g = 1;',
  " 'int bar(int a) {', '    return a * 2;' - allow the anchor pairs
  " (1,5) (3,7) (6,10) (8,1) (9,2); the longest monotonic subset is
  " (1,5) (3,7) (6,10).
  call win_gotoid(t:gtd.tree_win)
  call cursor(9, 1)
  call git_tree_diff#select()
  let s:lb = winbufnr(win_id2win(t:gtd.left_win))
  let s:rb = winbufnr(win_id2win(t:gtd.right_win))
  if exists('+diffanchors')
    call Check('auto anchors', getbufvar(s:lb, '&diffanchors') ==# '1,3,6'
          \ && getbufvar(s:rb, '&diffanchors') ==# '5,7,10')
    call Check('anchor diffopt', &diffopt =~# '\<anchor\>')
    FGitTreeDiffAutoAnchorsToggle
    call Check('anchors toggled off', getbufvar(s:lb, '&diffanchors') ==# ''
          \ && getbufvar(s:rb, '&diffanchors') ==# '')
    FGitTreeDiffAutoAnchorsToggle
    call Check('anchors toggled on',
          \ getbufvar(s:lb, '&diffanchors') ==# '1,3,6')
    " manual anchor pair in two steps: old bar() head to new bar() head;
    " it crosses every automatic pair, so it remains as the only anchor
    call win_gotoid(t:gtd.left_win)
    call cursor(8, 1)
    FGitTreeDiffAnchorAdd
    call win_gotoid(t:gtd.right_win)
    call cursor(1, 1)
    FGitTreeDiffAnchorAdd
    call Check('manual anchor', getbufvar(s:lb, '&diffanchors') ==# '8'
          \ && getbufvar(s:rb, '&diffanchors') ==# '1')
    FGitTreeDiffAnchorsClear
    call Check('manual anchors cleared',
          \ getbufvar(s:lb, '&diffanchors') ==# '1,3,6'
          \ && getbufvar(s:rb, '&diffanchors') ==# '5,7,10')
  endif
catch
  call add(s:res, 'EXCEPTION: ' . v:exception . ' @ ' . v:throwpoint)
endtry

call writefile(s:res, s:S . '/results3.txt')
qa!
