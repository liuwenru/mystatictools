# sshfs: options, -o mount options and their values, Host aliases from the SSH
# config for [user@]host:, and a local directory for the mount point.
#
# -o option names are read from the typed sshfs's own `-h` output, so they
# follow the local version (sshfs 2.x and 3.x print different lists); a fixed
# list is used when that fails. Common ssh_config options are added because
# sshfs passes unknown -o Name=value options to ssh.
# Never opens an SSH connection: nothing is completed after "host:".

_mini_sshfs_ssh_options='BatchMode= Ciphers= Compression= ConnectTimeout= ControlMaster= ControlPath= ControlPersist= HostKeyAlgorithms= HostName= IdentitiesOnly= IdentityFile= Port= PreferredAuthentications= ProxyCommand= ProxyJump= PubkeyAcceptedAlgorithms= ServerAliveCountMax= ServerAliveInterval= StrictHostKeyChecking= User= UserKnownHostsFile='

_mini_sshfs_static_options='reconnect delay_connect sshfs_sync no_readahead sync_readdir dir_cache= dcache_timeout= direct_io workaround= idmap= uidfile= gidfile= nomap= ssh_command= sftp_server= directport= passive disable_hardlink transform_symlinks follow_symlinks no_check_root password_stdin max_conns= port= compression= kernel_cache auto_cache noauto_cache umask= uid= gid= entry_timeout= negative_timeout= attr_timeout= allow_other allow_root auto_unmount debug'

# Mount options from `sshfs -h`: "-o name", "-o name=VALUE", "-o [no]name",
# "-o prefix_{a,b}_suffix=N"; "opt,[opt...]" and "SSHOPT=VAL" are skipped.
_mini_sshfs_options()
{
    local line name pre list post item
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(-[A-Za-z][[:space:]]+)?-o[[:space:]]+([^[:space:]]+) ]] || continue
        name="${BASH_REMATCH[2]}"
        case "$name" in *'['*'...'*|SSHOPT=*) continue ;; esac
        case "$name" in *=*) name="${name%%=*}=" ;; esac
        if [[ "$name" == '[no]'* ]]; then
            printf '%s\n' "${name#\[no\]}" "no${name#\[no\]}"
        elif [[ "$name" =~ ^([^{]*)\{([^}]*)\}(.*)$ ]]; then
            pre="${BASH_REMATCH[1]}" list="${BASH_REMATCH[2]}" post="${BASH_REMATCH[3]}"
            for item in ${list//,/ }; do printf '%s\n' "$pre$item$post"; done
        else
            printf '%s\n' "$name"
        fi
    done < <(
        if command -v timeout >/dev/null 2>&1; then
            timeout -k 1 2 "$_mini_sshfs_bin" -h 2>&1
        else
            "$_mini_sshfs_bin" -h 2>&1
        fi
    )
}

# Host aliases from the SSH config (no wildcards), like scp.bash.
_mini_sshfs_hosts()
{
    local file key rest host
    for file in "$HOME/.ssh/config" /etc/ssh/ssh_config; do
        [ -r "$file" ] || continue
        while read -r key rest; do
            case "$key" in
                [Hh][Oo][Ss][Tt])
                    for host in $rest; do
                        case "$host" in *[\*\?\!]*|\#*) continue ;; esac
                        printf '%s\n' "$host"
                    done ;;
            esac
        done < "$file"
    done
}

_mini_sshfs_completion()
{
    local _mini_sshfs_bin="${COMP_WORDS[0]}"
    local line c q= word= inword= keep=0 i current previous positional=0 skip=
    local -a words=()
    local list= item key value candidate prefix
    local -a candidates=()
    COMPREPLY=()

    # Split the line before the cursor like the shell (quotes, backslashes);
    # "host:/dir" and "-o a=b,c=d" stay one word. keep is the number of
    # leading characters of the last word that readline does not replace.
    line="${COMP_LINE:0:${COMP_POINT:-${#COMP_LINE}}}"
    for ((i = 0; i < ${#line}; i++)); do
        c="${line:i:1}"
        if [ -n "$q" ]; then
            if [ "$c" = "$q" ]; then q=
            elif [ "$q" = '"' ] && [ "$c" = '\' ] && [[ "${line:i+1:1}" == [\"\\\$\`] ]]; then
                i=$((i + 1)); word+="${line:i:1}"
            else word+="$c"
            fi
            continue
        fi
        case "$c" in
            [[:space:]]) [ -z "$inword" ] || words+=("$word"); word= inword= keep=0 ;;
            \'|\") q="$c" inword=1 keep=${#word} ;;
            \\) i=$((i + 1)); word+="${line:i:1}" inword=1 ;;
            *)
                word+="$c" inword=1
                # Readline keeps '@' and '$' in the replaced text.
                case "${COMP_WORDBREAKS-}" in
                    *"$c"*) keep=${#word}; [[ "$c" != [@\$] ]] || keep=$((keep - 1)) ;;
                esac ;;
        esac
    done
    words+=("$word")
    current="$word"
    previous="${words[${#words[@]}-2]-}"

    # Count positional arguments before the cursor: [user@]host:[dir] mountpoint.
    for ((i = 1; i < ${#words[@]} - 1; i++)); do
        if [ -n "$skip" ]; then skip=; continue; fi
        case "${words[i]}" in
            -o|-p|-F) skip=1 ;;
            -*) ;;
            *) positional=$((positional + 1)) ;;
        esac
    done
    # previous is an option only when it takes the current word as its value.
    [ -n "$skip" ] || previous=

    case "$previous" in
        -p) return 0 ;;
        -F)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
            compopt -o filenames 2>/dev/null
            return 0 ;;
    esac

    # -o list (also written -oLIST): complete the item after the last comma.
    if [ "$previous" = -o ] || [[ "$current" == -o?* ]]; then
        if [ "$previous" = -o ]; then list="$current"; else list="${current#-o}"; fi
        prefix="${current:0:${#current}-${#list}}"
        item="${list##*,}"
        prefix+="${list:0:${#list}-${#item}}"
        if [[ "$item" == *=* ]]; then
            key="${item%%=*}" value="${item#*=}"
            prefix+="$key="
            case "$key" in
                dir_cache|cache|compression|transform_symlinks|rellinks|[Bb]atch[Mm]ode|[Cc]ompression|[Ii]dentities[Oo]nly)
                    candidates=(yes no) ;;
                idmap) candidates=(none user file) ;;
                nomap) candidates=(ignore error) ;;
                workaround)
                    # Colon-separated list.
                    prefix+="${value%"${value##*:}"}"; value="${value##*:}"
                    candidates=(none all rename norename renamexdev norenamexdev truncate notruncate buflimit nobuflimit fstat nofstat createmode nocreatemode) ;;
                [Ss]trict[Hh]ost[Kk]ey[Cc]hecking) candidates=(yes no accept-new ask) ;;
                [Cc]ontrol[Mm]aster) candidates=(yes no auto ask autoask) ;;
                [Pp]roxy[Jj]ump|[Hh]ost[Nn]ame)
                    while IFS= read -r candidate; do candidates+=("$candidate"); done < <(_mini_sshfs_hosts) ;;
                ssh_command)
                    while IFS= read -r candidate; do candidates+=("$candidate"); done < <(compgen -c -- "$value") ;;
                uidfile|gidfile|[Ii]dentity[Ff]ile|[Uu]ser[Kk]nown[Hh]osts[Ff]ile|[Cc]ontrol[Pp]ath)
                    while IFS= read -r candidate; do
                        [ -d "$candidate" ] && candidate+=/
                        candidates+=("$candidate")
                    done < <(compgen -f -- "$value")
                    compopt -o nospace 2>/dev/null ;;
                *) return 0 ;;
            esac
        else
            value="$item"
            while IFS= read -r candidate; do candidates+=("$candidate"); done < <(_mini_sshfs_options)
            ((${#candidates[@]})) || candidates=($_mini_sshfs_static_options)
            candidates+=(ro rw default_permissions $_mini_sshfs_ssh_options)
        fi
        for candidate in "${candidates[@]}"; do
            [[ "$candidate" == "$value"* ]] || continue
            candidate="$prefix$candidate"
            COMPREPLY+=("${candidate:keep}")
            case "$candidate" in *=|*/) compopt -o nospace 2>/dev/null ;; esac
        done
        return 0
    fi

    if [[ "$current" == -* ]]; then
        COMPREPLY=($(compgen -W '-o -p -C -F -f -s -d --debug -v --verbose -1 -h --help -V --version' -- "$current"))
        return 0
    fi

    case "$positional" in
        0)
            # [user@]host: from the SSH config; nothing after the colon.
            [[ "$current" != *:* ]] || return 0
            prefix= value="$current"
            if [[ "$current" == *@* ]]; then prefix="${current%@*}@" value="${current##*@}"; fi
            while IFS= read -r candidate; do
                [[ "$candidate" == "$value"* ]] || continue
                candidate="$prefix$candidate:"
                COMPREPLY+=("${candidate:keep}")
            done < <(_mini_sshfs_hosts)
            compopt -o nospace 2>/dev/null ;;
        1)
            # Mount point: a local directory.
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -d -- "$current")
            compopt -o filenames 2>/dev/null ;;
    esac
    return 0
}

complete -F _mini_sshfs_completion sshfs
