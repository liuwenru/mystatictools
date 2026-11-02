_mini_scp_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" candidate key rest host prefix= value token
    COMPREPLY=()
    case "$previous" in
        -P|-l|-J|-c) return ;;
        -o)
            COMPREPLY=( $(compgen -W 'BatchMode= Compression= ConnectTimeout= IdentityFile= IdentitiesOnly= ProxyJump= ProxyCommand= Port= StrictHostKeyChecking= UserKnownHostsFile=' -- "$current") ); return ;;
        -i|-F|-S)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
    esac
    if [[ "$current" == -* ]]; then
        COMPREPLY=( $(compgen -W '-3 -4 -6 -A -B -C -D -F -i -J -l -O -o -P -p -q -r -R -S -s -T -v' -- "$current") ); return
    fi
    # Never open an SSH connection to complete remote paths.
    token="${COMP_LINE:0:COMP_POINT}"
    token="${token##*[[:space:]]}"
    [[ "$token" != *:* ]] || return
    [[ "$current" != *:* ]] || return
    value="$current"
    if [[ "$current" == *@* ]]; then prefix="${current%@*}@"; value="${current##*@}"; fi
    for candidate in "$HOME/.ssh/config" /etc/ssh/ssh_config; do
        [ -r "$candidate" ] || continue
        while read -r key rest; do
            case "$key" in
                [Hh][Oo][Ss][Tt])
                    for host in $rest; do
                        case "$host" in *[\*\?\!]*|\#*) continue ;; esac
                        [[ "$host" == "$value"* ]] && COMPREPLY+=("$prefix$host:")
                    done ;;
            esac
        done < "$candidate"
    done
    if [ -z "$prefix" ]; then
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
}
complete -o nospace -F _mini_scp_completion scp
