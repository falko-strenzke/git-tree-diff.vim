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
  call s:PrListWindow(l:root, l:prs)
endfunction

" Open the pull request of the currently checked out branch
" (:FGitPrOfCurrentBranch).  With several matching pull requests (e.g.
" against different base branches) a filtered pull request list is shown.
function! git_tree_diff#pr#of_current_branch() abort
  let l:root = git_tree_diff#find_root()
  if empty(l:root)
    return s:Error('not inside a git repository')
  endif
  let [l:err, l:branch] = git_tree_diff#git(l:root, 'branch --show-current')
  if l:err || empty(l:branch) || empty(l:branch[0])
    return s:Error('no branch checked out')
  endif
  let [l:err, l:prs] = s:GhJson(l:root, 'pr list --head '
        \ . shellescape(l:branch[0]) . ' --limit 200'
        \ . ' --json number,title,author,headRefName,updatedAt')
  if l:err
    return s:Error('gh pr list failed: ' . l:prs)
  endif
  if empty(l:prs)
    echomsg 'git-tree-diff: no open pull request for branch ' . l:branch[0]
    return
  endif
  if len(l:prs) == 1
    call s:OpenPr(l:root, l:prs[0].number)
  else
    call s:PrListWindow(l:root, l:prs)
  endif
endfunction

function! s:PrListWindow(root, prs) abort
  botright new
  execute 'resize ' . min([len(a:prs) + 1, 15])
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber nowrap nolist nospell
  setlocal cursorline signcolumn=no winfixheight
  let b:gtd_pr_root = a:root
  let b:gtd_pr_prs = a:prs
  call setline(1, map(copy(a:prs), 's:FormatPrLine(v:val)'))
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
        \ 'comments_time': localtime(),
        \ 'head_files': {},
        \ 'current': {},
        \ 'tree_win': win_getid(),
        \ 'file_win': 0, 'comment_win': 0, 'list_win': 0,
        \ }
  call s:RelocateComments()
  call s:SetupPrTreeBuffer()
  call s:PlaceTreeSigns()

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
" the line numbers (in the new version) classified as pure additions
" ('add'), changed lines ('chg', a removal paired with an addition) and
" positions where lines were deleted ('del').
function! s:ParseDiff(lines) abort
  let l:files = []
  let l:changes = {}
  let l:path = ''
  let l:minus = ''
  let l:new = 0
  let l:old_rem = 0
  let l:new_rem = 0
  " current run of consecutive -/+ lines: start line (new version) and the
  " number of removed and added lines; git emits all '-' before all '+'
  let l:bs = 0
  let l:bm = 0
  let l:bp = 0
  for l:line in a:lines
    if l:old_rem > 0 || l:new_rem > 0
      let l:ch = strpart(l:line, 0, 1)
      if l:ch ==# '+'
        if l:bm == 0 && l:bp == 0
          let l:bs = l:new
        endif
        let l:bp += 1
        let l:new += 1
        let l:new_rem -= 1
      elseif l:ch ==# '-'
        if l:bp > 0
          call s:FlushBlock(l:changes[l:path], l:bs, l:bm, l:bp)
          let l:bm = 0
          let l:bp = 0
        endif
        if l:bm == 0
          let l:bs = l:new
        endif
        let l:bm += 1
        let l:old_rem -= 1
      elseif l:ch ==# '\'
        " '\ No newline at end of file'
      else
        if l:bm || l:bp
          call s:FlushBlock(l:changes[l:path], l:bs, l:bm, l:bp)
          let l:bm = 0
          let l:bp = 0
        endif
        let l:new += 1
        let l:old_rem -= 1
        let l:new_rem -= 1
      endif
      continue
    endif
    if (l:bm || l:bp) && !empty(l:path)
      call s:FlushBlock(l:changes[l:path], l:bs, l:bm, l:bp)
      let l:bm = 0
      let l:bp = 0
    endif
    if l:line =~# '^diff --git '
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
        " one-letter file status: added files have no '--- a/' side
        let l:changes[l:path] =
              \ {'add': [], 'chg': [], 'del': [], 'deleted': l:deleted,
              \ 'status': l:deleted ? 'D' : empty(l:minus) ? 'A' : 'M'}
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
  if (l:bm || l:bp) && !empty(l:path)
    call s:FlushBlock(l:changes[l:path], l:bs, l:bm, l:bp)
  endif
  return [l:files, l:changes]
endfunction

" Classify one run of a:bm removed and a:bp added lines starting at line
" a:bs (new version): pairs are changed lines, surplus additions are new
" lines, surplus removals leave a deletion marker after the run.
function! s:FlushBlock(info, bs, bm, bp) abort
  let l:paired = min([a:bm, a:bp])
  for l:i in range(l:paired)
    call add(a:info.chg, a:bs + l:i)
  endfor
  for l:i in range(l:paired, a:bp - 1)
    call add(a:info.add, a:bs + l:i)
  endfor
  if a:bm > a:bp
    let l:lnum = max([a:bs + a:bp, 1])
    if empty(a:info.del) || a:info.del[-1] != l:lnum
      call add(a:info.del, l:lnum)
    endif
  endif
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
      let l:start = s:Num(l:c, 'start_line')
      let l:path = get(l:c, 'path', '')
      let l:url = get(l:c, 'html_url', '')
      let l:hunk = get(l:c, 'diff_hunk', '')
      call add(l:comments, {
            \ 'kind': l:kind,
            \ 'id': l:c.id,
            \ 'path': type(l:path) == v:t_string ? l:path : '',
            \ 'line': l:line > 0 ? l:line : s:Num(l:c, 'original_line'),
            \ 'start_line': l:start > 0 ? l:start
            \   : s:Num(l:c, 'original_start_line'),
            \ 'outdated': l:kind ==# 'review' && l:line <= 0,
            \ 'hunk_line': type(l:hunk) == v:t_string && !empty(l:hunk)
            \   ? split(l:hunk, "\n")[-1][1:] : '',
            \ 'moved_from': 0,
            \ 'reply_to': s:Num(l:c, 'in_reply_to_id'),
            \ 'user': get(get(l:c, 'user', {}), 'login', '?'),
            \ 'time': s:FmtTime(get(l:c, 'created_at', '')),
            \ 'body': get(l:c, 'body', ''),
            \ 'url': type(l:url) == v:t_string ? l:url : '',
            \ })
    endfor
  endfor
  " attach the resolution state and thread id of the review thread to each
  " review comment
  let l:threads = s:FetchThreads(a:root, a:nwo, a:number)
  for l:c in l:comments
    if l:c.kind ==# 'review'
      let l:root_id = l:c.reply_to != 0 ? l:c.reply_to : l:c.id
      let l:info = get(l:threads, l:root_id, {})
      let l:c.resolved = get(l:info, 'resolved', 0)
      let l:c.thread_id = get(l:info, 'thread_id', '')
    endif
  endfor
  " conversation comments first, then review comments grouped by file/line
  call sort(l:comments, function('s:CompareComments'))
  return l:comments
endfunction

" A review comment on an outdated diff carries only its original line number,
" which may no longer fit the pull request head version of the file.  If the
" originally commented line's text (the last line of the comment's diff hunk)
" occurs exactly once in the head version, move the comment there; the
" comment window points out the relocation.
function! s:RelocateComments() abort
  for l:c in t:gtd_pr.comments
    if l:c.kind !=# 'review' || !l:c.outdated || empty(l:c.path)
          \ || l:c.hunk_line !~# '\S'
          \ || get(get(t:gtd_pr.changes, l:c.path, {}), 'deleted', 0)
      continue
    endif
    " the head version is immutable while the tab is open: cache the contents
    if !has_key(t:gtd_pr.head_files, l:c.path)
      let t:gtd_pr.head_files[l:c.path] =
            \ s:FileContent(t:gtd_pr.head, l:c.path)
    endif
    let l:content = t:gtd_pr.head_files[l:c.path]
    let l:new = 0
    for l:i in range(len(l:content))
      if l:content[l:i] ==# l:c.hunk_line
        if l:new > 0
          let l:new = 0
          break
        endif
        let l:new = l:i + 1
      endif
    endfor
    if l:new > 0 && l:new != l:c.line
      let l:c.moved_from = l:c.line
      if l:c.start_line > 0
        let l:c.start_line += l:new - l:c.line
      endif
      let l:c.line = l:new
    endif
  endfor
  call sort(t:gtd_pr.comments, function('s:CompareComments'))
endfunction

" Thread resolution is only available via the GraphQL API.  Returns a map of
" thread root comment id -> {'resolved': 0/1, 'thread_id': node id}; empty
" on failure, in which case all threads count as unresolved.
function! s:FetchThreads(root, nwo, number) abort
  let l:parts = split(a:nwo, '/')
  if len(l:parts) != 2
    return {}
  endif
  let l:q = 'query { repository(owner: "' . l:parts[0] . '", name: "'
        \ . l:parts[1] . '") { pullRequest(number: ' . a:number . ') {'
        \ . ' reviewThreads(first: 100) { nodes {'
        \ . ' id isResolved comments(first: 1) { nodes { databaseId }'
        \ . ' } } } } } }'
  let [l:err, l:data] = s:GhJson(a:root,
        \ 'api graphql -f query=' . shellescape(l:q))
  if l:err
    return {}
  endif
  let l:res = {}
  let l:pr = get(get(get(l:data, 'data', {}), 'repository', {}),
        \ 'pullRequest', {})
  for l:thread in get(get(l:pr, 'reviewThreads', {}), 'nodes', [])
    let l:nodes = get(get(l:thread, 'comments', {}), 'nodes', [])
    if !empty(l:nodes)
      let l:res[l:nodes[0].databaseId] = {
            \ 'resolved': get(l:thread, 'isResolved', 0) ? 1 : 0,
            \ 'thread_id': get(l:thread, 'id', ''),
            \ }
    endif
  endfor
  return l:res
endfunction

" Resolve or unresolve a review conversation (:FGitPrResolve and
" :FGitPrUnresolve): the thread on the current line in a code window, or the
" selected comment's thread elsewhere.
function! git_tree_diff#pr#resolve() abort
  call s:SetResolved(1)
endfunction

function! git_tree_diff#pr#unresolve() abort
  call s:SetResolved(0)
endfunction

function! s:SetResolved(resolve) abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  let l:verb = a:resolve ? 'resolved' : 'unresolved'
  let l:c = {}
  if exists('b:gtd_pr_path')
    " code window: the first thread on this line that is not yet in the
    " requested state
    let l:other_seen = 0
    for l:cand in t:gtd_pr.comments
      if l:cand.kind ==# 'review' && l:cand.path ==# b:gtd_pr_path
            \ && l:cand.line == line('.')
        if get(l:cand, 'resolved', 0) != a:resolve
          let l:c = l:cand
          break
        endif
        let l:other_seen = 1
      endif
    endfor
    if empty(l:c)
      if l:other_seen
        echomsg 'git-tree-diff: the conversation on this line is already '
              \ . l:verb
        return
      endif
      return s:Error('no PR comment on this line')
    endif
  else
    let l:c = s:SelectedComment()
    if empty(l:c)
      return s:Error('no comment selected (open a comment first)')
    endif
  endif
  if l:c.kind !=# 'review'
    return s:Error('only review conversations can be ' . l:verb)
  endif
  if get(l:c, 'resolved', 0) == a:resolve
    echomsg 'git-tree-diff: the conversation is already ' . l:verb
    return
  endif
  if empty(get(l:c, 'thread_id', ''))
    return s:Error('no thread id known for this conversation')
  endif

  let l:q = 'mutation { ' . (a:resolve ? 'resolve' : 'unresolve')
        \ . 'ReviewThread(input: {threadId: "' . l:c.thread_id
        \ . '"}) { thread { isResolved } } }'
  let [l:err, l:out] = s:GhJson(t:gtd_pr.root,
        \ 'api graphql -f query=' . shellescape(l:q))
  if l:err
    return s:Error('updating the conversation failed: ' . l:out)
  endif
  echomsg 'git-tree-diff: conversation ' . l:verb
  call s:RefreshComments()
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
  setlocal winfixwidth cursorline signcolumn=auto
  setlocal shiftwidth=2 foldlevel=99
  setlocal foldmethod=expr foldexpr=git_tree_diff#foldexpr(v:lnum)
  setlocal foldtext=git_tree_diff#foldtext()
  silent! execute 'setlocal fillchars+=fold:\ '

  " same status icons and colors as in the :FGitTreeDiff tree
  let l:status = {}
  for l:f in t:gtd_pr.files
    let l:status[l:f] = get(get(t:gtd_pr.changes, l:f, {}), 'status', '')
  endfor
  let [l:lines, l:map] = git_tree_diff#tree_lines(t:gtd_pr.files,
        \ ['PR #' . t:gtd_pr.number, t:gtd_pr.title, ''], l:status)
  let b:gtd_map = l:map
  call setline(1, l:lines)
  setlocal nomodifiable

  setlocal filetype=gittreediff

  nnoremap <buffer> <silent> <CR> :call git_tree_diff#pr#tree_select()<CR>
  nnoremap <buffer> <silent> o :call git_tree_diff#pr#tree_select()<CR>
  nnoremap <buffer> <silent> <2-LeftMouse> :call git_tree_diff#pr#tree_select()<CR>
  nnoremap <buffer> <silent> q :tabclose<CR>
endfunction

" Reopen the file tree window in the left side bar (:FGitPrFileTreeOpen),
" e.g. after it was closed manually.  If it is already visible it is only
" focused.
function! git_tree_diff#pr#file_tree_open() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  if win_id2win(t:gtd_pr.tree_win)
    call win_gotoid(t:gtd_pr.tree_win)
    return
  endif
  topleft vertical new
  let t:gtd_pr.tree_win = win_getid()
  execute 'vertical resize ' . get(g:, 'git_tree_diff_width', 34)
  call s:SetupPrTreeBuffer()
  call s:PlaceTreeSigns()
  " select the file currently shown in the file window
  let l:path = win_id2win(t:gtd_pr.file_win)
        \ ? getbufvar(winbufnr(t:gtd_pr.file_win), 'gtd_pr_path', '') : ''
  if !empty(l:path)
    call s:MarkTreeFile(l:path)
  endif
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
    call s:FreshComments()
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
  " a comment-line highlight would not fit the newly shown file
  if exists('w:gtd_pr_line_match')
    silent! call matchdelete(w:gtd_pr_line_match)
    unlet w:gtd_pr_line_match
    unlet! w:gtd_pr_line_path
  endif
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
    for l:lnum in get(l:info, 'add', []) + get(l:info, 'chg', [])
      if l:lnum <= l:max
        call sign_place(0, 'gtdpr', 'GitTreeDiffPrAdd', a:buf,
              \ {'lnum': l:lnum, 'priority': 10})
      endif
    endfor
  endif
  " one comment sign per line; lines where every thread is resolved get the
  " dimmed variant
  let l:clines = {}
  for l:c in t:gtd_pr.comments
    if l:c.kind ==# 'review' && l:c.path ==# a:path
          \ && l:c.line > 0 && l:c.line <= l:max
      let l:clines[l:c.line] = get(l:clines, l:c.line, 0)
            \ || !get(l:c, 'resolved', 0)
    endif
  endfor
  for [l:lnum, l:unresolved] in items(l:clines)
    call sign_place(0, 'gtdpr',
          \ l:unresolved ? 'GitTreeDiffPrComment' : 'GitTreeDiffPrCommentDone',
          \ a:buf, {'lnum': str2nr(l:lnum), 'priority': l:unresolved ? 20 : 12})
  endfor
  " for a checked-out working tree file, mark local modifications relative
  " to the pull request head: green for added, blue for changed lines and
  " orange where lines were deleted
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
      for [l:sign, l:lnums] in [
            \ ['GitTreeDiffPrLocalAdd', get(l:linfo, 'add', [])],
            \ ['GitTreeDiffPrLocalChg', get(l:linfo, 'chg', [])]]
        for l:lnum in l:lnums
          if l:lnum <= l:max
            call sign_place(0, 'gtdpr', l:sign, a:buf,
                  \ {'lnum': l:lnum, 'priority': 15})
          endif
        endfor
      endfor
    endif
  endif
endfunction

" Mark files with at least one unresolved review comment with a "C" sign in
" the tree window.
function! s:PlaceTreeSigns() abort
  if !exists('*sign_place') || !win_id2win(t:gtd_pr.tree_win)
    return
  endif
  let l:buf = winbufnr(t:gtd_pr.tree_win)
  call sign_unplace('gtdpr', {'buffer': l:buf})
  let l:paths = {}
  for l:c in t:gtd_pr.comments
    if l:c.kind ==# 'review' && !empty(l:c.path) && !get(l:c, 'resolved', 0)
      let l:paths[l:c.path] = 1
    endif
  endfor
  let l:map = getbufvar(l:buf, 'gtd_map', [])
  for l:i in range(len(l:map))
    if !empty(l:map[l:i]) && !l:map[l:i].isdir
          \ && has_key(l:paths, l:map[l:i].path)
      call sign_place(0, 'gtdpr', 'GitTreeDiffPrComment', l:buf,
            \ {'lnum': l:i + 1, 'priority': 10})
    endif
  endfor
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
  call s:FreshComments()
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
  let l:title = '# PR #' . t:gtd_pr.number . ' · ' . l:where
  if l:c.kind ==# 'review'
    let l:title .= ' · ' . (get(l:c, 'resolved', 0) ? 'resolved' : 'unresolved')
  endif
  let l:lines = [l:title]
  let l:sugg = [{}]
  " an outdated comment sits at a line number from an old diff; it may have
  " been relocated to the matching line by s:RelocateComments()
  if get(l:c, 'moved_from', 0) > 0
    call add(l:lines, '_outdated comment: relocated from original line '
          \ . l:c.moved_from . ' by its line content_')
    call add(l:sugg, {})
  elseif l:c.kind ==# 'review' && get(l:c, 'outdated', 0) && l:c.line > 0
    call add(l:lines, '_outdated comment: line ' . l:c.line
          \ . ' refers to an old version of the file_')
    call add(l:sugg, {})
  endif
  for l:m in l:thread
    call extend(l:lines, ['', '## @' . l:m.user . ' · ' . l:m.time, ''])
    call extend(l:sugg, [{}, {}, {}])
    let l:body = split(l:m.body, '\r\?\n', 1)
    call extend(l:lines, l:body)
    call extend(l:sugg, s:SuggestionMap(l:m, l:body))
  endfor

  " note when further conversations exist on the same line
  if l:c.kind ==# 'review' && l:c.line > 0
    let l:others = len(filter(copy(t:gtd_pr.comments),
          \ 'v:val.kind ==# "review" && v:val.reply_to == 0'
          \ . ' && v:val.id != ' . l:root_id
          \ . ' && v:val.path ==# ' . string(l:c.path)
          \ . ' && v:val.line == ' . l:c.line))
    if l:others > 0
      call extend(l:lines, ['',
            \ '_' . l:others . ' more conversation'
            \ . (l:others == 1 ? '' : 's')
            \ . ' on this line, see :FGitPrCommentsOpen_'])
      call extend(l:sugg, [{}, {}])
    endif
  endif

  call s:FillCommentWin(l:lines, 'gtd-pr://comment/' . l:root_id, [], l:sugg)
  call s:HighlightCommentLine(l:c)
endfunction

" Map each body line of comment a:c to the suggested change
" ("```suggestion" fenced block) it belongs to, or {} for other lines.  A
" suggestion replaces the commented line range start_line..line (both are
" line numbers of the pull request head version).
function! s:SuggestionMap(c, body) abort
  let l:map = repeat([{}], len(a:body))
  if a:c.kind !=# 'review' || a:c.line <= 0
    return l:map
  endif
  let l:i = 0
  while l:i < len(a:body)
    if a:body[l:i] =~# '^\s*```suggestion\s*$'
      let l:j = l:i + 1
      let l:text = []
      while l:j < len(a:body) && a:body[l:j] !~# '^\s*```\s*$'
        call add(l:text, a:body[l:j])
        let l:j += 1
      endwhile
      if l:j < len(a:body)
        let l:s = {'path': a:c.path,
              \ 'start': get(a:c, 'start_line', 0) > 0
              \   ? a:c.start_line : a:c.line,
              \ 'end': a:c.line, 'text': l:text}
        for l:k in range(l:i, l:j)
          let l:map[l:k] = l:s
        endfor
        let l:i = l:j
      endif
    endif
    let l:i += 1
  endwhile
  return l:map
endfunction

" While a comment is shown, highlight the commented line in the code window
" if that window currently shows the commented file.
function! s:HighlightCommentLine(c) abort
  call git_tree_diff#pr#clear_line_match()
  if !win_id2win(t:gtd_pr.file_win)
    return
  endif
  let l:buf = winbufnr(t:gtd_pr.file_win)
  let l:max = get(get(getbufinfo(l:buf), 0, {}), 'linecount', 0)
  if a:c.kind ==# 'review' && !empty(a:c.path)
        \ && a:c.line > 0 && a:c.line <= l:max
        \ && getbufvar(l:buf, 'gtd_pr_path', '') ==# a:c.path
    call win_execute(t:gtd_pr.file_win, [
          \ 'let w:gtd_pr_line_match = '
          \ . 'matchaddpos("GitTreeDiffPrCommentLine", [' . a:c.line . '])',
          \ 'let w:gtd_pr_line_path = ' . string(a:c.path)])
  endif
endfunction

" Remove the commented-line highlight from the file window (e.g. when the
" comment window is closed).
function! git_tree_diff#pr#clear_line_match() abort
  if !exists('t:gtd_pr') || !win_id2win(t:gtd_pr.file_win)
    return
  endif
  call win_execute(t:gtd_pr.file_win, [
        \ 'if exists("w:gtd_pr_line_match")',
        \ '  silent! call matchdelete(w:gtd_pr_line_match)',
        \ '  unlet w:gtd_pr_line_match',
        \ '  unlet! w:gtd_pr_line_path',
        \ 'endif'])
endfunction

" The highlight is a window-local match: it survives buffer switches done
" outside the plugin (:e, :b, gf, tag jumps, ...) and would then underline
" an unrelated file.  Drop it as soon as the window shows a different file
" than the one it was created for.
function! git_tree_diff#pr#check_line_match() abort
  if exists('w:gtd_pr_line_match')
        \ && get(b:, 'gtd_pr_path', '') !=# get(w:, 'gtd_pr_line_path', '')
    silent! call matchdelete(w:gtd_pr_line_match)
    unlet w:gtd_pr_line_match
    unlet! w:gtd_pr_line_path
  endif
endfunction

augroup gtdpr_line_match
  autocmd!
  autocmd BufEnter * call git_tree_diff#pr#check_line_match()
augroup END

" Show a:lines in the comment window.  a:conv, when non-empty, is a per-line
" list mapping each buffer line to the comment it belongs to (used by the
" conversation view to resolve "the comment under the cursor").  a:sugg is
" the per-line suggested-change map built by s:SuggestionMap().
function! s:FillCommentWin(lines, name, conv, sugg) abort
  call s:EnsureCommentWin()
  let l:cur = win_getid()
  call win_gotoid(t:gtd_pr.comment_win)
  silent enew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal wrap linebreak nonumber norelativenumber nolist
  setlocal winfixwidth nofoldenable
  call setline(1, a:lines)
  if !empty(a:conv)
    let b:gtd_pr_conv = a:conv
  endif
  let b:gtd_pr_sugg = a:sugg
  execute 'silent! file ' . fnameescape(a:name)
  setlocal filetype=markdown
  setlocal nomodifiable
  nnoremap <buffer> <silent> q :close<CR>
  nnoremap <buffer> <silent> r :FGitPrReply<CR>
  nnoremap <buffer> <silent> a :FGitPrApplySuggestion<CR>
  " no comment shown means no commented-line highlight
  autocmd BufWinLeave <buffer> call git_tree_diff#pr#clear_line_match()
  call win_gotoid(l:cur)
endfunction

" Show all comments of the pull request in chronological order in the
" comment window (:FGitPrOpenConversation).
function! git_tree_diff#pr#open_conversation() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  call s:FreshComments()
  call s:RenderConversation()
  call win_gotoid(t:gtd_pr.comment_win)
endfunction

function! s:RenderConversation() abort
  let l:conv = sort(copy(t:gtd_pr.comments), function('s:CompareTime'))
  let l:lines = ['# PR #' . t:gtd_pr.number . ' · conversation']
  let l:map = [{}]
  let l:sugg = [{}]
  for l:c in l:conv
    let l:where = l:c.kind ==# 'review' && !empty(l:c.path)
          \ ? ' · ' . l:c.path . (l:c.line > 0 ? ':' . l:c.line : '') : ''
    let l:head = ['', '## @' . l:c.user . ' · ' . l:c.time . l:where, '']
    let l:body = split(l:c.body, '\r\?\n', 1)
    call extend(l:lines, l:head + l:body)
    call extend(l:map, repeat([l:c], len(l:head) + len(l:body)))
    call extend(l:sugg, repeat([{}], len(l:head)) + s:SuggestionMap(l:c, l:body))
  endfor
  call s:FillCommentWin(l:lines, 'gtd-pr://conversation', l:map, l:sugg)
endfunction

function! s:CompareTime(a, b) abort
  if a:a.time !=# a:b.time
    return a:a.time <# a:b.time ? -1 : 1
  endif
  return a:a.id == a:b.id ? 0 : a:a.id < a:b.id ? -1 : 1
endfunction

" Apply the suggested change under the cursor in the comment or conversation
" window to the checked-out working tree copy (:FGitPrApplySuggestion, "a").
" The buffer is modified but not saved.
function! git_tree_diff#pr#apply_suggestion() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  if !exists('b:gtd_pr_sugg')
    return s:Error('not in a comment window (open a comment first)')
  endif
  let l:s = get(b:gtd_pr_sugg, line('.') - 1, {})
  if empty(l:s)
    return s:Error('the cursor is not on a suggested change')
  endif
  " suggestions can only be applied to the real, editable file
  if !s:PrCheckedOut() || !filereadable(t:gtd_pr.root . '/' . l:s.path)
    return s:Error('the pull request branch is not checked out'
          \ . ' (use :FGitPrCheckoutBranch)')
  endif
  let l:origin = win_getid()
  call s:OpenFile(l:s.path)
  call s:MarkTreeFile(l:s.path)
  call win_gotoid(l:origin)
  let l:buf = winbufnr(t:gtd_pr.file_win)
  if getbufvar(l:buf, 'gtd_pr_path', '') !=# l:s.path
    return s:Error('could not open ' . l:s.path . ' in the file window')
  endif
  if l:s.end > get(get(getbufinfo(l:buf), 0, {}), 'linecount', 0)
    return s:Error('the suggested range ' . l:s.start . '-' . l:s.end
          \ . ' does not exist in the local file')
  endif
  call deletebufline(l:buf, l:s.start, l:s.end)
  if !empty(l:s.text)
    call appendbufline(l:buf, l:s.start - 1, l:s.text)
  endif
  call win_execute(t:gtd_pr.file_win, [
        \ printf('call cursor(min([%d, line(''$'')]), 1)', l:s.start),
        \ 'silent! normal! zv',
        \ 'normal! zz'])
  echomsg printf('git-tree-diff: applied the suggestion to %s:%d (not saved)',
        \ l:s.path, l:s.start)
endfunction

" ---------------------------------------------------------------------------
" automatic comment opening (:FGitPrCommentAutoOpenOn / Off)
" ---------------------------------------------------------------------------

" The setting is per pull request (tab) and applies to all code windows of
" that pull request.
function! git_tree_diff#pr#auto_open(on) abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  let t:gtd_pr.auto_open = a:on
  let t:gtd_pr.auto_open_last = ['', 0]
  if a:on
    augroup gtdpr_auto_open
      autocmd!
      autocmd CursorMoved * call git_tree_diff#pr#auto_open_check()
    augroup END
    call git_tree_diff#pr#auto_open_check()
  endif
  echomsg 'git-tree-diff: automatic comment opening '
        \ . (a:on ? 'enabled' : 'disabled')
endfunction

function! git_tree_diff#pr#auto_open_check() abort
  if !exists('t:gtd_pr') || !get(t:gtd_pr, 'auto_open', 0)
        \ || !exists('b:gtd_pr_path')
    return
  endif
  " only react when the cursor moved to a different line
  if get(t:gtd_pr, 'auto_open_last', ['', 0]) ==# [b:gtd_pr_path, line('.')]
    return
  endif
  let t:gtd_pr.auto_open_last = [b:gtd_pr_path, line('.')]
  call s:FreshComments()
  " resolved conversations open too; an unresolved one on the same line wins
  let l:found = -1
  for l:i in range(len(t:gtd_pr.comments))
    let l:c = t:gtd_pr.comments[l:i]
    if l:c.kind ==# 'review' && l:c.path ==# b:gtd_pr_path
          \ && l:c.line == line('.')
      if !get(l:c, 'resolved', 0)
        let l:found = l:i
        break
      elseif l:found < 0
        let l:found = l:i
      endif
    endif
  endfor
  if l:found >= 0
    let l:origin = win_getid()
    call s:ShowComment(l:found)
    call win_gotoid(l:origin)
  endif
endfunction

" ---------------------------------------------------------------------------
" comment list (:FGitPrCommentsOpen / Close / Toggle)
" ---------------------------------------------------------------------------

function! git_tree_diff#pr#comments_open() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  call s:FreshComments()
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
  " re-apply after a possible file switch in the code window
  call s:HighlightCommentLine(t:gtd_pr.comments[l:idx])
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

" The comment the user currently refers to: the comment under the cursor in
" the comment list or in the conversation view, or the (root of the) comment
" shown in the comment window.
function! s:SelectedComment() abort
  if !exists('t:gtd_pr')
    return {}
  endif
  if exists('b:gtd_pr_conv')
    return get(b:gtd_pr_conv, line('.') - 1, {})
  endif
  if exists('b:gtd_pr_clist')
    let l:idx = get(b:gtd_pr_clist, line('.') - 1, -1)
    return l:idx >= 0 ? t:gtd_pr.comments[l:idx] : {}
  endif
  if !empty(t:gtd_pr.current)
    for l:c in t:gtd_pr.comments
      if l:c.kind ==# t:gtd_pr.current.kind && l:c.id == t:gtd_pr.current.id
        return l:c
      endif
    endfor
  endif
  return {}
endfunction

function! git_tree_diff#pr#reply() abort
  if !exists('t:gtd_pr')
    return s:Error('no pull request open in this tab (use :FGitPrList)')
  endif
  let l:c = s:SelectedComment()
  if empty(l:c)
    return s:Error('no comment selected (open a comment first)')
  endif
  " GitHub has no replies to conversation comments (not attached to a line)
  if l:c.kind !=# 'review'
    return s:Error('conversation comments cannot be replied to on GitHub;'
          \ . ' use :FGitPrNewComment instead')
  endif
  call s:Compose('reply', {'kind': l:c.kind,
        \ 'id': l:c.reply_to != 0 ? l:c.reply_to : l:c.id})
endfunction

" ---------------------------------------------------------------------------
" comment links (:FGitPrBrowseComment / :FGitPrCommentCopyLink)
" ---------------------------------------------------------------------------

function! s:SelectedCommentUrl() abort
  let l:c = s:SelectedComment()
  if empty(l:c)
    call s:Error('no comment selected (open a comment first)')
    return ''
  endif
  if empty(get(l:c, 'url', ''))
    call s:Error('the selected comment has no link')
    return ''
  endif
  return l:c.url
endfunction

function! git_tree_diff#pr#browse_comment() abort
  let l:url = s:SelectedCommentUrl()
  if empty(l:url)
    return
  endif
  let l:browser = get(g:, 'git_tree_diff_browser', '')
  if empty(l:browser)
    if has('mac') || has('macunix')
      let l:browser = 'open'
    elseif has('win32') || has('win64')
      let l:browser = 'start ""'
    else
      let l:browser = 'xdg-open'
    endif
  endif
  call system(l:browser . ' ' . shellescape(l:url) . ' &')
  echomsg 'git-tree-diff: opened ' . l:url
endfunction

function! git_tree_diff#pr#copy_link() abort
  let l:url = s:SelectedCommentUrl()
  if empty(l:url)
    return
  endif
  if has('clipboard')
    call setreg('+', l:url)
    call setreg('*', l:url)
  endif
  call setreg('"', l:url)
  echomsg 'git-tree-diff: copied ' . l:url
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

  if l:state.type ==# 'reply'
    " replies exist for review comments only, see git_tree_diff#pr#reply()
    let l:url = 'repos/' . l:state.nwo . '/pulls/' . l:state.number
          \ . '/comments/' . l:state.target.id . '/replies'
  else
    " new comments are posted to the issue conversation
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
  let t:gtd_pr.comments_time = localtime()
  call s:RelocateComments()
  call s:PlaceTreeSigns()
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
    let l:lnum = line('.')
    silent enew
    call s:SetupCommentsBuffer()
    call cursor(min([l:lnum, line('$')]), 1)
    call win_gotoid(l:cur)
  endif
  call s:RefreshCommentWin()
endfunction

" The comment data is cached for one minute after the last load; any later
" comment access re-fetches it from GitHub.
function! s:FreshComments() abort
  if localtime() - get(t:gtd_pr, 'comments_time', 0) >= 60
    call s:RefreshComments()
  endif
endfunction

" Re-render the comment window so that new replies and a changed resolution
" state become visible immediately.
function! s:RefreshCommentWin() abort
  if !win_id2win(t:gtd_pr.comment_win)
    return
  endif
  let l:name = bufname(winbufnr(t:gtd_pr.comment_win))
  call win_execute(t:gtd_pr.comment_win, 'let s:keep_lnum = line(".")')
  if l:name =~# 'gtd-pr://conversation$'
    call s:RenderConversation()
  elseif l:name =~# 'gtd-pr://comment/' && !empty(t:gtd_pr.current)
    let l:shown = -1
    for l:i in range(len(t:gtd_pr.comments))
      let l:c = t:gtd_pr.comments[l:i]
      if l:c.kind ==# t:gtd_pr.current.kind && l:c.id == t:gtd_pr.current.id
        let l:shown = l:i
        break
      endif
    endfor
    if l:shown < 0
      return
    endif
    call s:ShowComment(l:shown)
  else
    return
  endif
  call win_execute(t:gtd_pr.comment_win,
        \ 'call cursor(min([' . s:keep_lnum . ', line("$")]), 1)')
endfunction
