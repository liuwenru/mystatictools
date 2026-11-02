_mini_kill_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}"
    local pids

    # After options such as -9, complete the current process IDs.
    pids="$(ps -e -o pid= 2>/dev/null)"
    COMPREPLY=( $(compgen -W "$pids" -- "$current") )
}

complete -F _mini_kill_completion kill

