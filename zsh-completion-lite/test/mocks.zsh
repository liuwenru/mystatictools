# Sourced inside the test zsh (zpty) after init.zsh. Dynamic commands are
# shell functions; no daemon, network or root access is required.

# Record each match instead of inserting it: "M:<word as inserted>".
compadd()
{
    local -a args=("$@") hits
    local a c v pre= hp= hs= suf= ip= i=1 j
    while (( i <= $#args )); do
        a=$args[i]
        [[ $a == -- || $a != -?* ]] && break
        for (( j = 2; j <= $#a; j++ )); do
            c=$a[j]
            if [[ $c == [PSpsiIWdJVXxrRMFOADE] ]]; then
                if (( j < $#a )); then v=$a[j+1,-1]; else (( i++ )); v=$args[i]; fi
                case $c in
                    P) pre=$v ;; p) hp=$v ;; s) hs=$v ;; S) suf=$v ;; i) ip=$v ;;
                    [OAD]) builtin compadd "$@"; return ;;
                esac
                break
            fi
        done
        (( i++ ))
    done
    builtin compadd -A hits "$@"
    local ret=$?
    for v in $hits; do print -r -- "M:$IPREFIX$ip$pre$hp$v$hs$suf" >> $ZCL_OUT; done
    return ret
}

systemctl()
{
    case " $* " in
        *' list-unit-files '*) print -l 'sshd.service enabled' 'example.timer enabled' ;;
        *' list-units '*) print -l 'sshd.service loaded active running SSH' ;;
    esac
}
journalctl() { print -l 'IDX BOOT ID FIRST ENTRY LAST ENTRY' '0 boot-id date range'; }
rg() { print -l 'rust: *.rs' 'python: *.py'; }
iptables() { print -l -- '-P INPUT ACCEPT' '-N CUSTOM_CHAIN'; }
nft()
{
    case " $* " in
        *' list tables '*) print -l 'table inet filter' ;;
        *' list table '*) print -l 'table inet filter {' ' chain input {' ' }' '}' ;;
    esac
}
timeout()
{
    # Run the mocked command in this shell, checking the deadline arguments.
    [[ $1 == -k && $2 == 1 && $3 == 2 ]] || return 1
    shift 3
    "$@"
}
ipset()
{
    # Only read-only queries are allowed; anything else is a test failure.
    [[ ${TEST_IPSET_FAIL:-} != yes ]] || return 1
    [[ ${TEST_IPSET_NOHELP:-} == yes && $1 == help ]] && return 1
    case "$*" in
        'help hash:ip'|'help hash:net'|'help hash:mac'|'help bitmap:port'|'help list:set')
            # Real `ipset help TYPE` prints the general usage first, in the same layout.
            print -l 'Usage: ipset [options] COMMAND' '' 'Commands:' 'create SETNAME TYPENAME [type-specific-options]' '        Create a new set' 'add SETNAME ENTRY' '        Add entry to the named set' ''
            printf '%s type specific options:\n\n' "$2" ;;
    esac
    case "$*" in
        'list -name') print -l blocked trusted group ;;
        'list -t blocked') print -l 'Name: blocked' 'Type: hash:ip' 'Header: family inet hashsize 1024 maxelem 65536 timeout 0 comment bucketsize 12' ;;
        'list -t trusted') print -l 'Name: trusted' 'Type: hash:net' 'Header: family inet hashsize 1024 maxelem 65536 bucketsize 12' ;;
        'list -t group') print -l 'Name: group' 'Type: list:set' 'Header: size 8' ;;
        'list blocked') print -l 'Name: blocked' 'Type: hash:ip' 'Header: family inet timeout 0 comment' 'Members:' '192.0.2.1 timeout 30 comment "x"' '192.0.2.10 timeout 0' '2001:db8::1 timeout 0' ;;
        'list trusted') print -l 'Name: trusted' 'Type: hash:net' 'Members:' '10.0.0.0/8' ;;
        help)
            print -l 'Usage: ipset [options] COMMAND' '' 'Supported set types:'
            printf '    %s\t\t%s\n' hash:ip 6 hash:ip 5 hash:net 7 hash:mac 1 bitmap:port 3 list:set 3 hash:ip,port,net 8 ;;
        'help hash:ip')
            print -l 'create SETNAME hash:ip ' '               [family inet|inet6]|[-4|-6]' '               [hashsize VALUE]' '               [netmask CIDR]' '               [timeout VALUE]' '               [counters]' '               [comment]' '               [skbinfo]'
            print -l 'add    SETNAME hash:ip IP' '               [timeout VALUE]' '               [packets VALUE]' '               [bytes VALUE]' '               [comment "string"]' '               [skbmark VALUE]' 'del    SETNAME hash:ip IP' 'test   SETNAME hash:ip IP' '' 'where depending on the INET family' ;;
        'help hash:net')
            print -l 'create SETNAME hash:net ' '               [family inet|inet6]|[-4|-6]' '               [timeout VALUE]' 'add    SETNAME hash:net IP[/CIDR]' '               [timeout VALUE]' '               [nomatch]' '               [comment "string"]' 'del    SETNAME hash:net IP[/CIDR]' 'test   SETNAME hash:net IP[/CIDR]' '               [nomatch]' ;;
        'help hash:mac') print -l 'create SETNAME hash:mac ' '               [hashsize VALUE]' '               [timeout VALUE]' 'add    SETNAME hash:mac MAC' ;;
        'help bitmap:port') print -l 'create SETNAME bitmap:port range [PROTO:]FROM-TO' '               [timeout VALUE]' 'add    SETNAME bitmap:port [PROTO:]PORT|FROM-TO' ;;
        'help list:set') print -l 'create SETNAME list:set ' '               [size VALUE]' 'add    SETNAME list:set NAME [before|after NAME]' '               [timeout VALUE]' '               [before|after NAME]' 'del    SETNAME list:set NAME [before|after NAME]' ;;
        help\ *) return 1 ;;
        *) print UNEXPECTED_IPSET_QUERY; return 1 ;;
    esac
}
docker()
{
    case " $* " in
        *' exec --env LC_ALL=C --env QUOTING_STYLE=literal '*' ls -1Ap -- '*)
            case ${TEST_DOCKER_LS:-} in
                timeout)
                    # A retry after a timeout would incorrectly produce a candidate.
                    if [[ " $* " == *' busybox ls '* ]]; then print root/; return 0; fi
                    return 124 ;;
                busybox) [[ " $* " == *' busybox ls '* ]] || return 127 ;;
                stopped) return 1 ;;
            esac
            case ${@[-1]} in
                /) print -l root/ run/ 'file with spaces/' .hidden ;;
                /root/) print -l report.txt reports/ 'report with spaces.txt' ;;
                '/file with spaces/') print -l nested.txt ;;
                *) return 1 ;;
            esac ;;
        *' ps -a --format {{.ID}} {{.Names}} '*) print -l 'a1b2c3d4e5f6 example-container' 'f6e5d4c3b2a1 stopped-db' ;;
        *' ps --format {{.ID}} '*) print -l a1b2c3d4e5f6 ;;
        *' ps '*) print -l example-container ;;
        *' images '*) print -l alpine:latest ;;
        *' network ls '*) print -l example-network ;;
        *' volume ls '*) print -l example-volume ;;
    esac
}
docker-compose()
{
    [[ ${COMPOSE_TEST_FAIL:-} != yes ]] || return 1
    if [[ -n ${COMPOSE_TEST_FILE:-} ]]; then
        [[ $1 == -f && $2 == $COMPOSE_TEST_FILE ]] || return 1
        shift 2
    fi
    if [[ -n ${COMPOSE_TEST_ARGS:-} ]]; then
        [[ "$*" == $COMPOSE_TEST_ARGS ]] || return 1
    fi
    case "${@[-2]} ${@[-1]}" in
        'config --services') print -l web worker db ;;
        'config --profiles') print -l development debug production ;;
        *) return 1 ;;
    esac
}
tmux()
{
    # Only these read-only queries are allowed; others may start a tmux server.
    if [[ -n ${TMUX_TEST_SOCKET:-} ]]; then
        [[ "$1 $2" == "-S $TMUX_TEST_SOCKET" ]] || return 1
        shift 2
    fi
    case "$*" in
        'list-sessions -F #{session_name}') print -l work db ;;
        'list-windows -a -F #{session_name}:#{window_index}') print -l work:0 work:1 ;;
        'list-panes -a -F #{session_name}:#{window_index}.#{pane_index}') print -l work:1.0 work:1.1 ;;
        'list-panes -a -F #{pane_id}') print -l %0 %1 ;;
        'list-buffers -F #{buffer_name}') print -l buffer0 ;;
        'list-keys -F #{key_table}') print -l root prefix copy-mode-vi ;;
        'show-options -g') print -l 'mouse off' 'status-left "[#S] "' 'update-environment[0] DISPLAY' ;;
        'show-hooks -g') print -l pane-died 'after-new-session[0] run-shell true' ;;
        'show-options -s'|'show-options -gw'|'show-hooks -gw') ;;
        *) print UNEXPECTED_TMUX_QUERY ;;
    esac
}
git()
{
    # Only these read-only local queries are allowed; nothing may contact a remote.
    if [[ -n ${GIT_TEST_DIR:-} ]]; then
        [[ "$1 $2" == "-C $GIT_TEST_DIR" ]] || return 1
        shift 2
    fi
    case "$*" in
        'config --get-regexp ^alias\.') print -l 'alias.lg log --oneline' ;;
        'for-each-ref --format=%(refname:short) refs/heads refs/tags refs/remotes') print -l main dev v1.0 origin/main origin/feature ;;
        'for-each-ref --format=%(refname:strip=3) refs/remotes') print -l HEAD main feature ;;
        'for-each-ref --format=%(refname:short) refs/heads') print -l main dev ;;
        'for-each-ref --format=%(refname:short) refs/tags') print -l v1.0 ;;
        'for-each-ref --format=%(refname:short) refs/remotes') print -l origin/main origin/feature ;;
        'for-each-ref --format=%(refname) refs/remotes/origin') print -l refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/feature ;;
        'remote') print -l origin ;;
        'stash list --format=%gd') print -l 'stash@{0}' ;;
        'config --name-only --list') print -l user.name ;;
        'ls-files -z --exclude-standard --modified --others --deleted --directory --no-empty-directory') printf '%s\0' 'new file.txt' changed.txt untracked/ ;;
        'ls-files -z --modified --deleted') printf '%s\0' changed.txt ;;
        'diff --cached --name-only --relative -z') printf '%s\0' staged.txt ;;
        'push --git-completion-helper') print -l '--force-with-lease --tags --repo=' ;;
        *' --git-completion-helper') return 129 ;;
        *) print UNEXPECTED_GIT_QUERY ;;
    esac
}
# --complete-args answers like nmcli 1.18+; TEST_NMCLI_OLD mimics nmcli 1.2.
nmcli()
{
    local last previous= candidate
    if [[ $1 == --complete-args ]]; then
        [[ ${TEST_NMCLI_OLD:-} == yes ]] && { print -u2 "Error: Option '-complete-args' is unknown"; return 2; }
        shift
        last=${@[-1]}
        (( $# < 2 )) || previous=${@[-2]}
        [[ $previous == file ]] && return 65
        {
            if (( $# == 1 )); then
                case $last in
                    -*) print -l -- --terse --pretty --mode --colors ;;
                    *) print -l general networking radio connection device agent monitor help ;;
                esac
            else
                case $previous in
                    id|up|mod) print -l 'Wired connection 1' "it's mine" 'vpn:office' 'ops@site' ;;
                    cloned-mac-address) print -l '00:11:22:33:44:55' ;;
                    lo) print -l ipv4.method ipv4.may-fail ;;
                    con|connection) print -l show up down modify ;;
                    *) print UNEXPECTED_NMCLI_QUERY ;;
                esac
            fi
        } | while IFS= read -r candidate; do [[ $candidate != ${last}* ]] || print -r -- $candidate; done
        return 0
    fi
    case "$*" in
        '-t -f NAME connection show') print -l 'Wired connection 1' 'vpn\:office' ;;
        '-t -f DEVICE device status') print -l eth0 wlan0 lo ;;
        *) print UNEXPECTED_NMCLI_QUERY; return 1 ;;
    esac
}
# sshfs 3.x help lines plus a 2.x-style "-d   -o debug".
sshfs()
{
    [[ $1 == -h ]] || { print UNEXPECTED_SSHFS_CALL; return 1; }
    [[ ${TEST_SSHFS_FAIL:-} != yes ]] || return 1
    print -l 'usage: sshfs [user@]host:[dir] mountpoint [options]' \
        '    -o opt,[opt...]        mount options' '    -o reconnect           reconnect to server' \
        '    -o dir_cache=BOOL      enable caching' '    -o dcache_{stat,link,dir}_timeout=N' \
        '    -o workaround=LIST     colon separated list of workarounds' '    -o idmap=TYPE          user/group ID mapping' \
        '    -o SSHOPT=VAL          ssh options' '    -o [no]auto_cache      enable caching' \
        '    -o allow_other         allow access by all users' '    -d   -o debug          enable debug output'
}
# LVM help text in the 2.03 --longhelp layout; only read-only reports are allowed.
lvm()
{
    case "$*" in
        lvcreate\ --longhelp)
            printf '  lvcreate - Create a logical volume\n\n'
            printf '  lvcreate -L|--size Size[m|UNIT] VG\n\t[ --type linear ] (implied)\n\t[ -l|--extents Number[PERCENT] ]\n\t[ PV ... ]\n'
            printf '  lvcreate --type thin-pool -L|--size Size[m|UNIT] VG\n'
            printf '  lvcreate -L|--size Size[m|UNIT] -s|--snapshot LV\n'
            printf '  lvcreate --thinpool LV_new -L|--size Size[m|UNIT] VG\n'
            printf '  lvcreate --thinpool LV -V|--virtualsize Size[m|UNIT] VG\n'
            printf '\t[ -a|--activate y|n|ay ]\n\t[ -n|--name String ]\n\t[ -r|--readahead auto|none|Number ]\n'
            printf '\t[    --alloc contiguous|cling|normal ]\n\t[ -y|--yes ]\n' ;;
        lvextend\ --longhelp)
            printf '  lvextend -L|--size [+]Size[m|UNIT] LV\n  lvextend LV PV ...\n\t[ -r|--resizefs ]\n\t[ -l|--extents [+]Number[PERCENT] ]\n' ;;
        lvs\ --longhelp)
            printf '  lvs\n\t[ -a|--all ]\n\t[ -o|--options String ]\n\t[    --units r|R|h|H|b|B|s|S|k|K|m|M|g|G|t|T|p|P|e|E ]\n' ;;
        vgchange\ --longhelp) printf '  vgchange -a|--activate y|n|ay\n\t[ -A|--autobackup y|n ]\n' ;;
        vgcreate\ --longhelp) printf '  vgcreate VG_new PV ...\n\t[ -s|--physicalextentsize Size[m|UNIT] ]\n' ;;
        vgcfgrestore\ --longhelp) printf '  vgcfgrestore -f|--file String VG\n' ;;
        *\ --longhelp) printf '  %s\n\t[ -y|--yes ]\n' "$1" ;;
        'vgs --noheadings -o vg_name') printf '  vg0\n  backup\n' ;;
        'lvs --noheadings -o vg_name,lv_name') printf '  vg0 root\n  vg0 data\n' ;;
        'lvs --noheadings -o lv_name vg0') printf '  root\n  data\n' ;;
        'pvs --noheadings -o pv_name') printf '  /dev/sdb\n' ;;
        'lvs -o help') printf '    lv_name   - Name.\n    devices   - Devices.\n' >&2 ;;
        *) print UNEXPECTED_LVM_QUERY ;;
    esac
}
_mini_lvm_disks() { print /dev/vdc; }
ps() { print -l '    1' '  42' ' 4242'; }
