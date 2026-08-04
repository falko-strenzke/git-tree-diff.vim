# git-tree-diff.vim

Browse a `git diff` as a file tree with side-by-side diff windows.

`:FGitTreeDiff` opens a new tab page with:

- a browsable, foldable file tree on the far left, showing only the files
  that have a non-empty diff — each with an icon and text color for its
  status: green `✚` added, blue `●` modified, red `✖` deleted,
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

## Pull requests

Requires the [gh](https://cli.github.com/) command line tool (installed and
authenticated).

`:FGitPrList` lists the open GitHub pull requests of the repository;
`:FGitPrOfCurrentBranch` directly opens the pull request belonging to the
currently checked-out branch (or a filtered list if there are several).
Opening one (`<CR>`) creates a new tab with a foldable tree of the changed
files on the left — like GitHub's "Files changed" view, with a `C` gutter
mark on files that have unresolved review comments — and a file window on
the right. Opening a file from the tree shows the pull request version
of the file with gutter signs: `┃` for added/changed lines, `▁` where lines
were deleted, and `C` on lines that have review comments (dimmed when all
threads on the line are resolved). If the pull
request is checked out (HEAD is the PR head commit, or the current branch
is the PR branch — possibly with additional local commits on top), the
real file is edited — even with local unstaged or uncommitted changes — so
it can be modified and saved; local modifications relative to the PR head
version get their own gutter marks — green `┃` for added, blue `┃` for
changed lines, orange `▁` for deletions — recomputed on every save.
`:FGitPrCheckoutBranch` checks the branch out for you.

| Command                 | Action                                            |
|-------------------------|---------------------------------------------------|
| `:FGitPrList`           | List open pull requests                           |
| `:FGitPrOfCurrentBranch`| Open the PR of the checked-out branch             |
| `:FGitPrFileTreeOpen`   | Reopen the PR file tree side bar                  |
| `:FGitPrOpenComment`    | Open the comment on the current line (`<leader>fc`) |
| `:FGitPrCommentsOpen`   | List all PR comments (also `Close` and `Toggle`)  |
| `:FGitPrReply`          | Reply to the selected comment                     |
| `:FGitPrNewComment`     | Add a new comment to the PR conversation          |
| `:FGitPrCheckoutBranch` | Check out the branch of the selected PR           |
| `:FGitPrOpenConversation` | Show the full conversation in the comment window |
| `:FGitPrApplySuggestion`| Apply the suggested change under the cursor (`a`)  |
| `:FGitPrBrowseComment`  | Open the selected comment on GitHub               |
| `:FGitPrCommentCopyLink`| Copy the selected comment's GitHub link           |
| `:FGitPrResolve`        | Resolve the selected review conversation          |
| `:FGitPrUnresolve`      | Unresolve the selected review conversation        |
| `:FGitPrCommentAutoOpenOn` / `...Off` | Auto-open the conversation under the cursor |

Comments are displayed as markdown in a window at the far right (`q`
closes it, `r` starts a reply, `a` applies the GitHub suggested change
under the cursor to the checked-out file — leaving the buffer unsaved for
review); for review comments the first line states
whether the conversation is resolved, and the commented code line is
highlighted while the comment is shown (style configurable via
`g:git_tree_diff_pr_highlight_style`). If further conversations exist on
the same line, a note at the bottom of the comment window says so. The comment list shows every comment with
an author/time header and a preview line; `<CR>` opens the comment,
`<C-n>`/`<C-p>` jump between comments. Opening a review comment from the
list also jumps the file window to the commented line — switching the file
and opening folds as needed. Replies and new comments are
written in a markdown buffer and sent to GitHub with `:w`; after posting —
and after resolving/unresolving — the gutter signs, the comment list and an
open comment or conversation window update immediately.

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

## Tests

`test/run.sh` runs the headless test suite for the pull request features.
It needs `vim` and `git`; all GitHub access is served by a local `gh` stub,
so no network access or authentication is required. All mutable state goes
to a temporary directory — the repository stays clean.

## Configuration

| Variable                             | Default | Description                            |
|--------------------------------------|---------|----------------------------------------|
| `g:git_tree_diff_width`              | `34`    | Width of the tree window               |
| `g:git_tree_diff_log_width`          | `50`    | Width of the log window (`:FGitLog`)   |
| `g:git_tree_diff_pr_comment_width`   | `50`    | Width of the PR comment window         |
| `g:git_tree_diff_pr_comments_height` | `12`    | Height of the PR comment list window   |
| `g:git_tree_diff_gh_cmd`             | `"gh"`  | The `gh` executable for GitHub access  |
| `g:git_tree_diff_browser`            | `""`    | Browser command (`""` = OS default)    |
| `g:git_tree_diff_pr_highlight_style` | `"underline"` | Commented-line highlight: `underline`, `italic`, `background` |

See `:help git-tree-diff` for details.
