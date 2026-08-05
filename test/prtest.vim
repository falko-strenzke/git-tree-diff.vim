set nocompatible
let s:here = expand('<sfile>:p:h')
let &runtimepath = fnamemodify(s:here, ':h') . ',' . &runtimepath
filetype on
let s:S = $GTD_TEST_DIR
let g:git_tree_diff_gh_cmd = s:here . '/gh'
runtime plugin/git_tree_diff.vim

let s:res = []
function! Check(name, cond) abort
  call add(g:gtd_test_res, (a:cond ? 'PASS ' : 'FAIL ') . a:name)
endfunction
let g:gtd_test_res = s:res

try
  " --- 1. PR list -----------------------------------------------------------
  FGitPrList
  call Check('list bufname', bufname('%') ==# 'gtd-pr://list')
  call Check('list lines', line('$') == 2)
  call Check('list line1', getline(1) =~# '#7\s\+Add frobnicator.*\[alice · feature/frob · 2026-07-29\]')
  call Check('list line2', getline(2) =~# '#9\s\+Fix typos')
  call Check('list ft', &filetype ==# 'gittreediffprlist')

  " --- 2. open PR #7 --------------------------------------------------------
  call cursor(1, 1)
  call git_tree_diff#pr#list_select()
  call Check('pr state', exists('t:gtd_pr') && t:gtd_pr.number == 7)
  call Check('pr title', t:gtd_pr.title ==# 'Add frobnicator')
  call Check('pr windows', winnr('$') == 2)
  call Check('tree focus', win_getid() == t:gtd_pr.tree_win)
  call Check('tree lines', join(getline(1, '$'), '|') ==#
        \ 'PR #7|Add frobnicator||src/|  ✚ frob.h|  ● main.c|✖ old.txt')
  call Check('tree width', winwidth(win_id2win(t:gtd_pr.tree_win)) == 34)
  call Check('tree nospell', !&l:spell)

  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('first file name', bufname(s:fbuf) =~# 'gtd-pr://aaaa111122/src/frob\.h')
  call Check('first file content', getbufline(s:fbuf, 1, '$') ==#
        \ ['#ifndef FROB_H', '#define FROB_H', '#endif'])
  let s:signs = sign_getplaced(s:fbuf, {'group': 'gtdpr'})[0].signs
  let s:sn = sort(map(copy(s:signs), 'printf("%d:%s", v:val.lnum, v:val.name)'))
  call Check('frob signs', s:sn ==# ['1:GitTreeDiffPrAdd', '2:GitTreeDiffPrAdd',
        \ '2:GitTreeDiffPrCommentDone', '3:GitTreeDiffPrAdd'])

  " tree: only files with unresolved comments carry a C sign
  " (main.c thread 101 is unresolved, frob.h thread 103 is resolved)
  let s:tbuf = winbufnr(win_id2win(t:gtd_pr.tree_win))
  call Check('tree comment sign', map(sign_getplaced(s:tbuf,
        \ {'group': 'gtdpr'})[0].signs, 'printf("%d:%s", v:val.lnum, v:val.name)')
        \ ==# ['6:GitTreeDiffPrComment'])
  call Check('resolved flags', map(filter(copy(t:gtd_pr.comments),
        \ 'v:val.kind ==# "review"'), 'v:val.id . ":" . v:val.resolved')
        \ ==# ['103:1', '101:0', '102:0'])

  " --- 3. select src/main.c -------------------------------------------------
  call cursor(6, 1)
  call git_tree_diff#pr#tree_select()
  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('main name', bufname(s:fbuf) =~# 'gtd-pr://aaaa111122/src/main\.c')
  call Check('main content', getbufline(s:fbuf, 5, 5) ==# ['  return frob();'])
  let s:signs = sign_getplaced(s:fbuf, {'group': 'gtdpr'})[0].signs
  let s:sn = sort(map(copy(s:signs), 'printf("%d:%s", v:val.lnum, v:val.name)'))
  call Check('main signs', s:sn ==# ['2:GitTreeDiffPrAdd', '5:GitTreeDiffPrAdd',
        \ '5:GitTreeDiffPrComment'])

  " deleted file shows the base version
  call cursor(7, 1)
  call git_tree_diff#pr#tree_select()
  let s:fbuf = winbufnr(win_id2win(t:gtd_pr.file_win))
  call Check('deleted name', bufname(s:fbuf) =~# 'gtd-pr://bbbb111122/old\.txt')
  call Check('deleted content', getbufline(s:fbuf, 1, '$') ==# ['obsolete', 'content'])
  call Check('deleted no signs', empty(sign_getplaced(s:fbuf, {'group': 'gtdpr'})[0].signs))

  " back to main.c for the comment tests
  call cursor(6, 1)
  call git_tree_diff#pr#tree_select()

  " --- 4. open comment from the file window ---------------------------------
  call win_gotoid(t:gtd_pr.file_win)
  call Check('leader map', maparg('\fc', 'n') =~# 'FGitPrOpenComment')
  call cursor(5, 1)
  FGitPrOpenComment
  call Check('comment win', win_id2win(t:gtd_pr.comment_win) > 0)
  call Check('focus back file', win_getid() == t:gtd_pr.file_win)
  let s:cbuf = winbufnr(win_id2win(t:gtd_pr.comment_win))
  call Check('comment name', bufname(s:cbuf) =~# 'gtd-pr://comment/101')
  let s:clines = getbufline(s:cbuf, 1, '$')
  call Check('comment head', s:clines[0] ==# '# PR #7 · src/main.c:5 · unresolved')
  call win_execute(t:gtd_pr.file_win, 'let g:matches = getmatches()')
  let s:cl = filter(copy(g:matches), 'v:val.group ==# "GitTreeDiffPrCommentLine"')
  call Check('line highlight open', len(s:cl) == 1 && s:cl[0].pos1 == [5])
  call Check('default hl style', get(get(hlget('GitTreeDiffPrCommentLine')[0],
        \ 'cterm', {}), 'underline', 0))
  call Check('comment alice', index(s:clines, '## @alice · 2026-07-29 10:11') >= 0)
  call Check('comment bob', index(s:clines, '## @bob · 2026-07-29 11:00') >= 0)
  call Check('comment body split', index(s:clines, 'Seems odd to me.') >= 0)
  call Check('comment ft', getbufvar(s:cbuf, '&filetype') ==# 'markdown')
  call Check('comment ro', !getbufvar(s:cbuf, '&modifiable'))
  call Check('comment current', t:gtd_pr.current ==# {'kind': 'review', 'id': 101})

  " --- 5. comment list ------------------------------------------------------
  FGitPrCommentsOpen
  call Check('clist win', win_getid() == t:gtd_pr.list_win)
  call Check('clist ft', &filetype ==# 'gittreediffprcomments')
  call Check('clist lines', line('$') == 8)
  call Check('clist carol', getline(1) =~# '^@carol · 2026-07-28 09:00 · conversation')
  call Check('clist dave', getline(3) =~# '^@dave · .* · src/frob\.h:2')
  call Check('clist alice', getline(5) =~# '^@alice · 2026-07-29 10:11 · src/main\.c:5')
  call Check('clist bob reply', getline(7) =~# '^↳ @bob')
  call Check('clist preview', getline(6) =~# 'really.*the return value')

  " a resolved thread announces its state and highlights its code line
  call cursor(3, 1)
  call git_tree_diff#pr#comments_select()
  let s:cbuf = winbufnr(win_id2win(t:gtd_pr.comment_win))
  call Check('resolved status', getbufline(s:cbuf, 1, 1) ==#
        \ ['# PR #7 · src/frob.h:2 · resolved'])
  call win_execute(t:gtd_pr.file_win, 'let g:matches = getmatches()')
  let s:cl = filter(copy(g:matches), 'v:val.group ==# "GitTreeDiffPrCommentLine"')
  call Check('line highlight select', len(s:cl) == 1 && s:cl[0].pos1 == [2])

  call cursor(1, 1)
  call git_tree_diff#pr#comments_select()
  let s:cbuf = winbufnr(win_id2win(t:gtd_pr.comment_win))
  call Check('conv comment', getbufline(s:cbuf, 1, 1) ==# ['# PR #7 · conversation'])
  call Check('focus stays list', win_getid() == t:gtd_pr.list_win)
  " a conversation comment has no code location: highlight is cleared
  call win_execute(t:gtd_pr.file_win, 'let g:matches = getmatches()')
  call Check('highlight cleared', empty(filter(copy(g:matches),
        \ 'v:val.group ==# "GitTreeDiffPrCommentLine"')))

  " comment links from the list and from the comment window
  call cursor(5, 1)
  FGitPrCommentCopyLink
  call Check('copy link list', getreg('"') ==#
        \ 'https://github.com/octo/demo/pull/7#discussion_r101')
  call cursor(7, 1)
  FGitPrCommentCopyLink
  call Check('copy link reply', getreg('"') ==#
        \ 'https://github.com/octo/demo/pull/7#discussion_r102')
  call cursor(1, 1)
  call git_tree_diff#pr#comments_select()
  call win_gotoid(t:gtd_pr.comment_win)
  FGitPrCommentCopyLink
  call Check('copy link window', getreg('"') ==#
        \ 'https://github.com/octo/demo/pull/7#issuecomment-201')
  let g:git_tree_diff_browser = s:here . '/browse.sh'
  FGitPrBrowseComment
  sleep 300m
  call Check('browse comment', filereadable(s:S . '/browse.log')
        \ && !empty(filter(readfile(s:S . '/browse.log'),
        \ 'v:val =~# "issuecomment-201"')))
  call win_gotoid(t:gtd_pr.list_win)

  " full conversation view
  FGitPrOpenConversation
  call Check('conv focus', win_getid() == t:gtd_pr.comment_win)
  call Check('conv name', bufname('%') ==# 'gtd-pr://conversation')
  call Check('conv title', getline(1) ==# '# PR #7 · conversation')
  let s:hdrs = filter(getline(1, '$'), 'v:val =~# "^## "')
  call Check('conv order', s:hdrs ==# [
        \ '## @dave · 2026-07-27 08:00 · src/frob.h:2',
        \ '## @carol · 2026-07-28 09:00',
        \ '## @alice · 2026-07-29 10:11 · src/main.c:5',
        \ '## @bob · 2026-07-29 11:00 · src/main.c:5'])
  " link commands act on the comment under the cursor (header or body line)
  call cursor(1, 1)
  call search('@carol')
  FGitPrCommentCopyLink
  call Check('conv copy carol', getreg('"') ==#
        \ 'https://github.com/octo/demo/pull/7#issuecomment-201')
  call search('Seems odd to me')
  FGitPrCommentCopyLink
  call Check('conv copy alice body', getreg('"') ==#
        \ 'https://github.com/octo/demo/pull/7#discussion_r101')
  call cursor(1, 1)
  call search('@dave')
  FGitPrBrowseComment
  sleep 300m
  call Check('conv browse dave', !empty(filter(readfile(s:S . '/browse.log'),
        \ 'v:val =~# "discussion_r103"')))
  call win_gotoid(t:gtd_pr.list_win)

  " selecting a review comment jumps the file window to the code location
  call win_gotoid(t:gtd_pr.tree_win)
  call cursor(5, 1)
  call git_tree_diff#pr#tree_select()
  call Check('file is frob', bufname(winbufnr(win_id2win(t:gtd_pr.file_win))) =~# 'frob\.h')
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(5, 1)
  call git_tree_diff#pr#comments_select()
  call Check('jump file', bufname(winbufnr(win_id2win(t:gtd_pr.file_win))) =~# 'src/main\.c')
  call win_execute(t:gtd_pr.file_win, 'let g:jline = line(".")')
  call Check('jump line', g:jline == 5)
  call win_execute(t:gtd_pr.tree_win, 'let g:tline = line(".")')
  call Check('jump tree sync', g:tline == 6)
  call Check('jump focus list', win_getid() == t:gtd_pr.list_win)

  " a closed fold concealing the line is opened
  call win_execute(t:gtd_pr.file_win, 'setlocal foldmethod=manual | 1,6fold | normal! zM')
  call win_execute(t:gtd_pr.file_win, 'let g:folded = foldclosed(5)')
  call Check('fold closed', g:folded == 1)
  call git_tree_diff#pr#comments_select()
  call win_execute(t:gtd_pr.file_win, 'let g:folded = foldclosed(5) | let g:jline = line(".")')
  call Check('fold opened', g:folded == -1 && g:jline == 5)

  FGitPrCommentsToggle
  call Check('toggle closed', !win_id2win(t:gtd_pr.list_win))
  FGitPrCommentsToggle
  call Check('toggle open', win_id2win(t:gtd_pr.list_win) > 0)
  FGitPrCommentsClose
  call Check('close cmd', !win_id2win(t:gtd_pr.list_win))
  FGitPrCommentsOpen

  " resolving conversations from the four contexts
  function! ResolveCount() abort
    return len(filter(readfile(g:gtd_S . '/gh.log'),
          \ 'v:val =~# "resolveReviewThread(input: {threadId: .RT_kwDO101.})"'))
  endfunction
  let g:gtd_S = s:S
  " a) comment list (cursor on unresolved @alice)
  call cursor(5, 1)
  FGitPrResolve
  call Check('resolve from list', ResolveCount() == 1)
  " already-resolved thread (@dave) triggers no mutation
  call cursor(3, 1)
  FGitPrResolve
  call Check('resolve resolved noop', len(filter(readfile(s:S . '/gh.log'),
        \ 'v:val =~# "resolveReviewThread"')) == 1)
  " b) code window, cursor on the commented line
  call win_gotoid(t:gtd_pr.file_win)
  call cursor(5, 1)
  FGitPrResolve
  call Check('resolve from code', ResolveCount() == 2)
  " c) conversation view, cursor inside @alice's comment
  FGitPrOpenConversation
  call cursor(1, 1)
  call search('Seems odd to me')
  FGitPrResolve
  call Check('resolve from conversation', ResolveCount() == 3)
  " c) comment window showing the thread
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(5, 1)
  call git_tree_diff#pr#comments_select()
  call win_gotoid(t:gtd_pr.comment_win)
  FGitPrResolve
  call Check('resolve from comment win', ResolveCount() == 4)
  call win_gotoid(t:gtd_pr.list_win)

  " unresolving: works on the resolved @dave thread, no-op on @alice
  call cursor(3, 1)
  FGitPrUnresolve
  call Check('unresolve from list', len(filter(readfile(s:S . '/gh.log'),
        \ 'v:val =~# "unresolveReviewThread(input: {threadId: .RT_kwDO103.})"'))
        \ == 1)
  call cursor(5, 1)
  FGitPrUnresolve
  call Check('unresolve unresolved noop',
        \ len(filter(readfile(s:S . '/gh.log'),
        \ 'v:val =~# "unresolveReviewThread"')) == 1)

  " automatic comment opening
  call win_gotoid(t:gtd_pr.file_win)
  call cursor(1, 1)
  FGitPrCommentAutoOpenOn
  call cursor(5, 1)
  doautocmd CursorMoved
  call Check('auto open', bufname(winbufnr(win_id2win(t:gtd_pr.comment_win)))
        \ =~# 'gtd-pr://comment/101')
  " a line whose conversations are all resolved (frob.h:2) opens too
  call win_gotoid(t:gtd_pr.tree_win)
  call cursor(5, 1)
  call git_tree_diff#pr#tree_select()
  call win_gotoid(t:gtd_pr.file_win)
  call cursor(2, 1)
  doautocmd CursorMoved
  call Check('auto open opens resolved',
        \ bufname(winbufnr(win_id2win(t:gtd_pr.comment_win)))
        \ =~# 'gtd-pr://comment/103')
  " back to main.c for the remaining tests
  call win_gotoid(t:gtd_pr.tree_win)
  call cursor(6, 1)
  call git_tree_diff#pr#tree_select()
  call win_gotoid(t:gtd_pr.file_win)
  FGitPrCommentAutoOpenOff
  " show a different comment, then move over the marker again: no change
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(1, 1)
  call git_tree_diff#pr#comments_select()
  call win_gotoid(t:gtd_pr.file_win)
  call cursor(4, 1)
  doautocmd CursorMoved
  call cursor(5, 1)
  doautocmd CursorMoved
  call Check('auto open off', bufname(winbufnr(win_id2win(t:gtd_pr.comment_win)))
        \ =~# 'gtd-pr://comment/201')
  call win_gotoid(t:gtd_pr.list_win)

  " --- 6. reply from the comment list ---------------------------------------
  " a conversation comment (@carol, no file line) cannot be replied to
  call cursor(1, 1)
  FGitPrReply
  call Check('no reply to conversation comment',
        \ execute('messages') =~# 'conversation comments cannot be replied to'
        \ && exists('b:gtd_pr_clist'))
  call cursor(5, 1)
  FGitPrReply
  call Check('compose ft', &filetype ==# 'markdown')
  call Check('compose acwrite', &buftype ==# 'acwrite')
  call Check('compose hint', getline(1) =~# '^<!--.*-->$')
  call setline(2, ['Reply body line 1', '', 'line 3'])
  silent write
  call Check('compose closed', &buftype !=# 'acwrite')
  let s:post = readfile(s:S . '/post.log')
  call Check('reply url', s:post[0] ==# 'URL: repos/octo/demo/pulls/7/comments/101/replies')
  call Check('reply body', s:post[1] =~# '"body"' && s:post[1] =~# 'Reply body line 1\\n\\nline 3')
  call Check('clist refreshed', win_id2win(t:gtd_pr.list_win) > 0
        \ && len(getbufline(winbufnr(win_id2win(t:gtd_pr.list_win)), 1, '$')) == 8)

  " --- 7. new comment -------------------------------------------------------
  FGitPrNewComment
  call setline(2, 'A brand new comment.')
  silent write
  let s:post = readfile(s:S . '/post.log')
  call Check('new url', len(s:post) == 4 && s:post[2] ==# 'URL: repos/octo/demo/issues/7/comments')
  call Check('new body', s:post[3] =~# 'A brand new comment\.')

  " empty comment is not sent
  FGitPrNewComment
  silent write
  call Check('empty not sent', len(readfile(s:S . '/post.log')) == 4)
  bwipeout!

  " comments were re-fetched after each successful post and (un)resolve
  " (initial + 4 resolves + 1 unresolve + 2 posts)
  let s:log = readfile(s:S . '/gh.log')
  call Check('refetch count', len(filter(copy(s:log),
        \ 'v:val =~# "pulls/7/comments?per_page"')) == 8)

  " checkout from the PR tab and from the PR list
  FGitPrCheckoutBranch
  call Check('checkout from tab', !empty(filter(readfile(s:S . '/gh.log'),
        \ 'v:val =~# "^pr checkout 7"')))
  tabfirst
  call cursor(2, 1)
  FGitPrCheckoutBranch
  call Check('checkout from list', !empty(filter(readfile(s:S . '/gh.log'),
        \ 'v:val =~# "^pr checkout 9"')))

  " --- 8. immediate comment window refresh ----------------------------------
  tablast
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(5, 1)
  call git_tree_diff#pr#comments_select()
  let s:CBuf = {-> winbufnr(win_id2win(t:gtd_pr.comment_win))}
  call Check('refresh: state before', getbufline(s:CBuf(), 1, 1)[0]
        \ =~# '· unresolved$')
  " resolving from the comment window updates the shown state at once
  call writefile(readfile(s:S . '/fixtures/graphql_resolved.json'),
        \ s:S . '/fixtures/graphql.json')
  call win_gotoid(t:gtd_pr.comment_win)
  FGitPrResolve
  call Check('refresh: resolved shown', getline(1) =~# '· resolved$')
  " a posted reply appears in the comment window at once
  call writefile(readfile(s:S . '/fixtures/rev_replied.json'),
        \ s:S . '/fixtures/rev.json')
  FGitPrReply
  call setline(2, 'Agreed, will fix.')
  silent write
  call Check('refresh: reply shown', !empty(filter(getbufline(s:CBuf(), 1, '$'),
        \ 'v:val =~# "@erin"')))
  " ... and in the conversation view
  FGitPrOpenConversation
  call Check('conversation shows reply', !empty(filter(
        \ getbufline(s:CBuf(), 1, '$'), 'v:val =~# "@erin"')))
  call writefile(readfile(s:S . '/fixtures/rev_replied2.json'),
        \ s:S . '/fixtures/rev.json')
  call search('Agreed, will fix')
  FGitPrReply
  call setline(2, 'Second thoughts about this.')
  silent write
  call Check('refresh: conversation updated',
        \ bufname(s:CBuf()) =~# 'gtd-pr://conversation$'
        \ && !empty(filter(getbufline(s:CBuf(), 1, '$'), 'v:val =~# "@frank"')))

  " --- 9. suggested changes -------------------------------------------------
  " suggestions are rendered in the comment window as markdown blocks
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(3, 1)
  call git_tree_diff#pr#comments_select()
  call Check('suggestion shown', !empty(filter(getbufline(s:CBuf(), 1, '$'),
        \ 'v:val =~# "^```suggestion$"')))
  " applying needs the checked out working tree copy
  call win_gotoid(t:gtd_pr.comment_win)
  call cursor(1, 1)
  call search('^```suggestion$')
  FGitPrApplySuggestion
  call Check('apply needs checkout',
        \ execute('messages') =~# 'branch is not checked out')
  call cursor(1, 1)
  FGitPrApplySuggestion
  call Check('apply not on suggestion',
        \ execute('messages') =~# 'not on a suggested change')

  " --- 10. reopening the file tree ------------------------------------------
  call win_execute(t:gtd_pr.tree_win, 'close')
  call Check('tree closed', win_id2win(t:gtd_pr.tree_win) == 0)
  FGitPrFileTreeOpen
  call Check('tree reopened', win_id2win(t:gtd_pr.tree_win) > 0
        \ && win_getid() == t:gtd_pr.tree_win
        \ && win_screenpos(win_id2win(t:gtd_pr.tree_win))[1] == 1
        \ && &filetype ==# 'gittreediff')
  call Check('tree reopened content', len(b:gtd_map) == line('$')
        \ && !empty(filter(copy(b:gtd_map),
        \ '!empty(v:val) && !v:val.isdir && v:val.path ==# "src/main.c"')))
  " the file shown in the file window is selected again
  call Check('tree reopened selection', getline(line('.')) =~# 'frob\.h')
  " when already visible, the tree window is only focused
  call win_gotoid(t:gtd_pr.file_win)
  FGitPrFileTreeOpen
  call Check('tree open focuses', win_getid() == t:gtd_pr.tree_win)

  " --- 11. stale commented-line highlight -----------------------------------
  " the @dave thread is still shown: its line highlight is in the file window
  call win_gotoid(t:gtd_pr.file_win)
  call Check('line match present', exists('w:gtd_pr_line_match')
        \ && w:gtd_pr_line_path ==# 'src/frob.h')
  " switching the buffer outside the plugin must clear the highlight
  enew
  call Check('line match cleared on buffer switch',
        \ !exists('w:gtd_pr_line_match') && !exists('w:gtd_pr_line_path'))
  " reopening a comment re-adds it; closing the comment window removes it
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(3, 1)
  call git_tree_diff#pr#comments_select()
  call win_gotoid(t:gtd_pr.file_win)
  call Check('line match re-added', exists('w:gtd_pr_line_match'))
  call win_execute(t:gtd_pr.comment_win, 'close')
  call Check('line match cleared on comment close',
        \ !exists('w:gtd_pr_line_match'))

  " --- 12. note about further conversations on the same line ----------------
  " two independent threads on main.c:5; a fresh PR tab picks them up
  call writefile(['[',
        \ ' {"id": 101, "path": "src/main.c", "line": 5, "original_line": 5,',
        \ '  "in_reply_to_id": null, "user": {"login": "alice"},',
        \ '  "created_at": "2026-07-29T10:11:12Z",',
        \ '  "html_url": "https://github.com/octo/demo/pull/7#discussion_r101",',
        \ '  "body": "Root one."},',
        \ ' {"id": 106, "path": "src/main.c", "line": 5, "original_line": 5,',
        \ '  "in_reply_to_id": null, "user": {"login": "grace"},',
        \ '  "created_at": "2026-07-30T09:00:00Z",',
        \ '  "html_url": "https://github.com/octo/demo/pull/7#discussion_r106",',
        \ '  "body": "Root two."},',
        \ ' {"id": 103, "path": "src/frob.h", "line": 2, "original_line": 2,',
        \ '  "in_reply_to_id": null, "user": {"login": "dave"},',
        \ '  "created_at": "2026-07-27T08:00:00Z",',
        \ '  "html_url": "https://github.com/octo/demo/pull/7#discussion_r103",',
        \ '  "body": "Guard comment please."}',
        \ ']'], s:S . '/fixtures/rev.json')
  tabfirst
  call cursor(1, 1)
  call git_tree_diff#pr#list_select()
  FGitPrCommentsOpen
  call cursor(1, 1)
  call search('@alice')
  call git_tree_diff#pr#comments_select()
  call Check('more-on-line note', getbufline(s:CBuf(), '$')[0]
        \ =~# '^_1 more conversation on this line')
  " the other thread on the same line carries the note as well
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(1, 1)
  call search('@grace')
  call git_tree_diff#pr#comments_select()
  call Check('note on other thread', getbufline(s:CBuf(), '$')[0]
        \ =~# '^_1 more conversation on this line')
  " a line with a single conversation gets no note
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(1, 1)
  call search('@dave')
  call git_tree_diff#pr#comments_select()
  call Check('no note for single thread',
        \ empty(filter(getbufline(s:CBuf(), 1, '$'),
        \ 'v:val =~# "more conversation"')))

  " --- 13. outdated comments: relocation by line content --------------------
  " GitHub reports no current line for outdated threads; the plugin falls
  " back to the original line and, if the commented line's text is unique in
  " the head version, relocates the comment there
  call writefile(['[',
        \ ' {"id": 301, "path": "src/main.c", "line": null,',
        \ '  "original_line": 99,',
        \ '  "diff_hunk": "@@ -1,2 +1,2 @@\n+int main(void) {",',
        \ '  "in_reply_to_id": null, "user": {"login": "rita"},',
        \ '  "created_at": "2026-08-01T10:00:00Z",',
        \ '  "html_url": "https://github.com/octo/demo/pull/7#discussion_r301",',
        \ '  "body": "Outdated but findable."},',
        \ ' {"id": 302, "path": "src/main.c", "line": null,',
        \ '  "original_line": 400,',
        \ '  "diff_hunk": "@@ -1,2 +1,2 @@\n+vanished_line();",',
        \ '  "in_reply_to_id": null, "user": {"login": "otto"},',
        \ '  "created_at": "2026-08-01T11:00:00Z",',
        \ '  "html_url": "https://github.com/octo/demo/pull/7#discussion_r302",',
        \ '  "body": "Outdated and gone."}',
        \ ']'], s:S . '/fixtures/rev.json')
  tabfirst
  call cursor(1, 1)
  call git_tree_diff#pr#list_select()
  let s:reloc = filter(copy(t:gtd_pr.comments), 'v:val.id == 301')[0]
  call Check('outdated comment relocated',
        \ s:reloc.line == 4 && s:reloc.moved_from == 99)
  let s:stay = filter(copy(t:gtd_pr.comments), 'v:val.id == 302')[0]
  call Check('unmatched outdated comment keeps line',
        \ s:stay.line == 400 && s:stay.moved_from == 0)
  " the relocated comment gets its gutter sign at the matched line
  call win_gotoid(t:gtd_pr.tree_win)
  call cursor(6, 1)
  call git_tree_diff#pr#tree_select()
  let s:msigns = map(sign_getplaced(winbufnr(win_id2win(t:gtd_pr.file_win)),
        \ {'group': 'gtdpr'})[0].signs,
        \ 'printf("%d:%s", v:val.lnum, v:val.name)')
  call Check('relocated comment sign',
        \ index(s:msigns, '4:GitTreeDiffPrComment') >= 0)
  " the comment window notes the relocation / the outdated position
  FGitPrCommentsOpen
  call cursor(1, 1)
  call search('@rita')
  call git_tree_diff#pr#comments_select()
  call Check('relocation note', getbufline(s:CBuf(), 2)[0]
        \ =~# '^_outdated comment: relocated from original line 99')
  call win_gotoid(t:gtd_pr.list_win)
  call cursor(1, 1)
  call search('@otto')
  call git_tree_diff#pr#comments_select()
  call Check('outdated note', getbufline(s:CBuf(), 2)[0]
        \ =~# '^_outdated comment: line 400 refers to an old version')

  " --- 14. one-minute comment cache -----------------------------------------
  " a comment added on github is not picked up while the cache is fresh
  call writefile(['[',
        \ ' {"id": 301, "path": "src/main.c", "line": null,',
        \ '  "original_line": 99,',
        \ '  "diff_hunk": "@@ -1,2 +1,2 @@\n+int main(void) {",',
        \ '  "in_reply_to_id": null, "user": {"login": "rita"},',
        \ '  "created_at": "2026-08-01T10:00:00Z",',
        \ '  "html_url": "https://github.com/octo/demo/pull/7#discussion_r301",',
        \ '  "body": "Outdated but findable."},',
        \ ' {"id": 303, "path": "src/main.c", "line": 5, "original_line": 5,',
        \ '  "in_reply_to_id": null, "user": {"login": "zoe"},',
        \ '  "created_at": "2026-08-02T09:00:00Z",',
        \ '  "html_url": "https://github.com/octo/demo/pull/7#discussion_r303",',
        \ '  "body": "Fresh from github."}',
        \ ']'], s:S . '/fixtures/rev.json')
  FGitPrCommentsOpen
  call Check('fresh cache not refetched',
        \ empty(filter(copy(t:gtd_pr.comments), 'v:val.user ==# "zoe"')))
  " after expiry the next access re-fetches and rebuilds the list
  let t:gtd_pr.comments_time = 0
  FGitPrCommentsOpen
  call Check('expired cache refetched',
        \ len(filter(copy(t:gtd_pr.comments), 'v:val.user ==# "zoe"')) == 1
        \ && !empty(filter(getbufline(winbufnr(win_id2win(t:gtd_pr.list_win)),
        \ 1, '$'), 'v:val =~# "@zoe"')))
catch
  call add(s:res, 'EXCEPTION: ' . v:exception . ' @ ' . v:throwpoint)
endtry

call writefile(s:res, s:S . '/results.txt')
qa!
