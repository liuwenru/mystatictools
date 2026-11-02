_mini_tar_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" candidate words expect= literal= prefix= word flags char i j
    local -a paths=()
    COMPREPLY=()
    # Track option arguments without opening archives or running compressors.
    for ((i=1; i<COMP_CWORD; i++)); do
        word="${COMP_WORDS[i]}"
        if [ -n "$expect" ]; then
            [ "$word" != '=' ] || continue
            expect=; continue
        fi
        [ -z "$literal" ] || continue
        case "$word" in
            --) literal=yes; continue ;;
            --file|--directory|--files-from|--exclude-from|--listed-incremental|--format|--quoting-style|--warning|--use-compress-program|--to-command|--exclude|--transform|--strip-components|--owner|--group|--mode|--mtime|--checkpoint|--checkpoint-action|--blocking-factor|--record-size|--label|--starting-file)
                expect="$word"; continue ;;
            --*) continue ;;
            -*) flags="${word#-}" ;;
            *)
                # Traditional no-dash option clusters are valid only as argv[1].
                if (( i == 1 )) && [[ "$word" =~ ^[AcdrtuxabfhjklmopvwzBCGJLOPSUXZ]+$ ]]; then flags="$word"; else continue; fi ;;
        esac
        for ((j=0; j<${#flags}; j++)); do
            char="${flags:j:1}"
            case "$char" in
                f|C|T|X|g|H|I|F|K|L|N|V|b)
                    # In dashed clusters, the rest is an attached argument.
                    # Traditional clusters take arguments from following words.
                    if [[ "$word" != -* ]] || (( j+1 == ${#flags} )); then expect="-$char"; fi
                    break ;;
            esac
        done
    done
    if [ -z "$literal" ]; then
        case "$current" in
            --*=*) expect="${current%%=*}"; prefix="$expect="; current="${current#*=}" ;;
            '=') [ -z "$expect" ] || current= ;;
        esac
    fi
    case "$expect" in
        -C|--directory) paths=(-d) ;;
        -f|--file|-T|--files-from|-X|--exclude-from|-g|--listed-incremental) paths=(-f) ;;
        -H|--format) words='gnu oldgnu pax posix ustar v7' ;;
        --quoting-style) words='literal shell shell-always shell-escape shell-escape-always c c-maybe escape locale clocale' ;;
        --warning) words='all none filename-with-nuls file-changed file-ignored file-removed file-shrank unknown-keyword' ;;
        -I|--use-compress-program)
            while IFS= read -r candidate; do COMPREPLY+=("$prefix$candidate"); done < <(compgen -c -- "$current")
            return ;;
        '')
            if [ -z "$literal" ] && [[ "$current" == -* ]]; then
                words='-c -x -t -r -u -A -d -f -C -v -p -h -k -m -O -P -T -X -z -j -J -Z -a -I -g -H -b -cf -cvf -czf -czvf -cjf -cJf -xf -xvf -xzf -xzvf -xjf -xJf -tf -tvf -tzf --create --extract --list --append --update --concatenate --diff --file --directory --verbose --gzip --bzip2 --xz --zstd --lzma --lzop --compress --auto-compress --use-compress-program --files-from --exclude --exclude-from --exclude-vcs --exclude-caches --wildcards --no-wildcards --null --no-recursion --one-file-system --strip-components --transform --format --listed-incremental --numeric-owner --same-owner --no-same-owner --same-permissions --no-same-permissions --acls --xattrs --selinux --sparse --keep-old-files --skip-old-files --overwrite --touch --to-stdout --to-command --absolute-names --warning --quoting-style --checkpoint --checkpoint-action --owner --group --mode --mtime --blocking-factor --record-size --label --starting-file --help --version'
            else
                if [ -z "$literal" ] && (( COMP_CWORD == 1 )); then
                    words='cf cvf czf czvf cjf cJf xf xvf xzf xzvf xjf xJf tf tvf tzf'
                fi
                paths=(-f)
            fi ;;
        *) return 0 ;;
    esac
    if [ -n "$words" ]; then
        while IFS= read -r candidate; do COMPREPLY+=("$prefix$candidate"); done < <(compgen -W "$words" -- "$current")
    fi
    if [ "${#paths[@]}" -gt 0 ]; then
        while IFS= read -r candidate; do COMPREPLY+=("$prefix$candidate"); done < <(compgen "${paths[@]}" -- "$current")
        compopt -o filenames 2>/dev/null || true
    fi
}
complete -F _mini_tar_completion tar
