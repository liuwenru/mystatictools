_mini_systemctl_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words command= word i
    local -a scope=()
    COMPREPLY=()
    for ((i=1; i<COMP_CWORD; i++)); do
        word="${COMP_WORDS[i]}"
        case "$word" in --user) scope=(--user) ;; --system) scope=(--system) ;; -H|--host|-M|--machine|--host=*|--machine=*) return ;; esac
    done
    case "$previous" in
        -t|--type) words='service socket target timer mount automount swap path slice scope device' ;;
        --state) words='active inactive failed activating deactivating enabled disabled masked static running exited dead' ;;
        -p|--property|-n|--lines|-H|--host|-M|--machine|--root|--image|--job-mode) return ;;
        *)
            case "$current" in
                -*) words='--user --system --all --failed --full --no-pager --no-legend --plain --quiet --now --force --runtime --no-block --no-reload --type --state --property --lines --help --version' ;;
                *)
                    for ((i=1; i<COMP_CWORD; i++)); do
                        case "${COMP_WORDS[i]}" in
                            start|stop|restart|reload|reload-or-restart|try-restart|status|show|cat|enable|disable|reenable|is-active|is-enabled|is-failed|mask|unmask|preset|edit|reset-failed|list-units|list-unit-files|list-timers|list-sockets|list-dependencies|daemon-reload|daemon-reexec|set-default|get-default|isolate|reboot|poweroff|halt|suspend) command="${COMP_WORDS[i]}"; break ;;
                        esac
                    done
                    if [ -z "$command" ]; then
                        words='start stop restart reload reload-or-restart try-restart status show cat enable disable reenable is-active is-enabled is-failed mask unmask preset edit reset-failed list-units list-unit-files list-timers list-sockets list-dependencies daemon-reload daemon-reexec set-default get-default isolate reboot poweroff halt suspend'
                    else
                        case "$command" in
                            daemon-*|get-default|reboot|poweroff|halt|suspend) return ;;
                            *) words="$(systemctl "${scope[@]}" list-unit-files --no-legend --no-pager 2>/dev/null | awk '{print $1}'; systemctl "${scope[@]}" list-units --all --plain --no-legend --no-pager 2>/dev/null | awk '{print $1}')" ;;
                        esac
                    fi ;;
            esac ;;
    esac
    COMPREPLY=( $(compgen -W "$words" -- "$current") )
}
complete -F _mini_systemctl_completion systemctl
