_mini_grep_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" candidate words prefix= i
    COMPREPLY=()
    case "$current" in
        --*=*) previous="${current%%=*}"; prefix="$previous="; current="${current#*=}" ;;
        '=') current= ;;
        *) if [ "$previous" = '=' ] && (( COMP_CWORD >= 2 )); then previous="${COMP_WORDS[COMP_CWORD-2]}"; fi ;;
    esac
    case "$previous" in
        --color|--colour) words='always auto never' ;;
        -d|--directories) words='read recurse skip' ;;
        -D|--devices) words='read skip' ;;
        -e|--regexp|-m|--max-count|-A|--after-context|-B|--before-context|-C|--context|--include|--exclude|--exclude-dir|--label) return ;;
        -f|--file|--exclude-from) ;;
        *) case "$current" in
            -*) words='-E -F -G -P -e -f -i -v -w -x -z -c -l -L -n -H -h -o -q -s -r -R -a -I -b -m -A -B -C --recursive --dereference-recursive --help --version --color= --colour= --include --exclude --exclude-dir --exclude-from --binary-files --line-buffered --null --directories --devices' ;;
        esac ;;
    esac
    if [ "$previous" = --binary-files ]; then words='binary text without-match'; fi
    if [ -n "$words" ]; then COMPREPLY=( $(compgen -W "$words" -- "$current") ); else
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
    if [ -n "$prefix" ]; then
        for ((i=0; i<${#COMPREPLY[@]}; i++)); do COMPREPLY[i]="$prefix${COMPREPLY[i]}"; done
    fi
    case "${COMPREPLY[*]}" in *=) compopt -o nospace 2>/dev/null || true ;; esac
}
complete -o bashdefault -o default -F _mini_grep_completion grep
