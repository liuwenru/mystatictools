_mini_nft_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words candidate family= object= table= i
    COMPREPLY=()
    case "$previous" in
        -f|--file)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
        -I|--includepath)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -d -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
        -d|--debug) words='scanner parser eval netlink mnl proto-ctx segtree all' ;;
        list) words='ruleset tables chains sets maps counters quotas table chain set map flowtable counter quota' ;;
        flush) words='ruleset table chain set map' ;;
        add|create|delete|destroy|rename) words='table chain rule set map element flowtable counter quota' ;;
        insert|replace) words='rule' ;;
        reset) words='counters quotas rules' ;;
        monitor) words='new destroy trace ruleset tables chains rules sets elements' ;;
        table|chain|rule|set|map|element|flowtable|tables|chains|sets|maps) words='inet ip ip6 arp bridge netdev' ;;
        inet|ip|ip6|arp|bridge|netdev)
            words="$(nft list tables "$previous" 2>/dev/null | awk '$1 == "table" {print $3}')" ;;
        *)
            case "$current" in
                -*) words='-h --help -v --version -c --check -f --file -i --interactive -I --includepath -n --numeric -a --handle -s --stateless -t --terse -j --json -e --echo -d --debug' ;;
                *)
                    if (( COMP_CWORD == 1 )); then
                        words='add create insert replace delete destroy list flush reset rename monitor describe import export'
                    else
                        for ((i=1; i<COMP_CWORD; i++)); do
                            case "${COMP_WORDS[i]}" in
                                chain|rule|set|map|element|flowtable)
                                    object="${COMP_WORDS[i]}"; family="${COMP_WORDS[i+1]}"; table="${COMP_WORDS[i+2]}"; break ;;
                            esac
                        done
                        if [ -n "$object" ] && (( COMP_CWORD == i+3 )); then
                            case "$object" in rule) object=chain ;; element) object=set ;; esac
                            words="$(nft list table "$family" "$table" 2>/dev/null | awk -v kind="$object" '$1 == kind {print $2}')"
                        else
                            words='ruleset table chain rule set map element counter quota flowtable type hook priority policy accept drop reject return jump goto ip ip6 inet tcp udp icmp ct meta iifname oifname saddr daddr sport dport state established related new invalid'
                        fi
                    fi ;;
            esac ;;
    esac
    COMPREPLY=( $(compgen -W "$words" -- "$current") )
}
complete -F _mini_nft_completion nft
