_mini_ipset_completion()
{
    local current previous words= candidate action= type= word prefix= i position=0 skip=no
    local raw="${COMP_WORDS[COMP_CWORD]}"
    local options='-exist -! -output -o -quiet -q -resolve -r -sorted -s -name -n -terse -t -file -f'
    local types='bitmap:ip bitmap:ip,mac bitmap:port hash:ip hash:mac hash:ip,mac hash:net hash:net,net hash:ip,port hash:net,port hash:ip,port,ip hash:ip,port,net hash:ip,mark hash:net,port,net hash:net,iface list:set'
    local -a tokens=()
    COMPREPLY=()

    # Bash normally splits type names at ':'. Rejoin them for positional parsing.
    for ((i=1; i<=COMP_CWORD; i++)); do
        word="${COMP_WORDS[i]}"
        if [ "$word" = : ] && ((${#tokens[@]})); then
            tokens[${#tokens[@]}-1]+=':'
        elif ((${#tokens[@]})) && [[ "${tokens[${#tokens[@]}-1]}" == *: ]]; then
            tokens[${#tokens[@]}-1]+="$word"
        else
            tokens+=("$word")
        fi
    done
    current="${tokens[${#tokens[@]}-1]}"
    previous=
    if ((${#tokens[@]} > 1)); then previous="${tokens[${#tokens[@]}-2]}"; fi
    if [ "$raw" = : ]; then
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
            -*) continue ;;
        esac
        if [ -z "$action" ]; then
            case "$word" in n) action=create ;; x) action=destroy ;; e) action=rename ;; w) action=swap ;; *) action="$word" ;; esac
        else
            position=$((position + 1))
            if [ "$action" = create ] && ((position == 2)); then type="$word"; fi
        fi
    done

    case "$previous" in
        -f|-file)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$raw")
            compopt -o filenames 2>/dev/null || true
            return ;;
        -o|-output) words='plain save xml json' ;;
        *)
            if [[ "$current" == -* ]]; then
                words="$options"
            elif [ -z "$action" ]; then
                words='create add del test destroy list save restore flush rename swap help version'
            else
                case "$action:$position" in
                    add:0|del:0|test:0|destroy:0|list:0|save:0|flush:0|rename:0|swap:0|swap:1)
                        words="$(ipset list -name 2>/dev/null)" ;;
                    create:1|help:0) words="$types" ;;
                    create:*)
                        if ((position >= 2)); then
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
                        fi ;;
                    add:*)
                        if ((position >= 2)); then
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
