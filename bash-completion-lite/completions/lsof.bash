_mini_lsof_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words candidate token trim= prefix= value mode=
    COMPREPLY=()
    token="${COMP_LINE:0:COMP_POINT}"
    token="${token##*[[:space:]]}"
    case "$token" in
        -i?*) mode=i; prefix=-i; value="${token#-i}" ;;
        -s?*) mode=s; prefix=-s; value="${token#-s}" ;;
        *)
            if [ "$previous" = -i ] || [ "$previous" = -s ]; then
                mode="${previous#-}"; value="$token"
            elif [[ "$token" == *:* ]]; then
                # ':' splits COMP_WORDS even inside -s TCP:LISTEN.
                case " ${COMP_WORDS[*]} " in
                    *' -s '*) mode=s; value="$token" ;;
                    *' -i '*) mode=i; value="$token" ;;
                esac
            fi ;;
    esac
    if [ -n "$mode" ]; then
        case "$mode" in
            i) words='4 6 TCP UDP TCP:22 TCP:80 TCP:443' ;;
            s) words='TCP:LISTEN TCP:ESTABLISHED TCP:CLOSE_WAIT TCP:TIME_WAIT UDP:Idle' ;;
        esac
        if [[ "$COMP_WORDBREAKS" == *:* && "$token" == *:* ]]; then trim="${token%:*}:"; fi
        for candidate in $words; do
            [[ "$candidate" == "$value"* ]] || continue
            candidate="$prefix$candidate"
            COMPREPLY+=("${candidate#"$trim"}")
        done
        return
    fi
    case "$previous" in
        -p) words="$(ps -e -o pid= 2>/dev/null)" ;;
        -u) words="$(compgen -u)" ;;
        -i) words='4 6 TCP UDP TCP:22 TCP:80 TCP:443' ;;
        -s) words='TCP:LISTEN TCP:ESTABLISHED TCP:CLOSE_WAIT TCP:TIME_WAIT UDP:Idle' ;;
        -d) words='cwd rtd txt mem DEL 0 1 2' ;;
        -F) words='p c u L f a l t D s o n T' ;;
        -c|-g|-r|+r) return ;;
        +D|+d)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -d -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
        *) case "$current" in
            -*|+*) words='-a -b -c -d -D -F -g -h -i -l -n -N -o -O -p -P -r -R -s -t -T -u -U -v -V -w -X +d +D +L1 +r' ;;
        esac ;;
    esac
    if [ -n "$words" ]; then COMPREPLY=( $(compgen -W "$words" -- "$current") ); else
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
}
complete -o default -F _mini_lsof_completion lsof
