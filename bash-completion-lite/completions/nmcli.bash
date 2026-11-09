# nmcli: candidates come from `nmcli --complete-args`, the same interface the
# NetworkManager completion uses, so commands, connection/device names,
# properties and property values follow the local nmcli version. Unlike that
# script this file does not need the bash-completion package: it splits the
# command line itself (quotes, backslashes, ':' and '=' kept in one word) and
# escapes the candidates for the quoting in use.
#
# nmcli without --complete-args (NetworkManager 1.2 and older): use the system
# nmcli completion when bash-completion is loaded, otherwise a small built-in
# list of objects, subcommands, options, connection and device names.
# Set MINI_NMCLI_OFFICIAL_COMPLETION to a space-separated list of files to
# search, or to an empty value to disable the system script.

if declare -F _init_completion >/dev/null; then
    for _mini_nmcli_file in ${MINI_NMCLI_OFFICIAL_COMPLETION-/usr/share/bash-completion/completions/nmcli /etc/bash_completion.d/nmcli}; do
        [ -r "$_mini_nmcli_file" ] || continue
        source "$_mini_nmcli_file"
        declare -F _nmcli >/dev/null && break
    done
    unset _mini_nmcli_file
fi

# Run the typed nmcli (e.g. ./nmcli) with a time limit when possible.
_mini_nmcli_run()
{
    if command -v timeout >/dev/null 2>&1; then
        timeout -k 1 2 "$_mini_nmcli_bin" "$@"
    else
        "$_mini_nmcli_bin" "$@"
    fi
}

# Split $1, the command line up to the cursor, the way the shell does.
# Sets _mini_nmcli_words (unquoted words; the last one is being completed),
# _mini_nmcli_quote (quote character still open in the last word) and
# _mini_nmcli_keep (leading characters of the last word that readline does not
# replace: up to an open quote or the last COMP_WORDBREAKS character).
_mini_nmcli_split()
{
    local line="$1" c q= word= inword= i
    _mini_nmcli_words=()
    _mini_nmcli_keep=0
    for ((i = 0; i < ${#line}; i++)); do
        c="${line:i:1}"
        if [ -n "$q" ]; then
            if [ "$c" = "$q" ]; then
                q=
            elif [ "$q" = '"' ] && [ "$c" = '\' ] && [[ "${line:i+1:1}" == [\"\\\$\`] ]]; then
                i=$((i + 1))
                word+="${line:i:1}"
            else
                word+="$c"
            fi
            continue
        fi
        case "$c" in
            [[:space:]])
                [ -z "$inword" ] || _mini_nmcli_words+=("$word")
                word= inword= _mini_nmcli_keep=0 ;;
            \'|\")
                q="$c" inword=1 _mini_nmcli_keep=${#word} ;;
            \\)
                i=$((i + 1))
                word+="${line:i:1}" inword=1 ;;
            *)
                word+="$c" inword=1
                # Readline keeps '@' and '$' in the replaced text.
                case "${COMP_WORDBREAKS-}" in
                    *"$c"*) _mini_nmcli_keep=${#word}; [[ "$c" != [@\$] ]] || _mini_nmcli_keep=$((_mini_nmcli_keep - 1)) ;;
                esac ;;
        esac
    done
    _mini_nmcli_words+=("$word")
    _mini_nmcli_quote="$q"
}

# Fallback for nmcli without --complete-args.
_mini_nmcli_fallback()
{
    local current="$1" previous=$2 word object= action= i=1
    local options='-t --terse -p --pretty -m --mode -c --colors -f --fields -g --get-values -e --escape -a --ask -s --show-secrets -w --wait -v --version -h --help'
    local words=

    case "$previous" in
        -m|--mode) words='tabular multiline' ;;
        -c|--colors) words='yes no auto' ;;
        -e|--escape) words='yes no' ;;
        -f|--fields|-g|--get-values|-w|--wait) return 0 ;;
        file) compopt -o default 2>/dev/null; return 0 ;;
    esac

    if [ -z "$words" ]; then
        # Words before the cursor, skipping global options and their values.
        while ((i < ${#_mini_nmcli_words[@]} - 1)); do
            word="${_mini_nmcli_words[i]}"
            i=$((i + 1))
            if [ -z "$object" ]; then
                case "$word" in
                    -m|--mode|-c|--colors|-f|--fields|-g|--get-values|-e|--escape|-w|--wait) i=$((i + 1)); continue ;;
                    -*) continue ;;
                esac
                object="$word"
            elif [ -z "$action" ]; then
                action="$word"
            fi
        done

        case "$object" in
            '') [[ "$current" == -* ]] && words="$options" ||
                    words='general networking radio connection device agent monitor help' ;;
            g*) [ -n "$action" ] || words='status hostname permissions logging' ;;
            n*) [ -n "$action" ] || words='on off connectivity' ;;
            r*) if [ -z "$action" ]; then words='all wifi wwan'; else words='on off'; fi ;;
            a*) [ -n "$action" ] || words='secret polkit all' ;;
            c*)
                case "$action" in
                    '') words='show up down add modify clone edit delete monitor reload load import export' ;;
                    s*|u*|do*|m*|c*|e*|de*)
                        if [ "$previous" = ifname ]; then
                            words=$(_mini_nmcli_run -t -f DEVICE device status 2>/dev/null)
                        else
                            words="id"$'\n'"uuid"$'\n'"path"$'\n'"apath"$'\n'
                            words+=$(_mini_nmcli_run -t -f NAME connection show 2>/dev/null)
                        fi ;;
                    i*) words='type file' ;;
                    l*) compopt -o default 2>/dev/null; return 0 ;;
                esac ;;
            d*)
                case "$action" in
                    '') words='status show set connect reapply modify disconnect delete monitor wifi lldp' ;;
                    w*|l*) ;;
                    *) words=$(_mini_nmcli_run -t -f DEVICE device status 2>/dev/null) ;;
                esac ;;
        esac
    fi

    # Fixed lists are space-separated; names from nmcli -t come one per line
    # with ':' escaped as '\:'.
    case "$words" in *$'\n'*) ;; *) words="${words// /$'\n'}" ;; esac
    while IFS= read -r word; do
        _mini_nmcli_add "${word//\\:/:}" "$current"
    done <<< "$words"
}

# Append candidate $1 if it starts with $2, escaped for the open quote.
_mini_nmcli_add()
{
    local candidate="$1" reply= c i
    [ -n "$candidate" ] || return 0
    [ "${candidate:0:${#2}}" = "$2" ] || return 0
    candidate="${candidate:_mini_nmcli_keep}"
    case "$_mini_nmcli_quote" in
        \')
            # Replacement in a variable: Bash 4.2 keeps the backslashes of a
            # literal replacement inside double quotes.
            c="'\\''"
            reply="${candidate//\'/$c}" ;;
        \")
            reply="${candidate//\\/\\\\}"
            reply="${reply//\"/\\\"}"
            reply="${reply//\$/\\\$}"
            reply="${reply//\`/\\\`}" ;;
        *)
            # Escape only characters the shell treats specially; keep ',', ':'
            # and '=' readable (printf %q would escape ',').
            for ((i = 0; i < ${#candidate}; i++)); do
                c="${candidate:i:1}"
                case "$c" in
                    [[:space:]\'\"\\\$\`\&\;\|\<\>\(\)\*\?\[\]\#\~\!\{\}]) reply+="\\$c" ;;
                    *) reply+="$c" ;;
                esac
            done ;;
    esac
    COMPREPLY+=("$reply")
}

_mini_nmcli_completion()
{
    local _mini_nmcli_bin="${COMP_WORDS[0]}" _mini_nmcli_quote= _mini_nmcli_keep=0
    local -a _mini_nmcli_words=()
    local line output status current candidate i
    COMPREPLY=()

    line="${COMP_LINE:0:${COMP_POINT:-${#COMP_LINE}}}"
    _mini_nmcli_split "$line"
    if [ "${_mini_nmcli_words[0]-}" != "$_mini_nmcli_bin" ]; then
        # The line does not start with this command (e.g. a wrapper changed
        # COMP_LINE); use Bash's own words instead.
        _mini_nmcli_words=("${COMP_WORDS[@]:0:COMP_CWORD+1}")
        _mini_nmcli_quote= _mini_nmcli_keep=0
    fi
    current="${_mini_nmcli_words[${#_mini_nmcli_words[@]}-1]}"

    output=$(_mini_nmcli_run --complete-args "${_mini_nmcli_words[@]:1}" 2>/dev/null)
    status=$?
    case "$status" in
        0)
            # nmcli 1.18 and older print nothing for a file argument.
            if [ -z "$output" ] && ((${#_mini_nmcli_words[@]} >= 3)) &&
               [ "${_mini_nmcli_words[${#_mini_nmcli_words[@]}-2]}" = file ]; then
                compopt -o default 2>/dev/null
                return 0
            fi
            while IFS= read -r candidate; do
                _mini_nmcli_add "$candidate" "$current"
            done <<< "$output" ;;
        65)
            # nmcli asks for a file name here.
            compopt -o default 2>/dev/null ;;
        124|137) ;;
        *)
            # --complete-args is not supported.
            if declare -F _nmcli >/dev/null && declare -F _init_completion >/dev/null; then
                _nmcli "$@"
                return
            fi
            i=$((${#_mini_nmcli_words[@]} - 2))
            _mini_nmcli_fallback "$current" "${_mini_nmcli_words[i]-}" ;;
    esac
    return 0
}

complete -F _mini_nmcli_completion nmcli
