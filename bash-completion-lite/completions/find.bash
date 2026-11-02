_mini_find_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words candidate
    COMPREPLY=()
    case "$previous" in
        -exec|-execdir|-ok|-okdir)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -c -- "$current")
            return ;;
        -type|-xtype) words='b c d p f l s' ;;
        -name|-iname|-path|-ipath|-regex|-iregex|-printf|-fprintf|-size|-mtime|-mmin|-atime|-amin|-ctime|-cmin|-maxdepth|-mindepth|-perm|-uid|-gid|-inum|-links) return ;;
        -user) words="$(compgen -u)" ;;
        -group) words="$(compgen -g)" ;;
        -newer|-anewer|-cnewer|-samefile|-fprint|-fprint0|-fls) words= ;;
        *)
            case "$current" in
                -*) words='-H -L -P -O -D -name -iname -path -ipath -regex -iregex -type -xtype -size -mtime -mmin -atime -amin -ctime -cmin -newer -user -group -uid -gid -perm -empty -executable -readable -writable -maxdepth -mindepth -mount -xdev -depth -prune -print -print0 -printf -fprint -fprint0 -ls -delete -exec -execdir -ok -okdir -quit -a -o -not' ;;
            esac ;;
    esac
    if [ -n "$words" ]; then
        COMPREPLY=( $(compgen -W "$words" -- "$current") )
    else
        while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
}
complete -o bashdefault -o default -F _mini_find_completion find
