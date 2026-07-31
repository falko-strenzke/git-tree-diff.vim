" Tests for the checked-out-PR scenario: repo2's HEAD equals the PR head.
set nocompatible
let s:here = expand('<sfile>:p:h')
let &runtimepath = fnamemodify(s:here, ':h') . ',' . &runtimepath
filetype on
let s:S = $GTD_TEST_DIR
let g:git_tree_diff_gh_cmd = s:here . '/gh'
let g:git_tree_diff_pr_highlight_style = 'background'
runtime plugin/git_tree_diff.vim

let s:res = []
function! Check(name, cond) abort
  call add(g:gtd_test_res, (a:cond ? 'PASS ' : 'FAIL ') . a:name)
endfunction
let g:gtd_test_res = s:res

function! s:Signs(buf) abort
  return sort(map(sign_getplaced(a:buf, {'group': 'gtdpr'})[0].signs,
        \ 'printf("%d:%s", v:val.lnum, v:val.name)'))
endfunction

try
  call Check('bg hl style', get(hlget('GitTreeDiffPrCommentLine')[0],
        \ 'linksto', '') ==# 'CursorColumn')
  FGitPrList
  call cursor(1, 1)
  call git_tree_diff#pr#list_select()

  " first file (src/frob.h, locally modified) is opened as the real file
  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('worktree buffer', bufname(s:fbuf) !~# '^gtd-pr://'
        \ && bufname(s:fbuf) =~# 'frob\.h')
  call Check('worktree editable', getbufvar(s:fbuf, '&buftype') ==# ''
        \ && getbufvar(s:fbuf, '&modifiable'))
  call Check('worktree local content',
        \ getbufline(s:fbuf, 1, '$') ==# ['#ifndef FROB_H',
        \ '#define FROB_H 1', '#endif', 'new local line'])
  " PR adds 1-3; local changes in red: line 2 modified, line 4 appended
  call Check('worktree signs', s:Signs(s:fbuf) ==# ['1:GitTreeDiffPrAdd',
        \ '2:GitTreeDiffPrAdd', '2:GitTreeDiffPrCommentDone',
        \ '2:GitTreeDiffPrLocal', '2:GitTreeDiffPrLocalDel',
        \ '3:GitTreeDiffPrAdd', '4:GitTreeDiffPrLocal'])

  " tree: C sign only on the file with the unresolved comment (main.c)
  call Check('tree comment sign', s:Signs(winbufnr(win_id2win(t:gtd_pr.tree_win)))
        \ ==# ['6:GitTreeDiffPrComment'])

  " a file deleted by the PR still shows the base version as scratch
  call win_gotoid(t:gtd_pr.tree_win)
  call cursor(7, 1)
  call git_tree_diff#pr#tree_select()
  call Check('deleted scratch', bufname(winbufnr(win_id2win(t:gtd_pr.file_win)))
        \ =~# '^gtd-pr://.*old\.txt')

  " selecting a review comment opens the local copy and jumps to the line
  FGitPrCommentsOpen
  call cursor(5, 1)
  call git_tree_diff#pr#comments_select()
  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('jump local file', bufname(s:fbuf) !~# '^gtd-pr://'
        \ && bufname(s:fbuf) =~# 'main\.c')
  call win_execute(t:gtd_pr.file_win, 'let g:jline = line(".")')
  call Check('jump local line', g:jline == 5)
  " main.c is locally unmodified: no red signs
  call Check('no local signs',
        \ empty(filter(s:Signs(s:fbuf), 'v:val =~# "Local"')))

  " editing and saving the file refreshes the red marks
  call win_gotoid(t:gtd_pr.file_win)
  call append(line('$'), 'int locally_added;')
  silent write
  call Check('local sign after save',
        \ filter(s:Signs(bufnr('%')), 'v:val =~# "Local"')
        \ ==# ['7:GitTreeDiffPrLocal'])

  " reopening the modified buffer from the tree keeps the unsaved changes
  call setline(1, '#include <stdio.h> /* modified */')
  call win_gotoid(t:gtd_pr.tree_win)
  call cursor(6, 1)
  call git_tree_diff#pr#tree_select()
  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('unsaved kept', getbufline(s:fbuf, 1, 1)
        \ ==# ['#include <stdio.h> /* modified */']
        \ && getbufvar(s:fbuf, '&modified'))

  " --- FGitPrOfCurrentBranch ------------------------------------------------
  " exactly one PR for the checked out branch: opened directly
  call writefile(['[{"number": 7, "title": "Add frobnicator",'
        \ . ' "author": {"login": "alice"}, "headRefName": "feature/frob",'
        \ . ' "updatedAt": "2026-07-29T12:00:00Z"}]'],
        \ s:S . '/fixtures/prhead.json')
  FGitPrOfCurrentBranch
  call Check('branch pr opened', exists('t:gtd_pr') && t:gtd_pr.number == 7)
  call Check('branch pr query', !empty(filter(readfile(s:S . '/gh.log'),
        \ 'v:val =~# "^pr list --head feature/frob "')))
  " several PRs with this head branch: a filtered list window is shown
  call writefile(['[{"number": 7, "title": "Add frobnicator",'
        \ . ' "author": {"login": "alice"}, "headRefName": "feature/frob",'
        \ . ' "updatedAt": "2026-07-29T12:00:00Z"},'
        \ . ' {"number": 8, "title": "Frobnicator against v2 base",'
        \ . ' "author": {"login": "alice"}, "headRefName": "feature/frob",'
        \ . ' "updatedAt": "2026-07-30T12:00:00Z"}]'],
        \ s:S . '/fixtures/prhead.json')
  FGitPrOfCurrentBranch
  call Check('branch pr list', &filetype ==# 'gittreediffprlist'
        \ && len(get(b:, 'gtd_pr_prs', [])) == 2
        \ && getline(1) =~# '^#7 ' && getline(2) =~# '^#8 ')
  call cursor(1, 1)
  call git_tree_diff#pr#list_select()
  call Check('branch list select', exists('t:gtd_pr') && t:gtd_pr.number == 7)
  " no PR for the branch: message only, nothing is opened
  call writefile(['[]'], s:S . '/fixtures/prhead.json')
  let s:tabs = tabpagenr('$')
  FGitPrOfCurrentBranch
  call Check('branch no pr', tabpagenr('$') == s:tabs)

  " --- applying suggested changes -------------------------------------------
  " single-line suggestion (@dave, frob.h line 2), applied from the thread
  FGitPrCommentsOpen
  call cursor(3, 1)
  call git_tree_diff#pr#comments_select()
  call win_gotoid(t:gtd_pr.comment_win)
  call cursor(1, 1)
  call search('^```suggestion$')
  FGitPrApplySuggestion
  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('suggestion applied', bufname(s:fbuf) =~# 'frob\.h'
        \ && getbufline(s:fbuf, 2, 2) ==# ['#define FROB_H /* include guard */']
        \ && getbufvar(s:fbuf, '&modified'))
  call win_execute(t:gtd_pr.file_win, 'let g:sline = line(".")')
  call Check('suggestion cursor', g:sline == 2)
  call win_execute(t:gtd_pr.file_win, 'silent write')
  " multi-line suggestion (@bob, main.c lines 4-5 via start_line)
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(7, 1)
  call git_tree_diff#pr#comments_select()
  call win_gotoid(t:gtd_pr.comment_win)
  call cursor(1, 1)
  call search('^```suggestion$')
  FGitPrApplySuggestion
  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('multiline suggestion applied', bufname(s:fbuf) =~# 'main\.c'
        \ && getbufline(s:fbuf, 4, 6) ==# ['int main(void) {  /* entry */',
        \ '  return frob() + 1;', '}'])
catch
  call add(s:res, 'EXCEPTION: ' . v:exception . ' @ ' . v:throwpoint)
endtry

call writefile(s:res, s:S . '/results2.txt')
qa!
