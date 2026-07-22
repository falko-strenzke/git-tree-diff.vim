# git-tree-diff.vim

Browse a `git diff` as a file tree with side-by-side diff windows.

`:FGitTreeDiff` opens a new tab page with:

- a browsable, foldable file tree on the far left, showing only the files
  that have a non-empty diff,
- two equally sized windows on the right showing the two compared versions
  of the selected file in Vim's usual diff view.

All command arguments are handed through to the underlying `git diff`
invocation.

```vim
:FGitTreeDiff                    " working tree vs. index
:FGitTreeDiff --cached           " index vs. HEAD
:FGitTreeDiff HEAD~3             " working tree vs. HEAD~3
:FGitTreeDiff main..feature      " two revisions
:FGitTreeDiff main...feature     " merge base of main vs. feature
:FGitTreeDiff HEAD -- src/       " limit to a path
```

`:FGitLog` opens a new tab page with a browsable commit log based on
`git log --graph --decorate` (with the optional argument `all`, `--all` is
appended). Pressing `<CR>` on a commit shows — right of the log window and
created on first use — the file tree of that commit's changes and the two
diff windows, exactly as for `:FGitTreeDiff`. The commit is compared against
its first parent (a root commit against the empty tree); selecting another
commit reuses the same windows.

```vim
:FGitLog                         " log of the current branch
:FGitLog all                     " git log --graph --decorate --all
```

## Tree window mappings

| Key             | Action                                             |
|-----------------|----------------------------------------------------|
| `<CR>` / `o`    | Open diff for file / toggle fold for directory     |
| `<2-LeftMouse>` | Same as `<CR>`                                     |
| `q`             | Close the tab page                                 |

## Log window mappings

| Key             | Action                                             |
|-----------------|----------------------------------------------------|
| `<CR>` / `o`    | Show tree and diffs for the commit under the cursor|
| `<2-LeftMouse>` | Same as `<CR>`                                     |
| `<C-n>` / `<C-p>` | Jump to next / previous commit                   |
| `q`             | Close the tab page                                 |

Versions taken from a git revision or the index are shown in read-only
scratch buffers. When one side is the working tree, the actual file is
edited, so you can modify and save it directly from the diff view.

## Installation

With Vim's native package support:

```sh
git clone https://github.com/fstrenzke/git-tree-diff.vim \
    ~/.vim/pack/plugins/start/git-tree-diff.vim
```

Or with any plugin manager, e.g. vim-plug:

```vim
Plug 'fstrenzke/git-tree-diff.vim'
```

## Configuration

| Variable                    | Default | Description                          |
|-----------------------------|---------|--------------------------------------|
| `g:git_tree_diff_width`     | `34`    | Width of the tree window             |
| `g:git_tree_diff_log_width` | `50`    | Width of the log window (`:FGitLog`) |

See `:help git-tree-diff` for details.
