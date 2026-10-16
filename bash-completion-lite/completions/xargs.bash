_mini_xargs_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" candidate word command= expect= i
    COMPREPLY=()
    # Find the command while skipping arguments belonging to xargs options.
    for ((i=1; i<COMP_CWORD; i++)); do
        word="${COMP_WORDS[i]}"
        if [ -n "$expect" ]; then expect=; continue; fi
        case "$word" in
            -a|--arg-file|-d|--delimiter|-E|-I|-L|--max-lines|-n|--max-args|-P|--max-procs|-s|--max-chars|--process-slot-var) expect=yes ;;
            --) if (( i+1 < COMP_CWORD )); then command="${COMP_WORDS[i+1]}"; else command=next; fi; break ;;
            -*) ;;
            *) command="$word"; break ;;
        esac
    done
    if [ -n "$command" ] && [ "$command" != next ]; then
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    elif [ -n "$expect" ]; then
        if [ "$previous" = -a ] || [ "$previous" = --arg-file ]; then
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
            compopt -o filenames 2>/dev/null || true
        fi
    elif [[ "$current" == -* ]] && [ "$command" != next ]; then
        COMPREPLY=( $(compgen -W '-0 --null -a --arg-file -d --delimiter -E -I -L --max-lines -n --max-args -P --max-procs -s --max-chars -p --interactive -r --no-run-if-empty -t --verbose -x --exit --show-limits --process-slot-var --help --version' -- "$current") )
    else
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -c -- "$current")
    fi
}
complete -F _mini_xargs_completion xargs
