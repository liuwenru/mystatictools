_mini_rg_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words candidate
    COMPREPLY=()
    case "$previous" in
        --color) words='always auto never ansi' ;;
        --engine) words='default pcre2 auto' ;;
        -t|--type|-T|--type-not) words="$(rg --type-list 2>/dev/null | cut -d: -f1)" ;;
        -e|--regexp|-g|--glob|--iglob|-r|--replace|-m|--max-count|-A|--after-context|-B|--before-context|-C|--context|-j|--threads|--max-depth|--max-filesize|--encoding|--sort|--sortr|--type-add|--type-clear) return ;;
        -f|--file|--ignore-file) ;;
        *) case "$current" in
            -*) words='-e -f -i -s -S -v -w -x -F -P -U -z -a -n -N -H -I -l -L -c -o -q -r -g -t -T -A -B -C -m -j --hidden --no-ignore --no-ignore-vcs --follow --files --type-list --type-add --type-clear --glob --iglob --ignore-file --max-depth --max-filesize --color --engine --encoding --sort --sortr --stats --json --trim --heading --no-heading --line-buffered --help --version' ;;
        esac ;;
    esac
    if [ -n "$words" ]; then COMPREPLY=( $(compgen -W "$words" -- "$current") ); else
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
}
complete -o bashdefault -o default -F _mini_rg_completion rg
