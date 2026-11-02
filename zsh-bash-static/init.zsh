# 可在 ~/.zshrc 中 source 本文件；路径相对于本文件，不要求固定安装位置。
fpath=("${${(%):-%x}:A:h}/share/zsh/functions" $fpath)
autoload -Uz compinit
compinit
