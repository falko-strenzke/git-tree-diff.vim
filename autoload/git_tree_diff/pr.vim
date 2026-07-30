" git_tree_diff/pr.vim - browse GitHub pull requests (:FGitPrList and friends)
"
" All GitHub access goes through the 'gh' command line tool, which must be
" installed and authenticated.  The executable can be overridden with
" g:git_tree_diff_gh_cmd (the test suite uses this to substitute a stub).

" ---------------------------------------------------------------------------
" gh helpers
" ---------------------------------------------------------------------------

function! s:Gh(root, args) abort
  let l:cmd = 'cd ' . shellescape(a:root) . ' && '
        \ . get(g:, 'git_tree_diff_gh_cmd', 'gh') . ' ' . a:args
  let l:out = systemlist(l:cmd)
  return [v:shell_error, l:out]
endfunction

function! s:GhJson(root, args) abort
  let [l:err, l:out] = s:Gh(a:root, a:args)
  if l:err
    return [1, join(l:out, ' ')]
  endif
  try
    return [0, json_decode(join(l:out, "\n"))]
  catch
    return [1, 'invalid JSON from gh']
  endtry
endfunction

" POST a:body (a JSON string) to the given gh api arguments via stdin.
function! s:GhPost(root, args, body) abort
  let l:cmd = 'cd ' . shellescape(a:root) . ' && '
        \ . get(g:, 'git_tree_diff_gh_cmd', 'gh') . ' ' . a:args
  let l:out = system(l:cmd, a:body)
  return [v:shell_error, l:out]
endfunction

function! s:Error(msg) abort
  echohl ErrorMsg | echomsg 'git-tree-diff: ' . a:msg | echohl None
endfunction

function! s:Num(dict, key) abort
  let l:val = get(a:dict, a:key, 0)
  return type(l:val) == v:t_number ? l:val : 0
endfunction

function! s:FmtTime(iso) abort
  return strpart(substitute(a:iso, 'T', ' ', ''), 0, 16)
endfunction

" ---------------------------------------------------------------------------
" :FGitPrList
" ---------------------------------------------------------------------------

function! git_tree_diff#pr#list() abort
  let l:root = git_tree_diff#find_root()
  if empty(l:root)
    return s:Error('not inside a git repository')
  endif
  let [l:err, l:prs] = s:GhJson(l:root,
        \ 'pr list --limit 200 --json number,title,author,headRefName,updatedAt')
  if l:err
    return s:Error('gh pr list failed: ' . l:prs)
  endif
  if empty(l:prs)
    echomsg 'git-tree-diff: no open pull requests'
    return
  endif

  botright new
  execute 'resize ' . min([len(l:prs) + 1, 15])
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber nowrap nolist nospell
  setlocal cursorline signcolumn=no winfixheight
  let b:gtd_pr_root = l:root
  let b:gtd_pr_prs = l:prs
  call setline(1, map(copy(l:prs), 's:FormatPrLine(v:val)'))
  setlocal nomodifiable
  silent! file gtd-pr://list
  setlocal filetype=gittreediffprlist

  nnoremap <buffer> <silent> <CR> :call git_tree_diff#pr#list_select()<CR>
  nnoremap <buffer> <silent> o :call git_tree_diff#pr#list_select()<CR>
  nnoremap <buffer> <silent> <2-LeftMouse> :call git_tree_diff#pr#list_select()<CR>
  nnoremap <buffer> <silent> q :close<CR>
endfunction

function! s:FormatPrLine(pr) abort
  return printf('#%-5d %s   [%s · %s · %s]', a:pr.number, a:pr.title,
        \ get(get(a:pr, 'author', {}), 'login', '?'),
        \ get(a:pr, 'headRefName', ''),
        \ strpart(get(a:pr, 'updatedAt', ''), 0, 10))
endfunction

function! git_tree_diff#pr#list_select() abort
  let l:pr = get(get(b:, 'gtd_pr_prs', []), line('.') - 1, {})
  if empty(l:pr)
    return
  endif
  call git_tree_diff#mark_selected(line('.'))
  call s:OpenPr(b:gtd_pr_root, l:pr.number)
endfunction

" ---------------------------------------------------------------------------
" PR tab
" ---------------------------------------------------------------------------

function! s:OpenPr(root, number) abort
  let [l:err, l:repo] = s:GhJson(a:root, 'repo view --json nameWithOwner')
  if l:err
    return s:Error('gh repo view failed: ' . l:repo)
  endif
  let l:nwo = get(l:repo, 'nameWithOwner', '')

  let [l:err, l:view] = s:GhJson(a:root,
        \ 'api ' . shellescape('repos/' . l:nwo . '/pulls/' . a:number))
  if l:err
    return s:Error('fetching the pull request failed: ' . l:view)
  endif

  let [l:err, l:diff] = s:Gh(a:root, 'pr diff ' . a:number)
  if l:err
    return s:Error('gh pr diff failed: ' . join(l:diff, ' '))
  endif
  let [l:files, l:changes] = s:ParseDiff(l:diff)
  if empty(l:files)
    return s:Error('no changed files in PR #' . a:number)
  endif

  let l:comments = s:FetchComments(a:root, l:nwo, a:number)

  tabnew
  let t:gtd_pr = {
        \ 'root': a:root,
        \ 'nwo': l:nwo,
        \ 'number': a:number,
        \ 'title': get(l:view, 'title', ''),
        \ 'head': get(get(l:view, 'head', {}), 'sha', ''),
        \ 'head_ref': get(get(l:view, 'head', {}), 'ref', ''),
        \ 'base': get(get(l:view, 'base', {}), 'sha', ''),
        \ 'files': l:files,
        \ 'changes': l:changes,
        \ 'comments': l:comments,
        \ 'current': {},
        \ 'tree_win': win_getid(),
        \ 'file_win': 0, 'comment_win': 0, 'list_win': 0,
        \ }
  call s:SetupPrTreeBuffer()

  " automatically show the first changed file
  for l:i in range(len(b:gtd_map))
    if !empty(b:gtd_map[l:i]) && !b:gtd_map[l:i].isdir
      call cursor(l:i + 1, 1)
      call git_tree_diff#pr#tree_select()
      break
    endif
  endfor
endfunction

" Parse a unified diff into the ordered list of changed files and, per file,
" the line numbers (in the new version) of added lines and of positions where
" lines were deleted.
function! s:ParseDiff(lines) abort
  let l:files = []
  let l:changes = {}
  let l:path = ''
  let l:minus = ''
  let l:new = 0
  let l:old_rem = 0
  let l:new_rem = 0
  for l:line in a:lines
    if l:old_rem > 0 || l:new_rem > 0
      let l:ch = strpart(l:line, 0, 1)
      if l:ch ==# '+'
        call add(l:changes[l:path].add, l:new)
        let l:new += 1
        let l:new_rem -= 1
      elseif l:ch ==# '-'
        let l:lnum = max([l:new, 1])
        if empty(l:changes[l:path].del) || l:changes[l:path].del[-1] != l:lnum
          call add(l:changes[l:path].del, l:lnum)
        endif
        let l:old_rem -= 1
      elseif l:ch ==# '\'
        " '\ No newline at end of file'
      else
        let l:new += 1
        let l:old_rem -= 1
        let l:new_rem -= 1
      endif
    elseif l:line =~# '^diff --git '
      let l:path = ''
      let l:minus = ''
    elseif l:line =~# '^--- '
      let l:minus = matchstr(l:line, '^--- a/\zs.*')
    elseif l:line =~# '^+++ '
      if l:line ==# '+++ /dev/null'
        let l:path = l:minus
        let l:deleted = 1
      else
        let l:path = matchstr(l:line, '^+++ b/\zs.*')
        let l:deleted = 0
      endif
      if !empty(l:path)
        call add(l:files, l:path)
        let l:changes[l:path] = {'add': [], 'del': [], 'deleted': l:deleted}
      endif
    elseif l:line =~# '^@@' && !empty(l:path)
      let l:m = matchlist(l:line,
            \ '^@@ -\d\+\%(,\(\d\+\)\)\= +\(\d\+\)\%(,\(\d\+\)\)\= @@')
      if !empty(l:m)
        let l:old_rem = empty(l:m[1]) ? 1 : str2nr(l:m[1])
        let l:new = str2nr(l:m[2])
        let l:new_rem = empty(l:m[3]) ? 1 : str2nr(l:m[3])
      endif
    endif
  endfor
  return [l:files, l:changes]
endfunction

" Fetch review comments (attached to file lines) and issue comments (the PR
" conversation) as one normalized list.
function! s:FetchComments(root, nwo, number) abort
  let l:comments = []
  for [l:kind, l:api] in [['review', 'pulls'], ['issue', 'issues']]
    let [l:err, l:list] = s:GhJson(a:root, 'api ' . shellescape(
          \ 'repos/' . a:nwo . '/' . l:api . '/' . a:number
          \ . '/comments?per_page=100'))
    if l:err || type(l:list) != v:t_list
      echohl WarningMsg
      echomsg 'git-tree-diff: could not fetch ' . l:kind . ' comments'
      echohl None
      continue
    endif
    for l:c in l:list
      let l:line = s:Num(l:c, 'line')
      let l:path = get(l:c, 'path', '')
      call add(l:comments, {
            \ 'kind': l:kind,
            \ 'id': l:c.id,
            \ 'path': type(l:path) == v:t_string ? l:path : '',
            \ 'line': l:line > 0 ? l:line : s:Num(l:c, 'original_line'),
            \ 'reply_to': s:Num(l:c, 'in_reply_to_id'),
            \ 'user': get(get(l:c, 'user', {}), 'login', '?'),
            \ 'time': s:FmtTime(get(l:c, 'created_at', '')),
            \ 'body': get(l:c, 'body', ''),
            \ })
    endfor
  endfor
  " conversation comments first, then review comments grouped by file/line
  call sort(l:comments, function('s:CompareComments'))
  return l:comments
endfunction

function! s:CompareComments(a, b) abort
  if (a:a.kind ==# 'issue') != (a:b.kind ==# 'issue')
    return a:a.kind ==# 'issue' ? -1 : 1
  endif
  if a:a.path !=# a:b.path
    return a:a.path <# a:b.path ? -1 : 1
  endif
  if a:a.line != a:b.line
    return a:a.line < a:b.line ? -1 : 1
  endif
  return a:a.id == a:b.id ? 0 : a:a.id < a:b.id ? -1 : 1
endfunction

" ---------------------------------------------------------------------------
" file tree
" ---------------------------------------------------------------------------

function! s:SetupPrTreeBuffer() abort
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber nowrap nolist nospell
  setlocal winfixwidth cursorline signcolumn=no
  setlocal shiftwidth=2 foldlevel=99
  setlocal foldmethod=expr foldexpr=git_tree_diff#foldexpr(v:lnum)
  setlocal foldtext=git_tree_diff#foldtext()
  silent! execute 'setlocal fillchars+=fold:\ '

  let [l:lines, l:map] = git_tree_diff#tree_lines(t:gtd_pr.files,
        \ ['PR #' . t:gtd_pr.number, t:gtd_pr.title, ''])
  let b:gtd_map = l:map
  call setline(1, l:lines)
  setlocal nomodifiable

  setlocal filetype=gittreediff

  nnoremap <buffer> <silent> <CR> :call git_tree_diff#pr#tree_select()<CR>
  nnoremap <buffer> <silent> o :call git_tree_diff#pr#tree_select()<CR>
  nnoremap <buffer> <silent> <2-LeftMouse> :call git_tree_diff#pr#tree_select()<CR>
  nnoremap <buffer> <silent> q :tabclose<CR>
endfunction

function! git_tree_diff#pr#tree_select() abort
  let l:entry = get(get(b:, 'gtd_map', []), line('.') - 1, {})
  if empty(l:entry) || !exists('t:gtd_pr')
    return
  endif
  if l:entry.isdir
    if foldclosed('.') != -1
      normal! zo
    else
      silent! normal! zc
    endif
  else
    call git_tree_diff#mark_selected(line('.'))
    let l:origin = win_getid()
    call s:OpenFile(l:entry.path)
    call win_gotoid(l:origin)
  endif
endfunction

" ---------------------------------------------------------------------------
" file window with gutter signs
" ---------------------------------------------------------------------------

function! s:EnsureFileWin() abort
  if !win_id2win(t:gtd_pr.file_win)
    call win_gotoid(t:gtd_pr.tree_win)
    rightbelow vertical new
    let t:gtd_pr.file_win = win_getid()
    call win_gotoid(t:gtd_pr.tree_win)
    execute 'vertical resize ' . get(g:, 'git_tree_diff_width', 34)
  endif
endfunction

function! s:OpenFile(path) abort
  call s:EnsureFileWin()
  call win_gotoid(t:gtd_pr.file_win)
  let l:info = get(t:gtd_pr.changes, a:path,
        \ {'add': [], 'del': [], 'deleted': 0})
  " a deleted file only exists on the base side
  let l:ref = l:info.deleted ? t:gtd_pr.base : t:gtd_pr.head

  " if the PR is checked out, edit the real file so it can be modified
  let l:full = t:gtd_pr.root . '/' . a:path
  if !l:info.deleted && s:PrCheckedOut() && filereadable(l:full)
    " do not reload the file if it is already shown (it may have unsaved
    " local changes)
    if expand('%:p') !=# fnamemodify(l:full, ':p')
      try
        execute 'silent edit ' . fnameescape(l:full)
      catch /E37\|E162/
        echohl WarningMsg
        echomsg 'git-tree-diff: buffer has unsaved changes; save it first'
        echohl None
      endtry
    endif
    augroup gtdpr_local
      autocmd! * <buffer>
      autocmd BufWritePost <buffer> call s:RefreshFileSigns()
    augroup END
  else
    silent enew
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    call setline(1, s:FileContent(l:ref, a:path))
    execute 'silent! file '
          \ . fnameescape('gtd-pr://' . strpart(l:ref, 0, 10) . '/' . a:path)
    filetype detect
    setlocal number nomodifiable
  endif
  setlocal signcolumn=yes
  let b:gtd_pr_path = a:path
  nnoremap <buffer> <silent> <leader>fc :FGitPrOpenComment<CR>
  call s:PlaceSigns(bufnr('%'), a:path)
endfunction

" The PR counts as checked out if HEAD is the PR head commit or the current
" branch is the PR head branch (the local branch may contain additional
" commits on top of the published PR head).
function! s:PrCheckedOut() abort
  let [l:err, l:head] = git_tree_diff#git(t:gtd_pr.root, 'rev-parse HEAD')
  if !l:err && !empty(l:head) && l:head[0] ==# t:gtd_pr.head
    return 1
  endif
  let [l:err, l:branch] = git_tree_diff#git(t:gtd_pr.root,
        \ 'branch --show-current')
  return !l:err && !empty(l:branch) && !empty(t:gtd_pr.head_ref)
        \ && l:branch[0] ==# t:gtd_pr.head_ref
endfunction

function! s:FileContent(ref, path) abort
  " prefer the local object database, fall back to the GitHub contents API
  let [l:err, l:out] = git_tree_diff#git(t:gtd_pr.root,
        \ 'show ' . shellescape(a:ref . ':' . a:path))
  if !l:err
    return l:out
  endif
  let l:url = 'repos/' . t:gtd_pr.nwo . '/contents/' . s:UrlEncode(a:path)
        \ . '?ref=' . a:ref
  let [l:err, l:out] = s:Gh(t:gtd_pr.root, 'api -H '
        \ . shellescape('Accept: application/vnd.github.raw') . ' '
        \ . shellescape(l:url))
  return l:err ? [] : l:out
endfunction

function! s:UrlEncode(path) abort
  return substitute(a:path, '[^A-Za-z0-9_./-]',
        \ '\=printf("%%%02X", char2nr(submatch(0)))', 'g')
endfunction

function! s:PlaceSigns(buf, path) abort
  if !exists('*sign_place')
    return
  endif
  call sign_unplace('gtdpr', {'buffer': a:buf})
  let l:max = get(get(getbufinfo(a:buf), 0, {}), 'linecount', 0)
  let l:info = get(t:gtd_pr.changes, a:path, {})
  if !empty(l:info) && !get(l:info, 'deleted', 0)
    for l:lnum in get(l:info, 'del', [])
      call sign_place(0, 'gtdpr', 'GitTreeDiffPrDel', a:buf,
            \ {'lnum': min([l:lnum, l:max]), 'priority': 10})
    endfor
    for l:lnum in get(l:info, 'add', [])
      if l:lnum <= l:max
        call sign_place(0, 'gtdpr', 'GitTreeDiffPrAdd', a:buf,
              \ {'lnum': l:lnum, 'priority': 10})
      endif
    endfor
  endif
  let l:done = {}
  for l:c in t:gtd_pr.comments
    if l:c.kind ==# 'review' && l:c.path ==# a:path
          \ && l:c.line > 0 && l:c.line <= l:max
          \ && !has_key(l:done, l:c.line)
      let l:done[l:c.line] = 1
      call sign_place(0, 'gtdpr', 'GitTreeDiffPrComment', a:buf,
            \ {'lnum': l:c.line, 'priority': 20})
    endif
  endfor
  " for a checked-out working tree file, mark local modifications relative
  " to the pull request head in red
  if empty(getbufvar(a:buf, '&buftype'))
    let [l:derr, l:dout] = git_tree_diff#git(t:gtd_pr.root,
          \ 'diff ' . shellescape(t:gtd_pr.head) . ' -- ' . shellescape(a:path))
    if !l:derr
      let [l:_, l:lchanges] = s:ParseDiff(l:dout)
      let l:linfo = get(l:lchanges, a:path, {})
      for l:lnum in get(l:linfo, 'del', [])
        call sign_place(0, 'gtdpr', 'GitTreeDiffPrLocalDel', a:buf,
              \ {'lnum': min([l:lnum, l:max]), 'priority': 15})
      endfor
      for l:lnum in get(l:linfo, 'add', [])
        if l:lnum <= l:max
          call sign_place(0, 'gtdpr', 'GitTreeDiffPrLocal', a:buf,
                \ {'lnum': l:lnum, 'priority': 15})
        endif
      endfor
    endif
  endif
endfunction

" BufWritePost handler of checked-out pull request files: recompute the
" gutter signs after saving.
function! s:RefreshFileSigns() abort
  if exists('t:gtd_pr') && exists('b:gtd_pr_path')
    call s:PlaceSigns(bufnr('%'), b:gtd_pr_path)
  endif
endfunction

" ---------------------------------------------------------------------------
" comment display (:FGitPrOpenComment)
" ---------------------------------------------------------------------------

function! git_tree_diff#pr#open_comment() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  if exists('b:gtd_pr_clist')
    return git_tree_diff#pr#comments_select()
  endif
  if !exists('b:gtd_pr_path')
    return s:Error('not in a pull request file window')
  endif
  let l:lnum = line('.')
  for l:i in range(len(t:gtd_pr.comments))
    let l:c = t:gtd_pr.comments[l:i]
    if l:c.kind ==# 'review' && l:c.path ==# b:gtd_pr_path
          \ && l:c.line == l:lnum
      let l:origin = win_getid()
      call s:ShowComment(l:i)
      call win_gotoid(l:origin)
      return
    endif
  endfor
  echomsg 'git-tree-diff: no PR comment on this line'
endfunction

function! s:EnsureCommentWin() abort
  if !win_id2win(t:gtd_pr.comment_win)
    let l:cur = win_getid()
    botright vertical new
    let t:gtd_pr.comment_win = win_getid()
    execute 'vertical resize '
          \ . get(g:, 'git_tree_diff_pr_comment_width', 50)
    setlocal winfixwidth
    call win_gotoid(l:cur)
  endif
endfunction

" Show the comment thread containing t:gtd_pr.comments[a:idx] in the comment
" window (created at the far right on first use).
function! s:ShowComment(idx) abort
  let l:c = t:gtd_pr.comments[a:idx]
  " review replies all point at the thread root
  let l:root_id = l:c.reply_to != 0 ? l:c.reply_to : l:c.id
  let l:thread = filter(copy(t:gtd_pr.comments),
        \ 'v:val.id == ' . l:root_id . ' || v:val.reply_to == ' . l:root_id)
  let t:gtd_pr.current = {'kind': l:c.kind, 'id': l:root_id}

  let l:where = l:c.kind ==# 'issue' ? 'conversation'
        \ : l:c.path . (l:c.line > 0 ? ':' . l:c.line : '')
  let l:lines = ['# PR #' . t:gtd_pr.number . ' · ' . l:where]
  for l:m in l:thread
    call extend(l:lines, ['', '## @' . l:m.user . ' · ' . l:m.time, ''])
    call extend(l:lines, split(l:m.body, '\r\?\n', 1))
  endfor

  call s:EnsureCommentWin()
  let l:cur = win_getid()
  call win_gotoid(t:gtd_pr.comment_win)
  silent enew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal wrap linebreak nonumber norelativenumber nolist
  setlocal winfixwidth nofoldenable
  call setline(1, l:lines)
  execute 'silent! file ' . fnameescape('gtd-pr://comment/' . l:root_id)
  setlocal filetype=markdown
  setlocal nomodifiable
  nnoremap <buffer> <silent> q :close<CR>
  nnoremap <buffer> <silent> r :FGitPrReply<CR>
  call win_gotoid(l:cur)
endfunction

" ---------------------------------------------------------------------------
" comment list (:FGitPrCommentsOpen / Close / Toggle)
" ---------------------------------------------------------------------------

function! git_tree_diff#pr#comments_open() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  if win_id2win(t:gtd_pr.list_win)
    call win_gotoid(t:gtd_pr.list_win)
    return
  endif
  botright new
  let t:gtd_pr.list_win = win_getid()
  execute 'resize ' . get(g:, 'git_tree_diff_pr_comments_height', 12)
  call s:SetupCommentsBuffer()
endfunction

function! git_tree_diff#pr#comments_close() abort
  if exists('t:gtd_pr') && win_id2win(t:gtd_pr.list_win)
    call win_execute(t:gtd_pr.list_win, 'close')
  endif
endfunction

function! git_tree_diff#pr#comments_toggle() abort
  if exists('t:gtd_pr') && win_id2win(t:gtd_pr.list_win)
    call git_tree_diff#pr#comments_close()
  else
    call git_tree_diff#pr#comments_open()
  endif
endfunction

function! s:SetupCommentsBuffer() abort
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber nowrap nolist nospell
  setlocal cursorline signcolumn=no winfixheight

  let l:lines = []
  let l:map = []
  for l:i in range(len(t:gtd_pr.comments))
    let l:c = t:gtd_pr.comments[l:i]
    let l:where = l:c.kind ==# 'issue' ? 'conversation'
          \ : l:c.path . (l:c.line > 0 ? ':' . l:c.line : '')
    call add(l:lines, (l:c.reply_to != 0 ? '↳ ' : '') . '@' . l:c.user
          \ . ' · ' . l:c.time . ' · ' . l:where)
    call add(l:lines, '    ' . s:Preview(l:c.body))
    call extend(l:map, [l:i, l:i])
  endfor
  if empty(l:lines)
    let l:lines = ['(no comments on this pull request)']
    let l:map = [-1]
  endif
  let b:gtd_pr_clist = l:map
  call setline(1, l:lines)
  setlocal nomodifiable
  silent! file gtd-pr://comments
  setlocal filetype=gittreediffprcomments

  nnoremap <buffer> <silent> <CR> :call git_tree_diff#pr#comments_select()<CR>
  nnoremap <buffer> <silent> o :call git_tree_diff#pr#comments_select()<CR>
  nnoremap <buffer> <silent> <2-LeftMouse> :call git_tree_diff#pr#comments_select()<CR>
  nnoremap <buffer> <silent> <C-n> :call search('^[@↳]', 'W')<CR>
  nnoremap <buffer> <silent> <C-p> :call search('^[@↳]', 'bW')<CR>
  nnoremap <buffer> <silent> q :close<CR>
endfunction

function! s:Preview(body) abort
  for l:line in split(a:body, '\r\?\n')
    if l:line !~# '^\s*$'
      return strpart(l:line, 0, 120)
    endif
  endfor
  return ''
endfunction

function! git_tree_diff#pr#comments_select() abort
  let l:idx = get(get(b:, 'gtd_pr_clist', []), line('.') - 1, -1)
  if l:idx < 0 || !exists('t:gtd_pr')
    return
  endif
  call git_tree_diff#mark_selected(line('.'))
  let l:origin = win_getid()
  call s:ShowComment(l:idx)
  call s:JumpToCode(t:gtd_pr.comments[l:idx])
  call win_gotoid(l:origin)
endfunction

" Move the file window to the code location of comment a:c: switch it to the
" commented file if necessary, put the cursor on the commented line and open
" any folds concealing it.
function! s:JumpToCode(c) abort
  if a:c.kind !=# 'review' || empty(a:c.path) || a:c.line <= 0
    return
  endif
  call s:EnsureFileWin()
  if getbufvar(winbufnr(t:gtd_pr.file_win), 'gtd_pr_path', '') !=# a:c.path
    let l:cur = win_getid()
    call s:OpenFile(a:c.path)
    call win_gotoid(l:cur)
    call s:MarkTreeFile(a:c.path)
  endif
  call win_execute(t:gtd_pr.file_win, [
        \ printf('call cursor(min([%d, line(''$'')]), 1)', a:c.line),
        \ 'silent! normal! zv',
        \ 'normal! zz'])
endfunction

" Select the given file in the tree window (cursor, highlight and folds).
function! s:MarkTreeFile(path) abort
  if !win_id2win(t:gtd_pr.tree_win)
    return
  endif
  let l:map = getbufvar(winbufnr(t:gtd_pr.tree_win), 'gtd_map', [])
  for l:i in range(len(l:map))
    if !empty(l:map[l:i]) && !l:map[l:i].isdir && l:map[l:i].path ==# a:path
      call win_execute(t:gtd_pr.tree_win, [
            \ 'call cursor(' . (l:i + 1) . ', 1)',
            \ 'silent! normal! zv',
            \ 'call git_tree_diff#mark_selected(' . (l:i + 1) . ')'])
      return
    endif
  endfor
endfunction

" ---------------------------------------------------------------------------
" branch checkout (:FGitPrCheckoutBranch)
" ---------------------------------------------------------------------------

function! git_tree_diff#pr#checkout() abort
  if exists('t:gtd_pr')
    let l:root = t:gtd_pr.root
    let l:number = t:gtd_pr.number
  elseif exists('b:gtd_pr_prs')
    let l:pr = get(b:gtd_pr_prs, line('.') - 1, {})
    if empty(l:pr)
      return
    endif
    let l:root = b:gtd_pr_root
    let l:number = l:pr.number
  else
    return s:Error('no pull request selected (use :FGitPrList)')
  endif

  let [l:err, l:out] = s:Gh(l:root, 'pr checkout ' . l:number . ' 2>&1')
  if l:err
    return s:Error('checkout of PR #' . l:number . ' failed: '
          \ . join(l:out, ' '))
  endif
  echomsg 'git-tree-diff: checked out the branch of PR #' . l:number

  " reload the shown file so the working tree copy is edited from now on
  if exists('t:gtd_pr') && win_id2win(t:gtd_pr.file_win)
    let l:path = getbufvar(winbufnr(t:gtd_pr.file_win), 'gtd_pr_path', '')
    if !empty(l:path)
      let l:cur = win_getid()
      call s:OpenFile(l:path)
      call win_gotoid(l:cur)
    endif
  endif
endfunction

" ---------------------------------------------------------------------------
" composing comments (:FGitPrReply / :FGitPrNewComment)
" ---------------------------------------------------------------------------

function! git_tree_diff#pr#reply() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  let l:target = {}
  if exists('b:gtd_pr_clist')
    let l:idx = get(b:gtd_pr_clist, line('.') - 1, -1)
    if l:idx >= 0
      let l:c = t:gtd_pr.comments[l:idx]
      let l:target = {'kind': l:c.kind,
            \ 'id': l:c.reply_to != 0 ? l:c.reply_to : l:c.id}
    endif
  elseif !empty(t:gtd_pr.current)
    let l:target = t:gtd_pr.current
  endif
  if empty(l:target)
    return s:Error('no comment selected (open a comment first)')
  endif
  call s:Compose('reply', l:target)
endfunction

function! git_tree_diff#pr#new_comment() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  call s:Compose('new', {})
endfunction

function! s:Compose(type, target) abort
  let l:state = {'type': a:type, 'target': a:target,
        \ 'root': t:gtd_pr.root, 'nwo': t:gtd_pr.nwo,
        \ 'number': t:gtd_pr.number}
  if a:type ==# 'reply' && win_id2win(t:gtd_pr.comment_win)
    call win_gotoid(t:gtd_pr.comment_win)
    rightbelow new
  else
    botright vertical new
    execute 'vertical resize '
          \ . get(g:, 'git_tree_diff_pr_comment_width', 50)
  endif
  setlocal buftype=acwrite bufhidden=wipe noswapfile nobuflisted
  setlocal wrap linebreak nonumber norelativenumber
  let b:gtd_pr_compose = l:state
  call setline(1, ['<!-- '
        \ . (a:type ==# 'reply' ? 'Reply to comment on' : 'New comment on')
        \ . ' PR #' . l:state.number
        \ . ' — write the comment below, :w sends it -->', ''])
  execute 'silent! file ' . fnameescape('gtd-pr://' . a:type . '/'
        \ . l:state.number . '/' . bufnr('%'))
  setlocal filetype=markdown
  autocmd BufWriteCmd <buffer> call s:Submit()
  call cursor(2, 1)
endfunction

function! s:Submit() abort
  let l:state = b:gtd_pr_compose
  let l:lines = filter(getline(1, '$'), 'v:val !~# ''^<!--.*-->$''')
  while !empty(l:lines) && l:lines[0] =~# '^\s*$'
    call remove(l:lines, 0)
  endwhile
  while !empty(l:lines) && l:lines[-1] =~# '^\s*$'
    call remove(l:lines, -1)
  endwhile
  if empty(l:lines)
    return s:Error('comment is empty, nothing sent')
  endif

  if l:state.type ==# 'reply' && l:state.target.kind ==# 'review'
    let l:url = 'repos/' . l:state.nwo . '/pulls/' . l:state.number
          \ . '/comments/' . l:state.target.id . '/replies'
  else
    " replies to conversation comments and new comments are issue comments
    let l:url = 'repos/' . l:state.nwo . '/issues/' . l:state.number
          \ . '/comments'
  endif
  let [l:err, l:out] = s:GhPost(l:state.root,
        \ 'api -X POST --input - ' . shellescape(l:url),
        \ json_encode({'body': join(l:lines, "\n")}))
  if l:err
    return s:Error('posting comment failed: ' . l:out)
  endif
  setlocal nomodified
  echomsg 'git-tree-diff: comment posted'
  let l:win = win_getid()
  call s:RefreshComments()
  call win_gotoid(l:win)
  silent! close
endfunction

" Re-fetch the comments and update the gutter signs and the comment list.
function! s:RefreshComments() abort
  if !exists('t:gtd_pr')
    return
  endif
  let t:gtd_pr.comments = s:FetchComments(t:gtd_pr.root, t:gtd_pr.nwo,
        \ t:gtd_pr.number)
  if win_id2win(t:gtd_pr.file_win)
    let l:buf = winbufnr(t:gtd_pr.file_win)
    let l:path = getbufvar(l:buf, 'gtd_pr_path', '')
    if !empty(l:path)
      call s:PlaceSigns(l:buf, l:path)
    endif
  endif
  if win_id2win(t:gtd_pr.list_win)
    let l:cur = win_getid()
    call win_gotoid(t:gtd_pr.list_win)
    silent enew
    call s:SetupCommentsBuffer()
    call win_gotoid(l:cur)
  endif
endfunction
