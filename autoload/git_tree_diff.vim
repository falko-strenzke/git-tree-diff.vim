" git_tree_diff.vim - implementation of :FGitTreeDiff
" The command opens a new tab with a file tree of all files that have a
" non-empty diff on the far left, and two equally sized diff windows on the
" right showing the two compared versions of the selected file.

" Sentinel for "the file in the working tree" (as opposed to a git revision).
let s:WORKTREE = ''

" ---------------------------------------------------------------------------
" git helpers
" ---------------------------------------------------------------------------

function! s:Git(root, args) abort
  let l:cmd = 'git -c core.quotepath=false -C ' . shellescape(a:root) . ' ' . a:args
  let l:out = systemlist(l:cmd)
  return [v:shell_error, l:out]
endfunction

function! s:FindRoot() abort
  let l:dir = expand('%:p:h')
  if empty(l:dir) || !isdirectory(l:dir)
    let l:dir = getcwd()
  endif
  let [l:err, l:out] = s:Git(l:dir, 'rev-parse --show-toplevel')
  return (l:err || empty(l:out)) ? '' : l:out[0]
endfunction

function! s:IsRev(root, word) abort
  let [l:err, l:_] = s:Git(a:root,
        \ 'rev-parse --verify --quiet ' . shellescape(a:word . '^{commit}'))
  return !l:err
endfunction

" Determine which two versions of each file are being compared, mirroring the
" revision semantics of 'git diff'.  Returns a dict with refs and display
" labels for both sides.  A ref is either something 'git show <ref>:<path>'
" understands (':0' for the index) or s:WORKTREE for the working tree file.
function! s:ParseArgs(root, argstr) abort
  let l:cached = 0
  let l:revs = []
  let l:labels = []
  for l:word in split(a:argstr)
    if l:word ==# '--'
      break
    elseif l:word ==# '--cached' || l:word ==# '--staged'
      let l:cached = 1
    elseif l:word =~# '^-'
      " other options only influence which files show a diff
      continue
    elseif l:word =~# '\.\.\.'
      let l:parts = split(l:word, '\.\.\.', 1)
      let l:a = empty(l:parts[0]) ? 'HEAD' : l:parts[0]
      let l:b = empty(l:parts[1]) ? 'HEAD' : l:parts[1]
      let [l:err, l:out] = s:Git(a:root,
            \ 'merge-base ' . shellescape(l:a) . ' ' . shellescape(l:b))
      if !l:err && !empty(l:out)
        call extend(l:revs, [l:out[0], l:b])
        call extend(l:labels, [strpart(l:out[0], 0, 10), l:b])
      endif
    elseif l:word =~# '\.\.'
      let l:parts = split(l:word, '\.\.', 1)
      call add(l:revs, empty(l:parts[0]) ? 'HEAD' : l:parts[0])
      call add(l:revs, empty(l:parts[1]) ? 'HEAD' : l:parts[1])
      call extend(l:labels, l:revs[-2 :])
    elseif s:IsRev(a:root, l:word)
      call add(l:revs, l:word)
      call add(l:labels, l:word)
    endif
  endfor

  if len(l:revs) >= 2
    return {'left': l:revs[0], 'left_label': l:labels[0],
          \ 'right': l:revs[1], 'right_label': l:labels[1]}
  elseif len(l:revs) == 1
    if l:cached
      return {'left': l:revs[0], 'left_label': l:labels[0],
            \ 'right': ':0', 'right_label': 'index'}
    endif
    return {'left': l:revs[0], 'left_label': l:labels[0],
          \ 'right': s:WORKTREE, 'right_label': 'worktree'}
  elseif l:cached
    return {'left': 'HEAD', 'left_label': 'HEAD',
          \ 'right': ':0', 'right_label': 'index'}
  endif
  return {'left': ':0', 'left_label': 'index',
        \ 'right': s:WORKTREE, 'right_label': 'worktree'}
endfunction

" ---------------------------------------------------------------------------
" entry point
" ---------------------------------------------------------------------------

function! git_tree_diff#run(args) abort
  let l:root = s:FindRoot()
  if empty(l:root)
    echohl ErrorMsg | echomsg 'git-tree-diff: not inside a git repository' | echohl None
    return
  endif

  let [l:err, l:files] = s:Git(l:root, 'diff --name-only ' . a:args)
  if l:err
    echohl ErrorMsg
    echomsg 'git-tree-diff: git diff failed: ' . join(l:files, ' ')
    echohl None
    return
  endif
  call filter(l:files, '!empty(v:val)')
  if empty(l:files)
    echomsg 'git-tree-diff: no differences'
    return
  endif

  let l:spec = s:ParseArgs(l:root, a:args)

  tabnew
  let t:gtd = {
        \ 'root': l:root,
        \ 'left_ref': l:spec.left,
        \ 'left_label': l:spec.left_label,
        \ 'right_ref': l:spec.right,
        \ 'right_label': l:spec.right_label,
        \ }

  " the window created by :tabnew becomes the left diff window
  let t:gtd.left_win = win_getid()
  rightbelow vertical new
  let t:gtd.right_win = win_getid()

  " tree window on the far left
  execute 'topleft vertical ' . get(g:, 'git_tree_diff_width', 34) . 'new'
  let t:gtd.tree_win = win_getid()
  call s:SetupTreeBuffer(l:files)
  wincmd =

  " automatically show the diff of the first file
  for l:i in range(len(b:gtd_map))
    if !empty(b:gtd_map[l:i]) && !b:gtd_map[l:i].isdir
      call cursor(l:i + 1, 1)
      call git_tree_diff#select()
      break
    endif
  endfor
endfunction

" ---------------------------------------------------------------------------
" tree buffer
" ---------------------------------------------------------------------------

function! s:BuildTree(files) abort
  let l:tree = {}
  for l:file in a:files
    let l:parts = split(l:file, '/')
    let l:node = l:tree
    for l:i in range(len(l:parts))
      if l:i == len(l:parts) - 1
        let l:node[l:parts[l:i]] = ''
      else
        if !has_key(l:node, l:parts[l:i]) || type(l:node[l:parts[l:i]]) != v:t_dict
          let l:node[l:parts[l:i]] = {}
        endif
        let l:node = l:node[l:parts[l:i]]
      endif
    endfor
  endfor
  return l:tree
endfunction

function! s:RenderTree(node, depth, prefix, lines, map) abort
  let l:dirs = []
  let l:files = []
  for l:key in keys(a:node)
    call add(type(a:node[l:key]) == v:t_dict ? l:dirs : l:files, l:key)
  endfor
  call sort(l:dirs)
  call sort(l:files)
  let l:indent = repeat('  ', a:depth)
  for l:dir in l:dirs
    call add(a:lines, l:indent . l:dir . '/')
    call add(a:map, {'isdir': 1, 'path': a:prefix . l:dir})
    call s:RenderTree(a:node[l:dir], a:depth + 1, a:prefix . l:dir . '/',
          \ a:lines, a:map)
  endfor
  for l:file in l:files
    call add(a:lines, l:indent . l:file)
    call add(a:map, {'isdir': 0, 'path': a:prefix . l:file})
  endfor
endfunction

function! s:SetupTreeBuffer(files) abort
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber nowrap nolist
  setlocal winfixwidth cursorline signcolumn=no
  setlocal shiftwidth=2 foldlevel=99
  setlocal foldmethod=expr foldexpr=git_tree_diff#foldexpr(v:lnum)
  setlocal foldtext=git_tree_diff#foldtext()
  silent! execute 'setlocal fillchars+=fold:\ '

  let l:lines = [fnamemodify(t:gtd.root, ':t'),
        \ t:gtd.left_label . ' → ' . t:gtd.right_label, '']
  let l:map = [{}, {}, {}]
  call s:RenderTree(s:BuildTree(a:files), 0, '', l:lines, l:map)
  let b:gtd_map = l:map
  call setline(1, l:lines)
  setlocal nomodifiable

  setlocal filetype=gittreediff

  nnoremap <buffer> <silent> <CR> :call git_tree_diff#select()<CR>
  nnoremap <buffer> <silent> o :call git_tree_diff#select()<CR>
  nnoremap <buffer> <silent> <2-LeftMouse> :call git_tree_diff#select()<CR>
  nnoremap <buffer> <silent> q :tabclose<CR>
endfunction

function! git_tree_diff#foldexpr(lnum) abort
  let l:level = indent(a:lnum) / 2
  if a:lnum < line('$') && indent(a:lnum + 1) / 2 > l:level
    return '>' . (l:level + 1)
  endif
  return l:level
endfunction

function! git_tree_diff#foldtext() abort
  let l:line = getline(v:foldstart)
  let l:count = v:foldend - v:foldstart
  return substitute(l:line, '^\(\s*\)', '\1▸ ', '') . ' (' . l:count . ')'
endfunction

" ---------------------------------------------------------------------------
" selection and diff windows
" ---------------------------------------------------------------------------

function! git_tree_diff#select() abort
  let l:entry = get(b:gtd_map, line('.') - 1, {})
  if empty(l:entry)
    return
  endif
  if l:entry.isdir
    if foldclosed('.') != -1
      normal! zo
    else
      silent! normal! zc
    endif
  else
    call s:MarkSelected()
    call s:OpenDiff(l:entry.path)
  endif
endfunction

function! s:MarkSelected() abort
  if exists('w:gtd_match')
    silent! call matchdelete(w:gtd_match)
  endif
  let w:gtd_match = matchaddpos('GitTreeDiffSelected', [line('.')])
endfunction

" Recreate the two diff windows in case the user closed one of them.
function! s:EnsureWindows() abort
  if !win_id2win(t:gtd.left_win)
    if win_id2win(t:gtd.right_win)
      call win_gotoid(t:gtd.right_win)
      leftabove vertical new
    else
      call win_gotoid(t:gtd.tree_win)
      botright vertical new
    endif
    let t:gtd.left_win = win_getid()
  endif
  if !win_id2win(t:gtd.right_win)
    call win_gotoid(t:gtd.left_win)
    rightbelow vertical new
    let t:gtd.right_win = win_getid()
  endif
endfunction

function! s:OpenDiff(path) abort
  if !exists('t:gtd')
    return
  endif
  let l:origin = win_getid()
  call s:EnsureWindows()

  call win_gotoid(t:gtd.left_win)
  diffoff
  call s:LoadVersion(t:gtd.left_ref, t:gtd.left_label, a:path)
  diffthis

  call win_gotoid(t:gtd.right_win)
  diffoff
  call s:LoadVersion(t:gtd.right_ref, t:gtd.right_label, a:path)
  diffthis

  call win_gotoid(l:origin)
endfunction

function! s:LoadVersion(ref, label, path) abort
  if a:ref ==# s:WORKTREE
    try
      execute 'silent edit ' . fnameescape(t:gtd.root . '/' . a:path)
    catch /E37\|E162/
      echohl WarningMsg
      echomsg 'git-tree-diff: buffer has unsaved changes; save it first'
      echohl None
    endtry
    return
  endif

  try
    silent enew
  catch /E37\|E162/
    echohl WarningMsg
    echomsg 'git-tree-diff: buffer has unsaved changes; save it first'
    echohl None
    return
  endtry
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  let [l:err, l:out] = s:Git(t:gtd.root,
        \ 'show ' . shellescape(a:ref . ':' . a:path))
  if l:err
    " file does not exist on this side (added or deleted)
    let l:out = []
  endif
  call setline(1, l:out)
  execute 'silent! file ' . fnameescape('gtd://' . a:label . '/' . a:path)
  filetype detect
  setlocal nomodifiable
endfunction
