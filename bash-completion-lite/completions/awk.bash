_mini_awk_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" candidate
    COMPREPLY=()
    case "$previous" in -F|--field-separator|-v|--assign|-e|--source) return ;; esac
    if [[ "$current" == -* ]] && [[ "$previous" != -f && "$previous" != --file ]]; then
        COMPREPLY=( $(compgen -W '-F -v -f -W' -- "$current") )
    else
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
}
complete -o default -F _mini_awk_completion awk
