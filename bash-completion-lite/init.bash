# Lightweight, user-owned Bash completion bootstrap.
# Source this file from ~/.bashrc. Do not execute it directly.

# Only interactive shells need programmable completion.
case $- in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

shopt -s progcomp 2>/dev/null || true

_MINI_BC_DEFAULT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion"
_MINI_BC_ROOT="${MINI_BASH_COMPLETION_ROOT:-$_MINI_BC_DEFAULT_ROOT}"
_MINI_BC_COMPLETIONS="$_MINI_BC_ROOT/completions"

_mini_bc_source_all()
{
    local completion_file

    [ -d "$_MINI_BC_COMPLETIONS" ] || return 0

    for completion_file in "$_MINI_BC_COMPLETIONS"/*; do
        [ -f "$completion_file" ] || continue
        [ -r "$completion_file" ] || continue
        source "$completion_file"
    done
}

_mini_completion_loader()
{
    local invoked_command="$1"
    local command_name="${invoked_command##*/}"
    local completion_file

    [ -n "$command_name" ] || return 1

    # Prefer the modern *.bash form, but accept common legacy names too.
    for completion_file in \
        "$_MINI_BC_COMPLETIONS/$command_name.bash" \
        "$_MINI_BC_COMPLETIONS/$command_name" \
        "$_MINI_BC_COMPLETIONS/_$command_name" \
        "$_MINI_BC_COMPLETIONS/$command_name-completion.sh"
    do
        [ -f "$completion_file" ] || continue
        [ -r "$completion_file" ] || continue

        source "$completion_file"

        # Status 124 asks Bash to retry after the file registered a compspec.
        if complete -p "$invoked_command" >/dev/null 2>&1 ||
           complete -p "$command_name" >/dev/null 2>&1
        then
            return 124
        fi

        return 1
    done

    return 1
}

_mini_bc_root_is_visible_to_official_loader()
{
    local configured_roots
    local root
    local old_ifs

    # With no override, bash-completion uses the same XDG default as us.
    if [ -z "${BASH_COMPLETION_USER_DIR:-}" ]; then
        [ "$_MINI_BC_ROOT" = "$_MINI_BC_DEFAULT_ROOT" ]
        return
    fi

    # New bash-completion releases allow colon-separated user roots.
    configured_roots="$BASH_COMPLETION_USER_DIR"
    old_ifs=$IFS
    IFS=:
    for root in $configured_roots; do
        if [ "$root" = "$_MINI_BC_ROOT" ]; then
            IFS=$old_ifs
            return 0
        fi
    done
    IFS=$old_ifs
    return 1
}

_mini_bc_try_load_official()
{
    local entrypoint

    [ -n "${BASH_COMPLETION_VERSINFO+x}" ] && return 0

    # Common Linux installation locations. A distro profile may already have
    # sourced one of these; the version-variable guard avoids double loading.
    for entrypoint in \
        /usr/share/bash-completion/bash_completion \
        /etc/bash_completion
    do
        if [ -r "$entrypoint" ]; then
            source "$entrypoint"
            [ -n "${BASH_COMPLETION_VERSINFO+x}" ] && return 0
        fi
    done

    return 1
}

if _mini_bc_try_load_official; then
    # The official loader already searches the standard user directory. If a
    # custom root is not visible to it, load only our files eagerly rather than
    # replacing its default loader.
    _mini_bc_root_is_visible_to_official_loader || _mini_bc_source_all
elif complete -p -D >/dev/null 2>&1; then
    # Another framework owns the default completion. Preserve it and eagerly
    # register only the completions shipped in our directory.
    _mini_bc_source_all
elif complete -D -F _mini_completion_loader \
        -o bashdefault -o default 2>/dev/null
then
    # Our on-demand loader is now active.
    :
else
    # Bash versions without `complete -D` fall back to eager loading.
    _mini_bc_source_all
fi

unset -f _mini_bc_try_load_official
unset -f _mini_bc_root_is_visible_to_official_loader
unset -f _mini_bc_source_all
unset _MINI_BC_DEFAULT_ROOT

