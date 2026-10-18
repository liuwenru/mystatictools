_mini_docker_compose_completion()
{
    local line="${COMP_LINE:0:COMP_POINT}" current token= quote= escaped= active= char
    local command= expect= option= prefix= mode=services words candidate output literal= query=yes positions=0 trim= i
    local -a arguments=() global_args=()
    COMPREPLY=()
    # Decode shell quoting without eval, preserving paths containing spaces and '='.
    for ((i=0; i<${#line}; i++)); do
        char="${line:i:1}"
        if [ -n "$escaped" ]; then
            if [ "$quote" = '"' ]; then
                case "$char" in '"'|'$'|'`'|'\') ;; *) token="$token\\" ;; esac
            fi
            token="$token$char"; escaped=; active=yes; continue
        fi
        case "$quote" in
            "'") if [ "$char" = "'" ]; then quote=; else token="$token$char"; fi ;;
            '"') case "$char" in '"') quote= ;; '\') escaped=yes ;; *) token="$token$char" ;; esac ;;
            *) case "$char" in
                '\') escaped=yes; active=yes ;;
                "'"|'"') quote="$char"; active=yes ;;
                ' '|$'\t'|$'\n')
                    [ -z "$active" ] || arguments+=("$token")
                    token=; active=; trim= ;;
                '=')
                    if [[ "$COMP_WORDBREAKS" == *'='* ]]; then trim="$token="; fi
                    token="$token$char"; active=yes ;;
                *) token="$token$char"; active=yes ;;
            esac ;;
        esac
    done
    arguments+=("$token")
    current="$token"
    for ((i=1; i<${#arguments[@]}-1; i++)); do
        token="${arguments[i]}"
        if [ -n "$expect" ]; then
            if [ -z "$command" ]; then global_args+=("$expect" "$token"); fi
            case "$expect:$token" in -f:-|--file:-|--file:*://*|-f:*://*) query=no ;; esac
            expect=; continue
        fi
        if [ -n "$literal" ]; then positions=$((positions + 1)); continue; fi
        case "$token" in
            --) literal=yes; continue ;;
            --file|--project-name|--project-directory|--env-file|--profile|--ansi|--progress|--parallel|--host|--context)
                expect="$token"; continue ;;
            -f)
                if [ -z "$command" ]; then expect=-f; fi
                continue ;;
            -p)
                if [ -z "$command" ]; then expect=-p; else expect=--publish; fi
                continue ;;
            -f?*|-p?*)
                if [ -z "$command" ]; then
                    option="${token:0:2}"; token="${token:2}"
                    global_args+=("$option" "$token")
                    case "$option:$token" in -f:-|-f:*://*) query=no ;; esac
                fi
                continue ;;
            --*=*)
                if [ -z "$command" ]; then global_args+=("$token"); fi
                case "$token" in --file=-|--file=*://*) query=no ;; esac
                continue ;;
            --compatibility|--verbose|--no-ansi|--dry-run|--tls|--tlsverify)
                [ -n "$command" ] || global_args+=("$token")
                continue ;;
            --env|--user|--workdir|--index|--tail|--since|--until|--timeout|--scale|--exit-code-from|--attach|--no-attach|--pull|--policy|--format|--output|--env-from-file|--build-arg|--memory|--stop-signal|--detach-keys|--protocol|-e|-u|-w)
                expect="$token"; continue ;;
            --name|--entrypoint|--volume|--wait-timeout|--rmi|--status|--filter|--signal)
                expect="$token"; continue ;;
            -v) if [ "$command" = run ]; then expect=--volume; fi; continue ;;
            -t)
                case "$command" in stop|restart|down|up) expect=--timeout ;; esac
                continue ;;
            -*) continue ;;
        esac
        if [ -z "$command" ]; then command="$token"; else positions=$((positions + 1)); fi
    done
    # Do not suggest Compose services/options inside the container command.
    case "$command" in exec|run) (( positions == 0 )) || return 0 ;; esac
    option="$expect"
    if [ -z "$literal" ]; then
        case "$current" in
            --*=*)
                option="${current%%=*}"; prefix="$option="; current="${current#*=}" ;;
            -f?*|-p?*)
                if [ -z "$command" ]; then option="${current:0:2}"; prefix="$option"; current="${current:2}"; fi ;;
        esac
    fi
    case "$option" in
        -f|--file|--env-file|--env-from-file|--output) mode=files ;;
        --project-directory) mode=directories ;;
        --ansi) words='auto never always'; mode=words ;;
        --progress) words='auto tty plain json quiet'; mode=words ;;
        --pull) words='always missing never'; mode=words ;;
        --policy) words='always missing'; mode=words ;;
        --rmi) words='all local'; mode=words ;;
        --profile) mode=profiles ;;
        --exit-code-from|--attach|--no-attach) mode=services ;;
        '')
            if [ -z "$literal" ] && [[ "$current" == -* ]]; then
                mode=words
                case "$command" in
                    '') words='-f --file -p --project-name --project-directory --env-file --profile --compatibility --ansi --progress --parallel --dry-run --verbose --no-ansi --help --version' ;;
                    up) words='-d --detach --build --no-build --force-recreate --no-recreate --no-deps --remove-orphans --renew-anon-volumes --abort-on-container-exit --exit-code-from --scale --timeout --pull --wait --wait-timeout --attach --no-attach --help' ;;
                    down) words='-v --volumes --remove-orphans --rmi --timeout --help' ;;
                    exec) words='-d --detach -e --env --index --privileged -T --no-TTY -u --user -w --workdir --help' ;;
                    run) words='-d --detach --rm --no-deps --build --pull --name --entrypoint -e --env --env-from-file -p --publish -P --service-ports -T --no-TTY -u --user -w --workdir --volume --use-aliases --help' ;;
                    logs) words='-f --follow --tail --since --until -t --timestamps --no-color --no-log-prefix --help' ;;
                    ps) words='-a --all -q --quiet --services --status --filter --format --no-trunc --help' ;;
                    build) words='--no-cache --pull --build-arg --progress --parallel --force-rm --compress --memory --quiet --help' ;;
                    pull) words='--ignore-pull-failures --include-deps --policy --quiet --help' ;;
                    config) words='--services --profiles --volumes --images --resolve-image-digests --no-interpolate --quiet --format --output --help' ;;
                    stop|restart) words='-t --timeout --help' ;;
                    rm) words='-f --force -s --stop -v --volumes --help' ;;
                    *) words='--help' ;;
                esac
            elif [ -z "$command" ]; then
                words='build config cp create down events exec help images kill logs ls pause port ps pull push restart rm run start stop top unpause up version wait watch'
                mode=words
            else
                case "$command" in
                    exec|run|port) (( positions == 0 )) || return 0 ;;
                    build|create|down|images|kill|logs|pause|ps|pull|push|restart|rm|start|stop|top|unpause|up|wait|watch) ;;
                    help) words='build config cp create down events exec images kill logs pause port ps pull push restart rm run start stop top unpause up version'; mode=words ;;
                    cp) mode=files ;;
                    *) return 0 ;;
                esac
            fi ;;
        *) return 0 ;;
    esac
    case "$mode" in
        files|directories)
            if [ "$mode" = directories ]; then option=-d; else option=-f; fi
            while IFS= read -r candidate; do COMPREPLY+=("$prefix$candidate"); done < <(compgen "$option" -- "$current")
            compopt -o filenames 2>/dev/null || true ;;
        words)
            while IFS= read -r candidate; do COMPREPLY+=("$prefix$candidate"); done < <(compgen -W "$words" -- "$current") ;;
        services|profiles)
            [ "$query" = yes ] || return 0
            # No daemon queries, no stdin reads and no unbounded configuration parsing.
            case "${COMPOSE_FILE:-}" in -|*://*) return 0 ;; esac
            command -v timeout >/dev/null 2>&1 || return 0
            if [ "$mode" = profiles ]; then option=--profiles; else option=--services; fi
            if ! output="$(timeout -k 1 2 docker-compose "${global_args[@]}" config "$option" </dev/null 2>/dev/null)"; then return 0; fi
            while IFS= read -r candidate; do
                [ -n "$candidate" ] || continue
                [[ "$candidate" == "$current"* ]] && COMPREPLY+=("$prefix$candidate")
            done <<< "$output" ;;
    esac
    if [ -n "$trim" ]; then
        for ((i=0; i<${#COMPREPLY[@]}; i++)); do COMPREPLY[i]="${COMPREPLY[i]#"$trim"}"; done
    fi
}
complete -F _mini_docker_compose_completion docker-compose
