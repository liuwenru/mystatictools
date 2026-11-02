_mini_sed_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" candidate
    COMPREPLY=()
    case "$previous" in -e|--expression) return ;; esac
    if [[ "$current" == -* ]] && [[ "$previous" != -f && "$previous" != --file ]]; then
        COMPREPLY=( $(compgen -W '-n --quiet --silent -e --expression -f --file -i --in-place -E -r --regexp-extended -s --separate -u --unbuffered -z --null-data --follow-symlinks --posix --sandbox --debug --help --version' -- "$current") )
    else
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
}
complete -o default -F _mini_sed_completion sed
