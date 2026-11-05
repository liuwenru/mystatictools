# ipset: subcommands, set names, set types and per-type parameters.
# Set types come from `ipset help`, create/add/del/test parameters from
# `ipset help TYPE` of the local binary. For add, `ipset list -t SET` tells the
# set's real type and options, so only parameters the set accepts are offered;
# del/test complete existing members from `ipset list SET`. All queries are
# read-only and fall back to fixed lists when they fail.

_MINI_IPSET_TYPES='bitmap:ip bitmap:ip,mac bitmap:port hash:ip hash:mac hash:ip,mac hash:net hash:net,net hash:ip,port hash:net,port hash:ip,port,ip hash:ip,port,net hash:ip,mark hash:net,port,net hash:net,iface list:set'
# Upper limit of members offered after del/test; large sets are cut here.
_MINI_IPSET_MAX_MEMBERS=1000

# Run the typed ipset binary (e.g. ./ipset) with a time limit when possible.
_mini_ipset_run()
{
    if command -v timeout >/dev/null 2>&1; then
        timeout -k 1 2 "$_mini_ipset_bin" "$@"
    else
        "$_mini_ipset_bin" "$@"
    fi
}

# Parse one section (create/add/del/test) of `ipset help TYPE` into lines
# "<keyword> <flag|value> <value-token> <enum values...>".
_mini_ipset_parse_type_help()
{
    awk -v want="$1" '
    function addkw(spec, arg,    n, k, i, e) {
        n = split(spec, k, "|")
        e = ""
        if (arg ~ /^[a-z][a-z0-9]*(\|[a-z][a-z0-9]*)+$/) { e = arg; gsub(/\|/, " ", e) }
        for (i = 1; i <= n; i++) {
            if (k[i] !~ /^(-[46]|[a-z][a-z0-9-]*)$/ || (k[i] in seen)) continue
            seen[k[i]] = 1
            printf "%s %s %s %s\n", k[i], (arg == "" ? "flag" : "value"), (arg == "" ? "-" : arg), e
        }
    }
    function parse(s,    g, w, n, i) {
        while (match(s, /\[[^][]*\]/)) {
            g = substr(s, RSTART + 1, RLENGTH - 2)
            s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
            n = split(g, w, " ")
            addkw(w[1], (n >= 2) ? w[2] : "")
        }
        # Required keywords outside brackets, e.g. "range IP/CIDR", "markmask VALUE".
        n = split(s, w, " ")
        for (i = 1; i < n; i++)
            if (w[i] ~ /^[a-z][a-z0-9-]*$/) { addkw(w[i], w[i + 1]); i++ }
    }
    # The general usage printed before this line has the same layout; skip it.
    /type specific options:/ { started = 1; next }
    !started { next }
    /^[^ \t]/ {
        insec = ($1 == want && $2 == "SETNAME")
        if (insec) { line = $0; sub(/^[^ ]+ +SETNAME +[^ ]+/, "", line); parse(line) }
        next
    }
    insec && /^[ \t]/ { parse($0) }'
}

_mini_ipset_completion()
{
    local current previous words= candidate action= type= word prefix= i position=0 skip=no
    local raw="${COMP_WORDS[COMP_CWORD]}" line help= header= set= used=' ' keyword kind arg enum
    local options='-exist -! -output -o -quiet -q -resolve -r -sorted -s -name -n -terse -t -file -f'
    local _mini_ipset_bin="${COMP_WORDS[0]}"
    local -a tokens=()
    COMPREPLY=()

    # The real command line keeps "hash:ip" and "2001:db8::1" in one word;
    # COMP_WORDS splits them at ':'. Use it when it matches this command.
    if [ -n "${COMP_LINE:-}" ]; then
        line="${COMP_LINE:0:${COMP_POINT:-${#COMP_LINE}}}"
        read -r -a tokens <<< "$line"
        [[ "$line" != *[[:space:]] ]] || tokens+=('')
        if ((${#tokens[@]} >= 2)) && [ "${tokens[0]}" = "${COMP_WORDS[0]}" ]; then
            tokens=("${tokens[@]:1}")
        else
            tokens=()
        fi
    fi
    if ((${#tokens[@]} == 0)); then
        # No usable COMP_LINE: rejoin words that Bash split at ':'.
        for ((i=1; i<=COMP_CWORD; i++)); do
            word="${COMP_WORDS[i]}"
            if [[ "$word" == :* && -z "${word//:/}" ]] && ((${#tokens[@]})); then
                tokens[${#tokens[@]}-1]+="$word"
            elif ((${#tokens[@]})) && [[ "${tokens[${#tokens[@]}-1]}" == *: ]]; then
                tokens[${#tokens[@]}-1]+="$word"
            else
                tokens+=("$word")
            fi
        done
    fi
    current="${tokens[${#tokens[@]}-1]}"
    previous=
    if ((${#tokens[@]} > 1)); then previous="${tokens[${#tokens[@]}-2]}"; fi
    # Readline replaces only the text after the last ':'; strip that part.
    if [[ -n "$raw" && -z "${raw//:/}" ]]; then
        prefix="$current"
    elif ((${#current} > ${#raw})); then
        prefix="${current:0:${#current}-${#raw}}"
    fi

    # Ignore global switches and their values when counting command arguments.
    for ((i=0; i<${#tokens[@]}-1; i++)); do
        word="${tokens[i]}"
        if [ "$skip" = yes ]; then skip=no; continue; fi
        case "$word" in
            -o|-output|-f|-file) skip=yes; continue ;;
            -[46]) [ "$action" = create ] && used="$used$word " ; continue ;;
            -*) continue ;;
        esac
        if [ -z "$action" ]; then
            case "$word" in n) action=create ;; x) action=destroy ;; e) action=rename ;; w) action=swap ;; *) action="$word" ;; esac
        else
            position=$((position + 1))
            ((position != 1)) || set="$word"
            if [ "$action" = create ] && ((position == 2)); then type="$word"; fi
            ((position < 3)) || used="$used$word "
        fi
    done

    case "$previous" in
        -f|-file)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$raw")
            compopt -o filenames 2>/dev/null || true
            return ;;
        -o|-output) words='plain save xml json' ;;
        *)
            if [[ "$current" == -* && "$current" != -[46] ]] && ! { [ "$action" = create ] && ((position >= 2)); }; then
                words="$options"
            elif [ -z "$action" ]; then
                words='create add del test destroy list save restore flush rename swap help version'
            else
                # For add/del/test the type comes from the existing set.
                if [ -n "$set" ] && { ((position >= 2)) || [ "$action" = add ]; } && [[ "$action" == add || "$action" == del || "$action" == test ]]; then
                    header="$(_mini_ipset_run list -t "$set" 2>/dev/null)"
                    type="$(awk '$1 == "Type:" {print $2; exit}' <<< "$header")"
                    header=" $(awk '$1 == "Header:" {$1 = ""; print; exit}' <<< "$header") "
                fi
                if ((position >= 2)) && [ -n "$type" ] && [[ "$action" == create || "$action" == add || "$action" == del || "$action" == test ]]; then
                    help="$(_mini_ipset_run help "$type" 2>/dev/null | _mini_ipset_parse_type_help "$action")"
                fi
                case "$action:$position" in
                    add:0|del:0|test:0|destroy:0|list:0|save:0|flush:0|rename:0|swap:0|swap:1)
                        words="$(_mini_ipset_run list -name 2>/dev/null)" ;;
                    create:1|help:0)
                        words="$(_mini_ipset_run help 2>/dev/null | awk '/^Supported set types:/ {f = 1; next} f && NF && !seen[$1]++ {print $1}')"
                        [ -n "$words" ] || words="$_MINI_IPSET_TYPES" ;;
                    del:1|test:1)
                        # Existing members, filtered by the typed prefix in awk.
                        words="$(_mini_ipset_run list "$set" 2>/dev/null | awk -v cur="$current" -v max="$_MINI_IPSET_MAX_MEMBERS" '
                            f && NF && index($1, cur) == 1 { print $1; if (++n >= max) exit }
                            $1 == "Members:" { f = 1 }')" ;;
                    add:1) [ "$type" != list:set ] || words="$(_mini_ipset_run list -name 2>/dev/null)" ;;
                    create:*|add:*|del:*|test:*)
                        if [ -n "$help" ]; then
                            line="$(awk -v k="$previous" '$1 == k && $2 == "value"' <<< "$help")"
                            if [ -n "$line" ] && ((position >= 3)); then
                                read -r keyword kind arg enum <<< "$line"
                                case "$arg" in
                                    NAME) words="$(_mini_ipset_run list -name 2>/dev/null)" ;;
                                    *) words="$enum" ;;
                                esac
                            else
                                while read -r keyword kind arg enum; do
                                    [ -n "$keyword" ] || continue
                                    [[ "$used" != *" $keyword "* ]] || continue
                                    # Options a set was not created with are rejected by add.
                                    if [ "$action" = add ] && [ "$header" != '  ' ]; then
                                        case "$keyword" in
                                            timeout) [[ "$header" == *' timeout '* ]] || continue ;;
                                            packets|bytes) [[ "$header" == *' counters '* ]] || continue ;;
                                            comment) [[ "$header" == *' comment '* ]] || continue ;;
                                            skbmark|skbprio|skbqueue) [[ "$header" == *' skbinfo '* ]] || continue ;;
                                        esac
                                    fi
                                    words="$words $keyword"
                                done <<< "$help"
                            fi
                        elif [ "$action" = create ] && ((position >= 2)); then
                            # Fixed fallback when `ipset help TYPE` is unavailable.
                            case "$previous" in
                                family) words='inet inet6' ;;
                                range|netmask|bitmask|hashsize|maxelem|bucketsize|timeout|size|markmask) ;;
                                *)
                                    words='timeout counters comment skbinfo'
                                    case "$type" in
                                        hash:*)
                                            words+=' hashsize maxelem bucketsize forceadd'
                                            [ "$type" = hash:mac ] || words+=' family'
                                            case "$type" in hash:ip|hash:ip,port|hash:net,net) words+=' netmask bitmask' ;; hash:ip,mark) words+=' markmask' ;; esac ;;
                                        bitmap:*) words+=' range'; [ "$type" != bitmap:ip ] || words+=' netmask' ;;
                                        list:set) words+=' size' ;;
                                    esac ;;
                            esac
                        elif [ "$action" = add ] && ((position >= 2)); then
                            case "$previous" in
                                timeout|packets|bytes|comment|skbmark|skbprio|skbqueue) ;;
                                *) words='timeout packets bytes comment skbmark skbprio skbqueue nomatch' ;;
                            esac
                        fi ;;
                esac
            fi ;;
    esac
    while IFS= read -r candidate; do
        COMPREPLY+=("${candidate#"$prefix"}")
    done < <(compgen -W "$words" -- "$current")
}
complete -F _mini_ipset_completion ipset
