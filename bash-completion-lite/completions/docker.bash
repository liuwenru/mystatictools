_mini_docker_cp_completion()
{
    local local_daemon="$1" endpoint="$2" line="${COMP_LINE:0:COMP_POINT}"
    local token= quote= escaped= char candidate container path directory base listing status trim= i
    COMPREPLY=()
    # Decode only shell quoting, never evaluate substitutions or user input.
    for ((i=0; i<${#line}; i++)); do
        char="${line:i:1}"
        if [ -n "$escaped" ]; then
            if [ "$quote" = '"' ]; then
                case "$char" in '"'|'$'|'`'|'\') ;; *) token="$token\\" ;; esac
            fi
            token="$token$char"; escaped=; continue
        fi
        case "$quote" in
            "'") if [ "$char" = "'" ]; then quote=; else token="$token$char"; fi ;;
            '"') case "$char" in '"') quote= ;; '\') escaped=yes ;; *) token="$token$char" ;; esac ;;
            *) case "$char" in
                '\') escaped=yes ;;
                "'"|'"') quote="$char" ;;
                ' '|$'\t'|$'\n') token=; trim= ;;
                ':')
                    if [[ "$COMP_WORDBREAKS" == *:* ]]; then trim="$token:"; fi
                    token="$token$char" ;;
                *) token="$token$char" ;;
            esac ;;
        esac
    done
    if [[ "$token" == -* ]]; then
        COMPREPLY=( $(compgen -W '-a -L -q --archive --follow-link --quiet --help' -- "$token") )
        return
    fi
    # A slash before ':' denotes a local path, e.g. ./file:with-colon.
    if [[ "$token" != *:* || "${token%%:*}" == */* ]]; then
        while IFS= read -r candidate; do COMPREPLY+=("${candidate#"$trim"}"); done < <(compgen -f -- "$token")
        compopt -o filenames 2>/dev/null || true
        if [ "$local_daemon" = yes ] && command -v timeout >/dev/null 2>&1; then
            while IFS= read -r candidate; do
                [[ "$candidate" == "$token"* ]] && COMPREPLY+=("$candidate:")
            done < <(timeout -k 1 2 docker --host "$endpoint" ps --format '{{.ID}}' 2>/dev/null)
        fi
        compopt -o nospace 2>/dev/null || true
        return
    fi
    [ "$local_daemon" = yes ] || return 0
    command -v timeout >/dev/null 2>&1 || return 0
    container="${token%%:*}"; path="${token#*:}"
    [ -n "$container" ] || return 0
    # Reject option-looking IDs; all paths are separate, quoted argv entries.
    [[ "$container" != -* ]] || return 0
    if [[ "$path" == */* ]]; then
        directory="${path%/*}/"; base="${path##*/}"
    else
        directory=; base="$path"
    fi
    # docker cp interprets relative container paths relative to /, not WORKDIR.
    if listing="$(timeout -k 1 2 docker --host "$endpoint" exec --env LC_ALL=C --env QUOTING_STYLE=literal \
        "$container" ls -1Ap -- "/${directory#/}" 2>/dev/null)"; then status=0; else status=$?; fi
    if [ "$status" -ne 0 ]; then
        # Do not retry an unresponsive daemon after a timeout.
        case "$status" in 124|137) return 0 ;; esac
        listing="$(timeout -k 1 2 docker --host "$endpoint" exec --env LC_ALL=C --env QUOTING_STYLE=literal \
            "$container" busybox ls -1Ap -- "/${directory#/}" 2>/dev/null)" || return 0
    fi
    # Readline replaces only the suffix after the last unquoted word-breaking colon.
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        [[ "$candidate" == "$base"* ]] || continue
        candidate="$container:$directory$candidate"
        COMPREPLY+=("${candidate#"$trim"}")
    done <<< "$listing"
    compopt -o filenames -o nospace 2>/dev/null || true
}

_mini_docker_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}" words command= subcommand= word candidate i endpoint token trim=
    COMPREPLY=()
    token="${COMP_LINE:0:COMP_POINT}"
    token="${token##*[[:space:]]}"
    if [[ "$token" == *:* && "$COMP_WORDBREAKS" == *:* ]]; then
        current="$token"; trim="${token%:*}:"
    fi
    # Query only the standard local Unix socket; never contact a remote context.
    local local_daemon=yes
    case "${DOCKER_HOST:-unix:///var/run/docker.sock}" in unix://*) ;; *) local_daemon=no ;; esac
    [ -z "${DOCKER_CONTEXT:-}" ] || local_daemon=no
    for ((i=1; i<COMP_CWORD; i++)); do
        word="${COMP_WORDS[i]}"
        case "$word" in -H|--host|--host=*|--context|--context=*) local_daemon=no ;; esac
        case "$word" in
            -H|--host|--context|--config|--log-level|--name|-e|--env|--env-file|-p|--publish|-v|--volume|--mount|-w|--workdir|-u|--user|--entrypoint|--label|--format|--filter|--since|--until|--tail|--network|--net|--restart|--pull|--file|--tag|--build-arg|--target|--platform|--progress)
                ((i++)); continue ;;
            -f|-t) case "$command" in build|compose|buildx) ((i++)); continue ;; esac ;;
        esac
        if [ -z "$command" ]; then
            case "$word" in
                run|exec|ps|images|pull|push|build|buildx|compose|start|stop|restart|kill|rm|rmi|logs|inspect|stats|top|attach|cp|create|container|image|network|volume|context|info|version|login|logout|system|events|wait|port|rename|update|save|load|tag) command="$word" ;;
            esac
        elif [ "$command" = container ] && [ -z "$subcommand" ] && { [ "$word" = exec ] || [ "$word" = cp ]; }; then
            command="$word"
        elif [ -z "$subcommand" ] && [[ "$word" != -* ]]; then
            # A colon-split image currently being completed is not an argument yet.
            if [ -z "$trim" ] || (( i < COMP_CWORD-2 )); then subcommand="$word"; fi
        fi
    done
    if [ "$command" = cp ]; then
        _mini_docker_cp_completion "$local_daemon" "${DOCKER_HOST:-unix:///var/run/docker.sock}"
        return
    fi
    case "$previous" in
        --restart) words='no on-failure always unless-stopped' ;;
        --pull) words='always missing never' ;;
        --network|--net)
            words='bridge host none'
            [ "$local_daemon" != yes ] || words="$words $(docker --host "${DOCKER_HOST:-unix:///var/run/docker.sock}" network ls --format '{{.Name}}' 2>/dev/null)" ;;
        -f)
            case "$command" in build|compose|buildx) ;; *) return ;; esac
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
        --file|--env-file|--config|--output)
            while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
            compopt -o filenames 2>/dev/null || true; return ;;
        --name|-e|--env|-p|--publish|-v|--volume|--mount|-w|--workdir|-u|--user|--entrypoint|--label|--format|--filter|--since|--until|--tail|--context|-H|--host) return ;;
        *)
            if [[ "$current" == -* ]]; then
                case "$command" in
                    run|create) words='-d -i -t -it -e -p -P -v -w -u --detach --interactive --tty --rm --name --env --env-file --publish --publish-all --volume --mount --workdir --user --network --restart --entrypoint --privileged --read-only --cap-add --cap-drop --pull --help' ;;
                    exec) words='-d -i -t -it -e -u -w --detach --interactive --tty --env --env-file --user --workdir --privileged --help' ;;
                    logs) words='-f -t --follow --tail --since --until --timestamps --details --help' ;;
                    ps|images) words='-a -q -f --all --quiet --filter --format --no-trunc --help' ;;
                    build) words='-f -t --file --tag --build-arg --no-cache --pull --target --platform --progress --help' ;;
                    *) words='--help --version --context --host --config --debug --log-level' ;;
                esac
            elif [ -z "$command" ]; then
                words='run exec ps images pull push build buildx compose start stop restart kill rm rmi logs inspect stats top attach cp create container image network volume context info version login logout system events wait port rename update save load tag'
            else
                case "$command" in
                    container) if [ -z "$subcommand" ]; then words='ls run exec start stop restart kill rm logs inspect stats top attach cp create prune rename update wait port'; else command="$subcommand"; fi ;;
                    image) if [ -z "$subcommand" ]; then words='ls pull push rm inspect build prune tag save load history'; else command="image-$subcommand"; fi ;;
                    network|volume|context) if [ -z "$subcommand" ]; then words='ls inspect create rm prune'; fi ;;
                    system) words='df events info prune' ;;
                    compose) words='up down start stop restart ps logs exec run build pull config version ls' ;;
                    buildx) words='build ls inspect version bake du prune' ;;
                esac
                if [ -z "$words" ] && [ "$local_daemon" = yes ]; then
                    endpoint="${DOCKER_HOST:-unix:///var/run/docker.sock}"
                    case "$command" in
                        exec)
                            # Only running container IDs; later arguments belong to its command.
                            [ -n "$subcommand" ] || words="$(docker --host "$endpoint" ps --format '{{.ID}}' 2>/dev/null)" ;;
                        start|stop|restart|kill|rm|logs|inspect|stats|top|attach|wait|port|rename|update)
                            words="$(docker --host "$endpoint" ps -a --format '{{.Names}}' 2>/dev/null)" ;;
                        run|create|rmi|image-rm|image-inspect|image-history|save|tag)
                            [ -n "$subcommand" ] || words="$(docker --host "$endpoint" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null)" ;;
                        network) words="$(docker --host "$endpoint" network ls --format '{{.Name}}' 2>/dev/null)" ;;
                        volume) words="$(docker --host "$endpoint" volume ls --format '{{.Name}}' 2>/dev/null)" ;;
                    esac
                fi
            fi ;;
    esac
    COMPREPLY=( $(compgen -W "$words" -- "$current") )
    if [ -n "$trim" ]; then
        for ((i=0; i<${#COMPREPLY[@]}; i++)); do COMPREPLY[i]="${COMPREPLY[i]#"$trim"}"; done
    fi
}
complete -F _mini_docker_completion docker
