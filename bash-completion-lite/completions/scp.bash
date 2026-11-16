# Split a command line into the array `words` the way the shell would, removing
# quotes and backslashes without evaluating anything; the last element is the
# word being typed (possibly empty). `trim` gets the part of that word up to
# its last unquoted ':', which Readline does not replace when ':' is in
# COMP_WORDBREAKS. Both variables belong to the caller.
# A function because legacy scp paths are unquoted twice: once for this shell
# and once for the remote shell.
_mini_scp_split()
{
    local line="$1" token= quote= escaped= char i
    words=(); trim=
    for ((i=0; i<${#line}; i++)); do
        char="${line:i:1}"
        if [ -n "$escaped" ]; then
            if [ "$quote" = '"' ]; then
                case "$char" in '"'|'$'|'`'|'\') ;; *) token="$token\\" ;; esac
            fi
            token="$token$char"; escaped=; continue
        fi
        case "$quote" in
            "'") if [ "$char" = "'" ]; then quote=; else token="$token$char"; fi ;;
            '"') case "$char" in '"') quote= ;; '\') escaped=yes ;; *) token="$token$char" ;; esac ;;
            *) case "$char" in
                '\') escaped=yes ;;
                "'"|'"') quote="$char" ;;
                ' '|$'\t'|$'\n') [ -z "$token" ] || words+=("$token"); token=; trim= ;;
                ':')
                    if [[ "$COMP_WORDBREAKS" == *:* ]]; then trim="$token:"; fi
                    token="$token$char" ;;
                *) token="$token$char" ;;
            esac ;;
        esac
    done
    words+=("$token")
}
# Options, SSH config Host aliases, local paths, and after "[user@]host:" the
# remote directory, listed with `ssh host ls`. The listing runs with
# BatchMode=yes (no password or passphrase prompt) under a 2s limit and needs
# timeout(1); nothing is offered when it fails. Relative remote paths start at
# the remote home directory.
# With the legacy scp protocol the remote shell parses the path, so it needs a
# second level of quoting; with SFTP it is taken as typed. Legacy is assumed
# for -O, and without -s for OpenSSH before 9.0 (`ssh -V`);
# MINI_SCP_LEGACY_PROTOCOL=yes|no overrides the version test.
_mini_scp_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" candidate key rest host prefix= value token
    local trim word_trim path directory base listed remote_directory listing legacy= version i quote="'" escaped_quote="'\\''"
    local -a words ssh_args=()
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
    _mini_scp_split "${COMP_LINE:0:COMP_POINT}"
    token="${words[${#words[@]}-1]}"; word_trim="$trim"
    if [[ "$token" == *:* ]]; then
        # A slash before ':' denotes a local path, e.g. ./file:with-colon.
        [[ "${token%%:*}" != */* ]] || return 0
        command -v timeout >/dev/null 2>&1 || return 0
        host="${token%%:*}"; path="${token#*:}"
        [ -n "$host" ] || return 0
        [[ "$host" != -* ]] || return 0
        # Connection options already typed for scp are passed on to ssh.
        for ((i=1; i<${#words[@]}-1; i++)); do
            case "${words[i]}" in
                -P) ssh_args+=(-p "${words[i+1]}"); i=$((i + 1)) ;;
                -i|-F|-J|-o) ssh_args+=("${words[i]}" "${words[i+1]}"); i=$((i + 1)) ;;
                -4|-6) ssh_args+=("${words[i]}") ;;
                -O) legacy=yes ;;
                -s) legacy=no ;;
            esac
        done
        if [ -z "$legacy" ]; then
            legacy="${MINI_SCP_LEGACY_PROTOCOL:-}"
            if [ -z "$legacy" ]; then
                version="$(ssh -V 2>&1)"
                if [[ "$version" =~ OpenSSH_([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -lt 9 ]; then legacy=yes; fi
            fi
        fi
        if [[ "$path" == */* ]]; then
            directory="${path%/*}/"; base="${path##*/}"
        else
            directory=; base="$path"
        fi
        # Legacy: the typed directory is in remote shell syntax; remove that
        # quoting (never evaluate it) to get the real name.
        listed="$directory"
        if [ "$legacy" = yes ] && [ -n "$directory" ]; then
            _mini_scp_split "$directory"
            listed="${words[${#words[@]}-1]}"
        fi
        # The remote shell parses the ls command line: quote the directory, but
        # leave a leading ~/ unquoted so that it expands there.
        case "$listed" in
            '') remote_directory=. ;;
            '~/'*) remote_directory="${listed#'~/'}"; remote_directory="~/'${remote_directory//$quote/$escaped_quote}'" ;;
            *) remote_directory="'${listed//$quote/$escaped_quote}'" ;;
        esac
        # -L: a symlink to a directory is listed as a directory. ls also fails
        # for a dangling symlink in the directory, so its output is used
        # whatever it returns.
        listing="$(timeout -k 1 2 ssh -o BatchMode=yes -a -x "${ssh_args[@]}" -- "$host" "ls -1ApL -- $remote_directory" 2>/dev/null)" || true
        # Readline replaces only the suffix after the last unquoted word-breaking colon.
        while IFS= read -r candidate; do
            [ -n "$candidate" ] || continue
            if [ "$legacy" = yes ]; then
                # Quote the name for the remote shell; Readline quotes it again for this one.
                if [[ "$candidate" == */ ]]; then printf -v candidate '%q/' "${candidate%/}"; else printf -v candidate '%q' "$candidate"; fi
            fi
            [[ "$candidate" == "$base"* ]] || continue
            candidate="$host:$directory$candidate"
            COMPREPLY+=("${candidate#"$word_trim"}")
        done <<< "$listing"
        compopt -o filenames 2>/dev/null || true
        return
    fi
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
