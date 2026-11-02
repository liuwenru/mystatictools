#!/usr/bin/env bash
# Run from the project root: bash tests/completions.bash
# Dynamic queries are mocked; no daemon, network or root access is required.
set -e
root="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)"
# Test the bundled git rules, not the system's official git completion.
MINI_GIT_OFFICIAL_COMPLETION=
for file in "$root"/completions/*.bash; do
    bash -n "$file"
    source "$file"
done

failures=0
checks=0
check()
{
    local expected="$1" function="$2" candidate found=no
    shift 2
    COMP_WORDS=("$@")
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    COMP_LINE="${TEST_COMP_LINE:-${COMP_WORDS[*]}}"
    COMP_POINT=${#COMP_LINE}
    "$function" || true
    for candidate in "${COMPREPLY[@]}"; do
        [ "$candidate" != "$expected" ] || found=yes
    done
    checks=$((checks + 1))
    if [ "$found" != yes ]; then
        printf 'FAIL: %s -> expected <%s>, got: ' "$COMP_LINE" "$expected"
        printf '<%s> ' "${COMPREPLY[@]}"
        printf '\n'
        failures=$((failures + 1))
    fi
}

systemctl()
{
    case " $* " in
        *' list-unit-files '*) printf '%s\n' 'sshd.service enabled' 'example.timer enabled' ;;
        *' list-units '*) printf '%s\n' 'sshd.service loaded active running SSH' ;;
    esac
}
journalctl() { printf '%s\n' '0 boot-id date range'; }
rg() { printf '%s\n' 'rust: *.rs' 'python: *.py'; }
iptables() { printf '%s\n' '-P INPUT ACCEPT' '-N CUSTOM_CHAIN'; }
ipset()
{
    # Any command other than this read-only name query is a test failure.
    [ "$*" = 'list -name' ] || { printf 'UNEXPECTED_IPSET_QUERY\n'; return 1; }
    [ "${TEST_IPSET_FAIL:-}" != yes ] || return 1
    printf '%s\n' blocked trusted
}
nft()
{
    case " $* " in
        *' list tables '*) printf '%s\n' 'table inet filter' ;;
        *' list table '*) printf '%s\n' 'table inet filter {' ' chain input {' ' }' '}' ;;
    esac
}
docker()
{
    case " $* " in
        *' exec --env LC_ALL=C --env QUOTING_STYLE=literal '*' ls -1Ap -- '*)
            case "${TEST_DOCKER_LS:-}" in
                timeout)
                    # A retry after a timeout would incorrectly produce a candidate.
                    if [[ " $* " == *' busybox ls '* ]]; then printf 'root/\n'; return 0; fi
                    return 124 ;;
                busybox) [[ " $* " == *' busybox ls '* ]] || return 127 ;;
                stopped) return 1 ;;
            esac
            case "${!#}" in
                /) printf '%s\n' 'root/' 'run/' 'file with spaces' '.hidden' ;;
                /root/) printf '%s\n' 'report.txt' 'reports/' 'report with spaces.txt' ;;
                '/file with spaces/') printf '%s\n' 'nested.txt' ;;
                *) return 1 ;;
            esac ;;
        *' ps -a --format {{.ID}} {{.Names}} '*) printf '%s\n' 'a1b2c3d4e5f6 example-container' 'f6e5d4c3b2a1 stopped-db' ;;
        *' ps --format {{.ID}} '*) printf '%s\n' a1b2c3d4e5f6 ;;
        *' ps '*) printf '%s\n' example-container ;;
        *' images '*) printf '%s\n' alpine:latest ;;
        *' network ls '*) printf '%s\n' example-network ;;
        *' volume ls '*) printf '%s\n' example-volume ;;
    esac
}
timeout()
{
    # Invoke the docker function without an external daemon, checking the deadline.
    [ "$1" = -k ] && [ "$2" = 1 ] && [ "$3" = 2 ] || return 1
    shift 3
    "$@"
}
docker-compose()
{
    [ "${COMPOSE_TEST_FAIL:-}" != yes ] || return 1
    if [ -n "${COMPOSE_TEST_FILE:-}" ]; then
        [ "$1" = -f ] && [ "$2" = "$COMPOSE_TEST_FILE" ] || return 1
        shift 2
    fi
    if [ -n "${COMPOSE_TEST_ARGS:-}" ]; then
        [ "$*" = "$COMPOSE_TEST_ARGS" ] || return 1
    fi
    case " ${*: -2} " in
        ' config --services ') printf '%s\n' web worker db ;;
        ' config --profiles ') printf '%s\n' development debug production ;;
        *) return 1 ;;
    esac
}
tmux()
{
    # Only these read-only queries are allowed; others may start a tmux server.
    if [ -n "${TMUX_TEST_SOCKET:-}" ]; then
        [ "$1 $2" = "-S $TMUX_TEST_SOCKET" ] || return 1
        shift 2
    fi
    case "$*" in
        'list-sessions -F #{session_name}') printf '%s\n' work db ;;
        'list-windows -a -F #{session_name}:#{window_index}') printf '%s\n' work:0 work:1 ;;
        'list-panes -a -F #{session_name}:#{window_index}.#{pane_index}') printf '%s\n' work:1.0 work:1.1 ;;
        'list-panes -a -F #{pane_id}') printf '%s\n' %0 %1 ;;
        'list-buffers -F #{buffer_name}') printf '%s\n' buffer0 ;;
        'list-keys -F #{key_table}') printf '%s\n' root prefix copy-mode-vi ;;
        'show-options -g') printf '%s\n' 'mouse off' 'status-left "[#S] "' 'update-environment[0] DISPLAY' ;;
        'show-hooks -g') printf '%s\n' pane-died 'after-new-session[0] run-shell true' ;;
        'show-options -s'|'show-options -gw'|'show-hooks -gw') ;;
        *) printf 'UNEXPECTED_TMUX_QUERY\n' ;;
    esac
}

git()
{
    # Only these read-only local queries are allowed; nothing may contact a remote.
    if [ -n "${GIT_TEST_DIR:-}" ]; then
        [ "$1 $2" = "-C $GIT_TEST_DIR" ] || return 1
        shift 2
    fi
    case "$*" in
        'config --get-regexp ^alias\.') printf '%s\n' 'alias.lg log --oneline' ;;
        'for-each-ref --format=%(refname:short) refs/heads refs/tags refs/remotes') printf '%s\n' main dev v1.0 origin/main origin/feature ;;
        'for-each-ref --format=%(refname:strip=3) refs/remotes') printf '%s\n' HEAD main feature ;;
        'for-each-ref --format=%(refname:short) refs/heads') printf '%s\n' main dev ;;
        'for-each-ref --format=%(refname:short) refs/tags') printf '%s\n' v1.0 ;;
        'for-each-ref --format=%(refname:short) refs/remotes') printf '%s\n' origin/main origin/feature ;;
        'for-each-ref --format=%(refname) refs/remotes/origin') printf '%s\n' refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/feature ;;
        'remote') printf '%s\n' origin ;;
        'stash list --format=%gd') printf '%s\n' 'stash@{0}' ;;
        'config --name-only --list') printf '%s\n' user.name ;;
        'ls-files -z --exclude-standard --modified --others --deleted --directory --no-empty-directory') printf '%s\0' 'new file.txt' changed.txt untracked/ ;;
        'ls-files -z --modified --deleted') printf '%s\0' changed.txt ;;
        'diff --cached --name-only --relative -z') printf '%s\0' staged.txt ;;
        'push --git-completion-helper') printf '%s\n' '--force-with-lease --tags --repo=' ;;
        *' --git-completion-helper') return 129 ;;
        *) printf 'UNEXPECTED_GIT_QUERY\n' ;;
    esac
}

for command in find grep systemctl journalctl rg nslookup iptables ipset nft scp docker docker-compose lsof sed awk xargs tar tmux git; do
    complete -p "$command" >/dev/null
done
check -name _mini_find_completion find -na
check d _mini_find_completion find . -type ''
check bash _mini_find_completion find . -exec bas
check --recursive _mini_grep_completion grep --rec
check auto _mini_grep_completion grep --color = a
check --color=auto _mini_grep_completion grep --color=au
check restart _mini_systemctl_completion systemctl res
check sshd.service _mini_systemctl_completion systemctl --user restart ss
check service _mini_systemctl_completion systemctl -t ser
check warning _mini_journalctl_completion journalctl -p war
check sshd.service _mini_journalctl_completion journalctl -u ss
check 0 _mini_journalctl_completion journalctl -b ''
check python _mini_rg_completion rg -t py
check --hidden _mini_rg_completion rg --hi
check -type= _mini_nslookup_completion nslookup -ty
check -type=AAAA _mini_nslookup_completion nslookup -type=AA
check AAAA _mini_nslookup_completion nslookup -type = AA
check AAAA _mini_nslookup_completion nslookup -type =
check nat _mini_iptables_completion iptables -t n
check POSTROUTING _mini_iptables_completion iptables -t nat -A POST
check ACCEPT _mini_iptables_completion iptables -P INPUT A
check CUSTOM_CHAIN _mini_iptables_completion iptables -A CUS
check CUSTOM_CHAIN _mini_iptables_completion iptables -j CUS
check create _mini_ipset_completion ipset cr
check add _mini_ipset_completion ipset -exist ad
check -exist _mini_ipset_completion ipset -ex
check blocked _mini_ipset_completion ipset add bl
check blocked _mini_ipset_completion ipset -q list bl
check trusted _mini_ipset_completion ipset swap blocked tr
check trusted _mini_ipset_completion ipset -output save -file sets.txt swap blocked tr
check hash:ip _mini_ipset_completion ipset create new hash:i
check ip _mini_ipset_completion ipset create new hash : i
check ip _mini_ipset_completion ipset create new hash :
check list:set _mini_ipset_completion ipset help list:s
check family _mini_ipset_completion ipset create new hash : ip fa
check inet6 _mini_ipset_completion ipset create new hash : ip family in
check range _mini_ipset_completion ipset n new bitmap:port ra
check timeout _mini_ipset_completion ipset add blocked 192.0.2.1 ti
check json _mini_ipset_completion ipset list -output j
check xml _mini_ipset_completion ipset -o x
for line in 'create ' 'rename blocked new' 'add blocked ' 'create new hash:ip timeout ' 'create new hash:mac family' ; do
    read -r -a COMP_WORDS <<< "ipset $line"
    [[ "$line" != *' ' ]] || COMP_WORDS+=('')
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    _mini_ipset_completion || true
    [ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
    checks=$((checks + 1))
done
TEST_IPSET_FAIL=yes
COMP_WORDS=(ipset list ''); COMP_CWORD=2
_mini_ipset_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
unset TEST_IPSET_FAIL
check ruleset _mini_nft_completion nft list ru
check inet _mini_nft_completion nft add table in
check filter _mini_nft_completion nft list table inet fi
check input _mini_nft_completion nft list chain inet filter in
check -P _mini_scp_completion scp -P
check --restart _mini_docker_completion docker run --rest
check -it _mini_docker_completion docker exec -i
# -i of exec is --interactive, so the next word is still a container.
check a1b2c3d4e5f6 _mini_docker_completion docker exec -i a1
check example-container _mini_docker_completion docker stop ex
check a1b2c3d4e5f6 _mini_docker_completion docker exec ''
check a1b2c3d4e5f6 _mini_docker_completion docker exec -it a1
check a1b2c3d4e5f6 _mini_docker_completion docker exec --user root a1
check a1b2c3d4e5f6 _mini_docker_completion docker container exec a1
check a1b2c3d4e5f6 _mini_docker_completion docker container exec -it --user root a1
check -it _mini_docker_completion docker container exec -i
check alpine:latest _mini_docker_completion docker run --name example al
check example-network _mini_docker_completion docker run --network ex
check example-volume _mini_docker_completion docker volume inspect ex
check TCP _mini_lsof_completion lsof -i T
check LISTEN _mini_lsof_completion lsof -s TCP:L
TEST_COMP_LINE='lsof -s TCP:L' check LISTEN _mini_lsof_completion lsof -s TCP : L
TEST_COMP_LINE='lsof -iTCP:4' check 443 _mini_lsof_completion lsof -iTCP : 4
TEST_COMP_LINE='docker run alpine:l' check latest _mini_docker_completion docker run alpine : l
check --expression _mini_sed_completion sed --exp
check -F _mini_awk_completion awk -F
check --max-procs _mini_xargs_completion xargs --max-p
check bash _mini_xargs_completion xargs -n 1 bas
check bash _mini_xargs_completion xargs -- bas
check --extract _mini_tar_completion tar --ext
check -xzvf _mini_tar_completion tar -xz
check xzvf _mini_tar_completion tar xz
check pax _mini_tar_completion tar --format pa
check --format=pax _mini_tar_completion tar --format=pa
check pax _mini_tar_completion tar --format = pa
check gnu _mini_tar_completion tar -H gn
check shell _mini_tar_completion tar --quoting-style sh
check bash _mini_tar_completion tar -I bas
check up _mini_docker_compose_completion docker-compose u
check --build _mini_docker_compose_completion docker-compose up --bu
check --follow _mini_docker_compose_completion docker-compose logs --fo
check --no-TTY _mini_docker_compose_completion docker-compose exec --no
check auto _mini_docker_compose_completion docker-compose --ansi a
check auto _mini_docker_compose_completion docker-compose --ansi=a
check always _mini_docker_compose_completion docker-compose pull --policy a
check web _mini_docker_compose_completion docker-compose up w
check worker _mini_docker_compose_completion docker-compose logs wo
check db _mini_docker_compose_completion docker-compose exec d
check web _mini_docker_compose_completion docker-compose exec --user root w
check web _mini_docker_compose_completion docker-compose run --name temporary w
check web _mini_docker_compose_completion docker-compose run -v /tmp:/tmp w
check web _mini_docker_compose_completion docker-compose up --exit-code-from w
check production _mini_docker_compose_completion docker-compose --profile pro
COMPOSE_TEST_ARGS='-f compose.yml -f override.yml -p demo config --services' check web _mini_docker_compose_completion docker-compose -f compose.yml -f override.yml -p demo up w
COMPOSE_TEST_ARGS='--file=compose.yml --project-name=demo config --services' check web _mini_docker_compose_completion docker-compose --file=compose.yml --project-name=demo up w
COMPOSE_TEST_ARGS='--project-directory . --env-file .env --profile debug config --services' check web _mini_docker_compose_completion docker-compose --project-directory . --env-file .env --profile debug up w
COMPOSE_TEST_FILE='project with spaces/compose.yml' TEST_COMP_LINE='docker-compose -f "project with spaces/compose.yml" up w' check web _mini_docker_compose_completion docker-compose -f 'project with spaces/compose.yml' up w
COMPOSE_TEST_FILE='project with spaces/compose.yml' TEST_COMP_LINE='docker-compose -f project\ with\ spaces/compose.yml up w' check web _mini_docker_compose_completion docker-compose -f 'project\ with\ spaces/compose.yml' up w
for line in 'docker-compose exec web ' 'docker-compose run --rm web ' 'docker-compose -f - up ' 'docker-compose -f https://example.invalid/compose.yml up '; do
    COMP_LINE="$line"; COMP_POINT=${#line}
    _mini_docker_compose_completion || true
    [ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
    checks=$((checks + 1))
done
COMPOSE_TEST_FAIL=yes
COMP_LINE='docker-compose up '; COMP_POINT=${#COMP_LINE}
_mini_docker_compose_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
unset COMPOSE_TEST_FAIL
check select-window _mini_tmux_completion tmux select-w
check selectw _mini_tmux_completion tmux sel
check -L _mini_tmux_completion tmux -
check work _mini_tmux_completion tmux attach -t w
check db _mini_tmux_completion tmux a -t ''
check db _mini_tmux_completion tmux kill-session -at d
check -t _mini_tmux_completion tmux attach -d -
TEST_COMP_LINE='tmux selectw -t work:1' check 1 _mini_tmux_completion tmux selectw -t work : 1
TEST_COMP_LINE='tmux select-pane -t work:1.' check 1.1 _mini_tmux_completion tmux select-pane -t work : 1.
check %1 _mini_tmux_completion tmux select-pane -t %
check mouse _mini_tmux_completion tmux set -g mou
check update-environment _mini_tmux_completion tmux show-options -g upd
check on _mini_tmux_completion tmux set -g mouse ''
check pane-died _mini_tmux_completion tmux set-hook -g pane-d
check after-new-session _mini_tmux_completion tmux set-hook -g after-n
check buffer0 _mini_tmux_completion tmux pasteb -b buf
check tiled _mini_tmux_completion tmux selectl ti
check copy-mode-vi _mini_tmux_completion tmux bind -T copy
check command _mini_tmux_completion tmux clearphist -T com
check bash _mini_tmux_completion tmux new-window -t work bas
TEST_COMP_LINE='tmux ls \; attach -t d' check db _mini_tmux_completion tmux ls '\' ';' attach -t d
TMUX_TEST_SOCKET=/tmp/tmux-test TEST_COMP_LINE='tmux -S /tmp/tmux-test attach -t w' check work _mini_tmux_completion tmux -S /tmp/tmux-test attach -t w
check status _mini_git_completion git sta
check lg _mini_git_completion git l
check --no-pager _mini_git_completion git --no-p
check dev _mini_git_completion git checkout d
check feature _mini_git_completion git switch fea
check origin/feature _mini_git_completion git log origin/f
check v1.0 _mini_git_completion git show v
check main..dev _mini_git_completion git log main..d
check v1.0...main _mini_git_completion git diff v1.0...ma
check 'new file.txt' _mini_git_completion git add new
check untracked/ _mini_git_completion git add un
check changed.txt _mini_git_completion git restore ch
check changed.txt _mini_git_completion git checkout -- ch
check staged.txt _mini_git_completion git restore --staged st
check staged.txt _mini_git_completion git reset HEAD -- st
check origin _mini_git_completion git push ''
check dev _mini_git_completion git push origin d
check feature _mini_git_completion git fetch origin fe
check main _mini_git_completion git pull origin ma
TEST_COMP_LINE='git push origin dev:fe' check feature _mini_git_completion git push origin dev : fe
check dev _mini_git_completion git branch -d d
check origin/main _mini_git_completion git branch -u origin/m
TEST_COMP_LINE='git branch --set-upstream-to=origin/m' check origin/main _mini_git_completion git branch --set-upstream-to = origin/m
check v1.0 _mini_git_completion git tag -d v
check 'stash@{0}' _mini_git_completion git stash pop ''
check push _mini_git_completion git stash pu
check set-url _mini_git_completion git remote set-u
check origin _mini_git_completion git remote show ''
check user.name _mini_git_completion git config user.n
check --force-with-lease _mini_git_completion git push --force-w
check --cached _mini_git_completion git diff --cach
check --amend _mini_git_completion git commit --am
check ort _mini_git_completion git merge -s o
TEST_COMP_LINE='git status --untracked-files=n' check normal _mini_git_completion git status --untracked-files = n
check stash _mini_git_completion git help sta
GIT_TEST_DIR=/srv/repo check dev _mini_git_completion git -C /srv/repo checkout d
for line in 'git commit -m ' 'git checkout -b ' 'git log -n ' 'git push origin dev:feature '; do
    COMP_LINE="$line"; COMP_POINT=${#line}
    read -r -a COMP_WORDS <<< "$line"; COMP_WORDS+=(''); COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    _mini_git_completion || true
    [ "${#COMPREPLY[@]}" -eq 0 ] || [ "$line" = 'git push origin dev:feature ' ] || { printf 'FAIL: %s -> unexpected: %s\n' "$line" "${COMPREPLY[*]}"; failures=$((failures + 1)); }
    [[ " ${COMPREPLY[*]} " != *UNEXPECTED* ]] || { printf 'FAIL: %s -> %s\n' "$line" "${COMPREPLY[*]}"; failures=$((failures + 1)); }
    checks=$((checks + 1))
done

for line in 'tmux set -g status-left ' 'tmux set -g mouse on ' 'tmux attach -t work ' 'tmux new -s ' 'tmux kill-server '; do
    COMP_LINE="$line"; COMP_POINT=${#line}
    read -r -a COMP_WORDS <<< "$line"; COMP_WORDS+=(''); COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    _mini_tmux_completion || true
    [ "${#COMPREPLY[@]}" -eq 0 ] || { printf 'FAIL: %s -> unexpected: %s\n' "$line" "${COMPREPLY[*]}"; failures=$((failures + 1)); }
    checks=$((checks + 1))
done

check a1b2c3d4e5f6: _mini_docker_completion docker cp a1
check example-container: _mini_docker_completion docker cp exa
check stopped-db: _mini_docker_completion docker cp sto
check f6e5d4c3b2a1: _mini_docker_completion docker cp ./local f6
check stopped-db: _mini_docker_completion docker container cp ./local st
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:/ro' check /root/ _mini_docker_completion docker cp a1b2c3d4e5f6 : /ro
TEST_COMP_LINE='docker cp ./local a1b2c3d4e5f6:/ro' check /root/ _mini_docker_completion docker cp ./local a1b2c3d4e5f6 : /ro
TEST_COMP_LINE='docker container cp a1b2c3d4e5f6:/ro' check /root/ _mini_docker_completion docker container cp a1b2c3d4e5f6 : /ro
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:/root/re' check /root/reports/ _mini_docker_completion docker cp a1b2c3d4e5f6 : /root/re
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:/root/re' check /root/report.txt _mini_docker_completion docker cp a1b2c3d4e5f6 : /root/re
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:/root/re' check '/root/report with spaces.txt' _mini_docker_completion docker cp a1b2c3d4e5f6 : /root/re
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:ro' check root/ _mini_docker_completion docker cp a1b2c3d4e5f6 : ro
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:/.h' check /.hidden _mini_docker_completion docker cp a1b2c3d4e5f6 : /.h
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:/file\ with\ spaces/ne' check '/file with spaces/nested.txt' _mini_docker_completion docker cp a1b2c3d4e5f6 : '/file\ with\ spaces/ne'
TEST_COMP_LINE='docker cp "a1b2c3d4e5f6:/file with spaces/ne' check 'a1b2c3d4e5f6:/file with spaces/nested.txt' _mini_docker_completion docker cp '"a1b2c3d4e5f6:/file with spaces/ne'
TEST_COMP_LINE='docker cp a1b2c3d4e5f6:"/file with spaces/ne' check '/file with spaces/nested.txt' _mini_docker_completion docker cp a1b2c3d4e5f6 : '"/file with spaces/ne'
TEST_COMP_LINE='docker cp "a1b2c3d4e5f6:/root/re"' check 'a1b2c3d4e5f6:/root/report.txt' _mini_docker_completion docker cp '"a1b2c3d4e5f6:/root/re"'
TEST_COMP_LINE="docker cp 'a1b2c3d4e5f6:/root/re" check 'a1b2c3d4e5f6:/root/report.txt' _mini_docker_completion docker cp "'a1b2c3d4e5f6:/root/re"
TEST_COMP_LINE='docker cp a1b2c3d4e5f6\:/ro' check 'a1b2c3d4e5f6:/root/' _mini_docker_completion docker cp 'a1b2c3d4e5f6\:/ro'
TEST_DOCKER_LS=busybox TEST_COMP_LINE='docker cp a1b2c3d4e5f6:/ro' check /root/ _mini_docker_completion docker cp a1b2c3d4e5f6 : /ro
for mode in timeout stopped; do
    TEST_DOCKER_LS="$mode"
    COMP_WORDS=(docker cp a1b2c3d4e5f6 : /ro); COMP_CWORD=4
    COMP_LINE='docker cp a1b2c3d4e5f6:/ro'; COMP_POINT=${#COMP_LINE}
    _mini_docker_completion || true
    [ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
    checks=$((checks + 1))
done
unset TEST_DOCKER_LS

# After the container ID, do not suggest more containers or query the daemon.
docker() { printf 'UNEXPECTED_DAEMON_QUERY\n'; }
command()
{
    if [ "$1" = -v ] && [ "$2" = timeout ]; then return 1; fi
    builtin command "$@"
}
COMP_WORDS=(docker cp a1b2c3d4e5f6 : /ro); COMP_CWORD=4
COMP_LINE='docker cp a1b2c3d4e5f6:/ro'; COMP_POINT=${#COMP_LINE}
_mini_docker_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
check completions/docker.bash _mini_docker_completion docker cp completions/dock
COMP_LINE='docker-compose up '; COMP_POINT=${#COMP_LINE}
_mini_docker_compose_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
unset -f command

COMP_WORDS=(docker exec -it a1b2c3d4e5f6 ''); COMP_CWORD=4
_mini_docker_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
COMP_WORDS=(docker container exec -it a1b2c3d4e5f6 ''); COMP_CWORD=5
_mini_docker_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))

# A remote endpoint must never be queried, even through an environment override.
COMP_WORDS=(docker --context remote stop ''); COMP_CWORD=4
_mini_docker_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
DOCKER_HOST=tcp://remote:2375
COMP_WORDS=(docker stop ''); COMP_CWORD=2
_mini_docker_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
unset DOCKER_HOST
COMP_WORDS=(docker --context remote cp a1b2c3d4e5f6 : /ro); COMP_CWORD=6
COMP_LINE='docker --context remote cp a1b2c3d4e5f6:/ro'; COMP_POINT=${#COMP_LINE}
_mini_docker_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))

# Use an isolated directory to check that paths containing spaces stay intact.
temporary="$(mktemp -d "${TMPDIR:-/tmp/opencode}/mini-completion.XXXXXXXX")"
trap 'rm -f -- "$temporary/file with spaces" "$temporary/git-official" "$temporary/home/.ssh/config"; rmdir -- "$temporary/home/.ssh" "$temporary/home" "$temporary" 2>/dev/null || true' EXIT
touch "$temporary/file with spaces"
for command in find grep rg scp lsof sed awk; do
    check "$temporary/file with spaces" "_mini_${command}_completion" "$command" "$temporary/file"
done
check "$temporary/file with spaces" _mini_xargs_completion xargs cat "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker cp "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker load '<' "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker load -i "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker load --input "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker load --input = "$temporary/file"
check "--input=$temporary/file with spaces" _mini_docker_completion docker load "--input=$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker image load --input = "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker save --output = "$temporary/file"
check "--output=$temporary/file with spaces" _mini_docker_completion docker save "--output=$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker image load -i "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker save -o "$temporary/file"
check "$temporary/file with spaces" _mini_docker_completion docker save alpine:latest '>' "$temporary/file"
check --input _mini_docker_completion docker load --in
check "$temporary/file with spaces" _mini_tmux_completion tmux source-file "$temporary/file"
check "$temporary/file with spaces" _mini_git_completion git log -- "$temporary/file"
check "$temporary/file with spaces" _mini_git_completion git commit -F "$temporary/file"
# A system git completion script, when found, replaces the bundled rules.
printf '%s\n' '__git_main() { :; }' 'complete -F __git_main git' > "$temporary/git-official"
if ( MINI_GIT_OFFICIAL_COMPLETION="$temporary/missing $temporary/git-official"; source "$root/completions/git.bash"; complete -p git | grep -q ' __git_main git$' ); then :; else
    printf 'FAIL: official git completion was not used\n'; failures=$((failures + 1))
fi
checks=$((checks + 1))
check "$temporary/file with spaces" _mini_docker_completion docker cp a1b2c3d4e5f6:/root/report.txt "$temporary/file"
check "$temporary/file with spaces" _mini_tar_completion tar -czvf "$temporary/file"
check "$temporary/file with spaces" _mini_tar_completion tar xzvf "$temporary/file"
check "$temporary/file with spaces" _mini_tar_completion tar -f "$temporary/file"
check "$temporary/file with spaces" _mini_ipset_completion ipset restore -file "$temporary/file"
check "$temporary/file with spaces" _mini_tar_completion tar --file = "$temporary/file"
check "--file=$temporary/file with spaces" _mini_tar_completion tar "--file=$temporary/file"
check "$temporary/file with spaces" _mini_tar_completion tar -cf archive.tar -- "$temporary/file"
check "$temporary/file with spaces" _mini_tar_completion tar -cfarchive.tar "$temporary/file"
check "$temporary/file with spaces" _mini_tar_completion tar -T "$temporary/file"
check "$temporary/file with spaces" _mini_docker_compose_completion docker-compose -f "$temporary/file"
check "$temporary/file with spaces" _mini_docker_compose_completion docker-compose "--file=$temporary/file"
check "-f$temporary/file with spaces" _mini_docker_compose_completion docker-compose "-f$temporary/file"
check "$temporary/file with spaces" _mini_docker_compose_completion docker-compose --env-file "$temporary/file"
mkdir -p "$temporary/home/.ssh"
check "$temporary/home" _mini_tar_completion tar -C "$temporary/ho"
check "$temporary/home" _mini_tmux_completion tmux new -d -c "$temporary/ho"
check "--directory=$temporary/home" _mini_tar_completion tar "--directory=$temporary/ho"
check "$temporary/home" _mini_docker_compose_completion docker-compose --project-directory "$temporary/ho"
COMP_WORDS=(tar -C "$temporary/file"); COMP_CWORD=2
_mini_tar_completion || true
[ "${#COMPREPLY[@]}" -eq 0 ] || failures=$((failures + 1))
checks=$((checks + 1))
printf 'Host production test-*\n' > "$temporary/home/.ssh/config"
HOME="$temporary/home" check production: _mini_scp_completion scp prod
HOME="$temporary/home" check admin@production: _mini_scp_completion scp admin@prod
printf '%s checks, %s failures\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
