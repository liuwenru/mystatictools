# zsh-completion-lite: source this file from ~/.zshrc. Do not execute it.
# Paths are relative to this file, so the directory can live anywhere.

[[ -o interactive ]] || return 0

typeset -g _mini_zc_root=${${(%):-%x}:A:h}

() {
    emulate -L zsh
    local dir=$_mini_zc_root/functions file name line
    local -a commands_list compinit_file official

    [[ -d $dir ]] || return 0

    # compsys (compinit/compdef) comes with zsh's function library. If no
    # framework started it yet, start it here, before this directory is added
    # to fpath: zsh's own functions stay registered for the commands listed
    # in MINI_ZSH_OFFICIAL_COMPLETION.
    if (( ! $+functions[compdef] )); then
        compinit_file=(${^fpath}/compinit(N))
        if (( ! $#compinit_file )); then
            print -u2 "zsh-completion-lite: compinit not found in fpath; zsh function library missing"
            return 1
        fi
        autoload -Uz compinit
        compinit
    fi
    fpath=($dir ${fpath:#$dir})

    # Commands listed here keep zsh's own completion, e.g. "git docker".
    official=(${=MINI_ZSH_OFFICIAL_COMPLETION-})

    # Register every _* file explicitly so these rules win even when compinit
    # ran earlier (frameworks, cached .zcompdump) with zsh's own functions.
    for file in $dir/_*(N-.); do
        name=${file:t}
        autoload -Uz $name
        IFS= read -r line < $file || continue
        [[ $line == '#compdef '* ]] || continue
        commands_list=(${${=line}[2,-1]})
        commands_list=(${commands_list:|official})
        (( $#commands_list )) && compdef $name $commands_list
    done
}
