_mini_iptables_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words table=filter word i chains
    COMPREPLY=()
    for ((i=1; i<COMP_CWORD; i++)); do
        case "${COMP_WORDS[i]}" in -t|--table) table="${COMP_WORDS[i+1]}" ;; esac
    done
    case "$previous" in
        -t|--table) words='filter nat mangle raw security' ;;
        -p|--protocol) words='tcp udp udplite icmp icmpv6 esp ah sctp all' ;;
        -j|--jump|-g|--goto)
            chains="$(iptables -w 1 -t "$table" -S 2>/dev/null | awk '$1 == "-N" {print $2}')"
            words="ACCEPT DROP RETURN REJECT LOG NFLOG QUEUE NFQUEUE MARK CONNMARK DNAT SNAT MASQUERADE REDIRECT $chains" ;;
        -A|--append|-C|--check|-D|--delete|-I|--insert|-R|--replace|-L|--list|-S|--list-rules|-F|--flush|-Z|--zero|-X|--delete-chain|-P|--policy|-E|--rename-chain)
            case "$table" in
                filter|security) words='INPUT FORWARD OUTPUT' ;;
                nat) words='PREROUTING INPUT OUTPUT POSTROUTING' ;;
                mangle) words='PREROUTING INPUT FORWARD OUTPUT POSTROUTING' ;;
                raw) words='PREROUTING OUTPUT' ;;
            esac
            chains="$(iptables -w 1 -t "$table" -S 2>/dev/null | awk '$1 == "-N" {print $2}')"
            words="$words $chains" ;;
        -i|--in-interface|-o|--out-interface)
            for word in /sys/class/net/*; do [ ! -e "$word" ] || words="$words ${word##*/}"; done ;;
        -m|--match) words='tcp udp icmp conntrack state multiport comment limit hashlimit addrtype owner set mark connmark statistic recent iprange' ;;
        --ctstate|--state) words='NEW ESTABLISHED RELATED INVALID UNTRACKED' ;;
        --reject-with) words='icmp-port-unreachable icmp-host-unreachable icmp-net-unreachable icmp-admin-prohibited tcp-reset' ;;
        -s|--source|-d|--destination|--sport|--source-port|--dport|--destination-port|--sports|--dports|--comment|--to-source|--to-destination|-N|--new-chain|--set-mark|--log-prefix|-w|--wait|-W|--wait-interval) return ;;
        *)
            if (( COMP_CWORD >= 2 )) && [[ "${COMP_WORDS[COMP_CWORD-2]}" == -P || "${COMP_WORDS[COMP_CWORD-2]}" == --policy ]]; then
                words='ACCEPT DROP'
            else
                words='-t --table -A --append -C --check -D --delete -I --insert -R --replace -L --list -S --list-rules -F --flush -Z --zero -N --new-chain -X --delete-chain -P --policy -E --rename-chain -p --protocol -s --source -d --destination -i --in-interface -o --out-interface -j --jump -g --goto -m --match -n --numeric -v --verbose -x --exact --line-numbers -w --wait --sport --dport --sports --dports --ctstate --state --comment --reject-with --to-source --to-destination --log-prefix --help --version'
            fi ;;
    esac
    COMPREPLY=( $(compgen -W "$words" -- "$current") )
}
complete -F _mini_iptables_completion iptables
