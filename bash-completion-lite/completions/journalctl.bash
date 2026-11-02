_mini_journalctl_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words candidate word
    local -a scope=()
    COMPREPLY=()
    for word in "${COMP_WORDS[@]:1:COMP_CWORD-1}"; do
        case "$word" in --user) scope=(--user) ;; -M|--machine|--machine=*) return ;; esac
    done
    case "$previous" in
        -u|--unit|--user-unit)
            [ "$previous" != --user-unit ] || scope=(--user)
            words="$(systemctl "${scope[@]}" list-unit-files --no-legend --no-pager 2>/dev/null | awk '{print $1}')" ;;
        -p|--priority) words='emerg alert crit err warning notice info debug 0 1 2 3 4 5 6 7' ;;
        -o|--output) words='short short-full short-iso short-iso-precise short-precise short-monotonic short-unix verbose export json json-pretty json-sse cat' ;;
        -b|--boot) words="$(journalctl --list-boots --no-pager 2>/dev/null | awk '{print $1}')" ;;
        -F|--field) words='_SYSTEMD_UNIT _SYSTEMD_USER_UNIT _PID _UID _GID _COMM _EXE _HOSTNAME SYSLOG_IDENTIFIER PRIORITY' ;;
        -D|--directory|--root)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -d -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
        --file)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
        -n|--lines|-S|--since|-U|--until|-g|--grep|-t|--identifier|--cursor|--after-cursor|--vacuum-size|--vacuum-time|--vacuum-files) return ;;
        *) words='-u --unit --user-unit --user --system -f --follow -e --pager-end -n --lines -b --boot -k --dmesg -p --priority -o --output -S --since -U --until -r --reverse -a --all -q --quiet --no-pager --no-hostname --utc --list-boots --disk-usage --verify --rotate --sync --vacuum-size --vacuum-time --vacuum-files -t --identifier -g --grep -F --field -D --directory --file --help --version' ;;
    esac
    COMPREPLY=( $(compgen -W "$words" -- "$current") )
}
complete -F _mini_journalctl_completion journalctl
