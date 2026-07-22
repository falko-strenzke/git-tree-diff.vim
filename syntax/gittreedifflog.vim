" Syntax highlighting for the git-tree-diff log buffer (:FGitLog)
if exists('b:current_syntax')
  finish
endif

syntax match GitTreeDiffLogCommit +\<commit \x\{40}\>.*$+ contains=GitTreeDiffLogSha,GitTreeDiffLogDecoration
syntax match GitTreeDiffLogSha +\x\{40}+ contained
syntax match GitTreeDiffLogDecoration +(.*)$+ contained
syntax match GitTreeDiffLogAuthor +\<Author: .*$+
syntax match GitTreeDiffLogDate +\<Date: .*$+
syntax match GitTreeDiffLogMerge +\<Merge: .*$+

highlight default link GitTreeDiffLogCommit Statement
highlight default link GitTreeDiffLogSha Identifier
highlight default link GitTreeDiffLogDecoration Special
highlight default link GitTreeDiffLogAuthor Type
highlight default link GitTreeDiffLogDate Comment
highlight default link GitTreeDiffLogMerge Comment

let b:current_syntax = 'gittreedifflog'
