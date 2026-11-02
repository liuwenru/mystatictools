_mini_nslookup_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" prefix= value candidate host aliases
    value="$current"
    local types='A AAAA ANY CNAME MX NS PTR SOA SRV TXT'
    COMPREPLY=()
    # Bash normally treats '=' as a separate word during completion.
    case "$current" in
        -type=*|-query=*|-querytype=*) prefix="${current%%=*}="; value="${current#*=}" ;;
        *)
            if [ "${COMP_WORDS[COMP_CWORD-1]}" = '=' ] && (( COMP_CWORD >= 2 )); then
                case "${COMP_WORDS[COMP_CWORD-2]}" in -type|-query|-querytype) prefix=' ' ;; esac
            elif [ "$current" = '=' ]; then
                case "${COMP_WORDS[COMP_CWORD-1]}" in -type|-query|-querytype) prefix=' '; value= ;; esac
            fi ;;
    esac
    if [ -n "$prefix" ]; then
        [ "$prefix" != ' ' ] || prefix=
        for candidate in $types; do [[ "$candidate" == "$value"* ]] && COMPREPLY+=("$prefix$candidate"); done
    elif [[ "$current" == -* ]]; then
        COMPREPLY=( $(compgen -W '-type= -query= -querytype= -class= -timeout= -retry= -port= -debug -nodebug -recurse -norecurse -vc -novc -search -nosearch -domain= -version' -- "$current") )
        case "${COMPREPLY[*]}" in *=) compopt -o nospace 2>/dev/null || true ;; esac
    elif [ -r /etc/hosts ]; then
        while read -r host aliases; do
            [[ "$host" == \#* ]] && continue
            for candidate in $aliases; do
                [[ "$candidate" == \#* ]] && break
                [[ "$candidate" == "$current"* ]] && COMPREPLY+=("$candidate")
            done
        done < /etc/hosts
    fi
}
complete -F _mini_nslookup_completion nslookup
