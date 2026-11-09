#!/usr/bin/env zsh
# Run from anywhere: zsh test/completions.zsh
# Starts an interactive zsh in a pseudo terminal (zsh/zpty), installs a copy of
# the project into a temporary HOME, sources init.zsh and presses Tab on each
# test line. compadd is wrapped to record matches; dynamic commands are mocked
# (test/mocks.zsh), so no daemon, network or root access is needed.
emulate zsh
setopt err_return no_unset pipe_fail
zmodload zsh/zpty zsh/zselect

root=${0:A:h:h}
tmp=$(mktemp -d ${TMPDIR:-/tmp}/zsh-completion-lite-test.XXXXXXXX)
trap 'zpty -d t 2>/dev/null || :; rm -rf -- $tmp' EXIT
out=$tmp/matches
install_dir=$tmp/home/.local/share/zsh-completion-lite
integer checks=0 failures=0 serial=0

# Install like the README: a plain recursive copy, umask 022.
(umask 022; mkdir -p $install_dir:h && cp -R $root/. $install_dir/ && rm -rf $install_dir/test)
mkdir -p $tmp/home/.ssh $tmp/home/data
touch $tmp/home/data/'file with spaces'
print 'Host production test-*' > $tmp/home/.ssh/config
# PATH without timeout(1), for the "no timeout" checks.
mkdir $tmp/no-timeout
for f in /usr/bin/* /bin/*(N); do
    [[ ${f:t} == timeout || -e $tmp/no-timeout/${f:t} ]] || ln -s $f $tmp/no-timeout/${f:t}
done
data=$tmp/home/data

# Read pty output until $1 appears; give up after about 10 seconds.
wait_for()
{
    local buffer= chunk
    integer tries=0
    while (( tries++ < 1000 )); do
        if zpty -r -t t chunk 2>/dev/null; then
            buffer+=$chunk
            [[ $buffer == *${~1}* ]] && return 0
        else
            zselect -t 1 || true
        fi
    done
    print -r -- "TIMEOUT waiting for $1"
    return 1
}
# Run a command line in the test shell; wait for its output and the next
# prompt, so that keys typed afterwards reach the line editor, not the
# terminal's line discipline.
run()
{
    (( ++serial ))
    zpty -w t "$1; print -r __DO''NE_$serial"
    wait_for "__DONE_$serial*ZCLPROMPT>"
}
# Type $1, press Tab, clear the line; matches land in $out. Each completion
# writes "TAB" first (the _zcl_mark completer), proving Tab was handled.
complete_line()
{
    : > $out
    (( ++serial ))
    zpty -w -n t "$1"$'\t'
    zpty -w -n t $'\C-e\C-u'
    zpty -w t "print -r __DO''NE_$serial"
    wait_for "__DONE_$serial*ZCLPROMPT>"
    if [[ $(<$out) != TAB* ]]; then
        print -r -- "FAIL: $1 -> completion did not run"
        (( ++failures ))
        return 1
    fi
}
# check EXPECTED LINE: one match, as inserted or unquoted, equals EXPECTED.
check()
{
    local expected=$1 line=$2 m
    local -a matches
    (( ++checks ))
    complete_line $line || return 0
    matches=(${${(M)${(f)"$(<$out)"}:#M:*}#M:})
    for m in $matches; do
        [[ $m == $expected || ${(Q)m} == $expected ]] && return 0
    done
    print -r -- "FAIL: $line -> expected <$expected>, got: ${(j: :)${(@)matches/#/<}/%/>}"
    (( ++failures ))
    return 0
}
# none LINE: no matches at all (and no UNEXPECTED_* query output).
none()
{
    local line=$1
    (( ++checks ))
    complete_line $line || return 0
    if [[ $(<$out) == *M:* ]]; then
        print -r -- "FAIL: $line -> unexpected: ${(j: :)${(M)${(f)"$(<$out)"}:#M:*}#M:}"
        (( ++failures ))
    fi
    return 0
}

# exec: zpty runs the command in a forked copy of this script, whose EXIT
# trap would otherwise remove $tmp when the session ends.
zpty -b t "exec env HOME=$tmp/home TERM=dumb zsh -f -i"
run "PS1='ZCLPROMPT> '; unsetopt promptcr; cd $data"
run "export ZCL_OUT=$out; source $install_dir/init.zsh; source $root/test/mocks.zsh"
run "_zcl_mark() { print TAB >> \$ZCL_OUT; return 1 }; zstyle ':completion:*' completer _zcl_mark _complete"

# Registration: every #compdef command uses our function.
run "for c in kill find grep systemctl journalctl rg nslookup iptables ipset nft scp docker docker-compose lsof sed awk xargs tar tmux git nmcli sshfs lvm lvcreate vgs pvcreate; do print -r -- \$c=\$_comps[\$c]; done > $tmp/registered"
for line in ${(f)"$(<$tmp/registered)"}; do
    (( ++checks ))
    [[ ${line#*=} == _mini_* ]] || { print -r -- "FAIL: not registered: $line"; (( ++failures )) }
done

check 42 'kill -9 4'
check -name 'find -na'
check d 'find . -type '
check bash 'find . -exec bas'
check -user 'find . -us'
check --recursive 'grep --rec'
check --color=auto 'grep --color=au'
check --color= 'grep --col'
check restart 'systemctl res'
check sshd.service 'systemctl --user restart ss'
check service 'systemctl -t ser'
none 'systemctl -H remote restart '
check warning 'journalctl -p war'
check sshd.service 'journalctl -u ss'
check 0 'journalctl -b '
none 'journalctl -b I'
check python 'rg -t py'
check --hidden 'rg --hi'
check -type= 'nslookup -ty'
check -type=AAAA 'nslookup -type=AA'
check nat 'iptables -t n'
check POSTROUTING 'iptables -t nat -A POST'
check ACCEPT 'iptables -P INPUT A'
check CUSTOM_CHAIN 'iptables -A CUS'
check CUSTOM_CHAIN 'iptables -j CUS'

check create 'ipset cr'
check add 'ipset -exist ad'
check -exist 'ipset -ex'
check blocked 'ipset add bl'
check blocked 'ipset -q list bl'
check trusted 'ipset swap blocked tr'
check trusted 'ipset -output save -file sets.txt swap blocked tr'
check hash:ip 'ipset create new hash:i'
check list:set 'ipset help list:s'
check family 'ipset create new hash:ip fa'
check inet6 'ipset create new hash:ip family in'
check range 'ipset n new bitmap:port ra'
check timeout 'ipset add blocked 192.0.2.1 ti'
check json 'ipset list -output j'
check xml 'ipset -o x'
check hash:ip,port,net 'ipset create new hash:ip,p'
check bitmap:port 'ipset help bit'
check netmask 'ipset create new hash:ip net'
check -6 'ipset create new hash:ip -'
check timeout 'ipset create new hash:mac '
check size 'ipset create new list:set '
check comment 'ipset add blocked 192.0.2.5 '
check nomatch 'ipset add trusted 10.1.0.0/16 '
check nomatch 'ipset test trusted 10.0.0.0/8 '
check trusted 'ipset add group tr'
check after 'ipset add group trusted '
check blocked 'ipset add group trusted before '
check 192.0.2.10 'ipset del blocked 192.0.2.1'
check 10.0.0.0/8 'ipset -exist test trusted '
check 2001:db8::1 'ipset del blocked 2001:db8::'
check 2001:db8::1 'ipset del blocked 2001:d'
# Parameters not supported by the set, already used, or meant for other types.
for line in 'add blocked 192.0.2.5 pa' 'add blocked 192.0.2.5 sk' 'add trusted 10.1.0.0/16 com' \
    'add blocked 192.0.2.5 timeout 30 ti' 'create new hash:ip timeout 1 ti' 'create new hash:mac fam' \
    'add blocked 1' 'del trusted 192' 'add blocked 192.0.2.5 en' 'create new hash:ip ty' \
    'create ' 'rename blocked new' 'add blocked ' 'create new hash:ip timeout ' 'create new hash:mac family'; do
    none "ipset $line"
done
# Without `ipset help` the fixed type list is used.
run 'export TEST_IPSET_NOHELP=yes'
check hash:net,iface 'ipset create new hash:net,i'
check family 'ipset create new hash:net fa'
run 'unset TEST_IPSET_NOHELP; export TEST_IPSET_FAIL=yes'
none 'ipset list '
run 'unset TEST_IPSET_FAIL'

check connection 'nmcli c'
check --terse 'nmcli --te'
check ipv4.method 'nmcli con mod lo ipv4.m'
check 'Wired\ connection\ 1' 'nmcli con up id Wir'
check 'Wired connection 1' 'nmcli con up id "Wired con'
# Inside single quotes the reply is escaped for that quote.
check "it'\\''s mine" "nmcli con up id 'it"
check "it\\'s\\ mine" 'nmcli con up id it'
check 00:11:22:33:44:55 'nmcli con mod x cloned-mac-address 00:11:'
check vpn:office 'nmcli con up id vpn:o'
check ops@site 'nmcli con up id ops@s'
none 'nmcli con up id zz'
check "$data/file with spaces" "nmcli con import type openvpn file $data/fi"
run 'export TEST_NMCLI_OLD=yes'
check connection 'nmcli -t c'
check modify 'nmcli connection mo'
check 'Wired connection 1' 'nmcli con up Wi'
check uuid 'nmcli con show uu'
check vpn:office 'nmcli con up vpn:'
check wlan0 'nmcli -m multiline device show wl'
check eth0 'nmcli con up ifname e'
check multiline 'nmcli -m mu'
check --pretty 'nmcli --pr'
check wifi 'nmcli radio w'
run 'unset TEST_NMCLI_OLD'

check --verbose 'sshfs --verb'
check reconnect 'sshfs -o rec'
check reconnect,allow_other 'sshfs -o reconnect,allow_o'
check -oreconnect 'sshfs -oreco'
check dcache_link_timeout= 'sshfs -o dcache_l'
check noauto_cache 'sshfs -o noauto'
check debug 'sshfs -o deb'
check ServerAliveInterval= 'sshfs -o ServerAliveI'
check default_permissions 'sshfs host: /mnt -o default_'
check reconnect,dir_cache=yes 'sshfs -o reconnect,dir_cache=y'
check idmap=user 'sshfs -o idmap=u'
check workaround=rename:renamexdev 'sshfs -o workaround=rename:renamex'
check StrictHostKeyChecking=accept-new 'sshfs -o StrictHostKeyChecking=acc'
check production: 'sshfs prod'
check admin@production: 'sshfs -o reconnect admin@prod'
check ProxyJump=production 'sshfs -o ProxyJump=pro'
check $data 'sshfs -p 2222 srv:/data '"${data:h}/da"
check $data 'sshfs -o reconnect srv: '"${data:h}/da"
check "$data/file with spaces" "sshfs -F $data/fi"
check "IdentityFile=$data/file with spaces" "sshfs -o IdentityFile=$data/fi"
run 'export TEST_SSHFS_FAIL=yes'
check sshfs_sync 'sshfs -o sshfs_s'
run 'unset TEST_SSHFS_FAIL'
# Remote paths and -p values are never completed.
for line in 'srv:/d' 'srv:' '-p 2'; do none "sshfs $line"; done

check lvcreate 'lvm lvcr'
check vgcreate 'lvm help vgc'
check vg0 'lvcreate -L 10G '
check vg0 'lvm lvcreate -L 10G -n data '
check vg0/root 'lvcreate -L 1G -s '
check /dev/sdb 'lvcreate -L 10G vg0 '
check thin-pool 'lvcreate --type th'
check vg0/data 'lvcreate --thinpool vg0/d'
check ay 'lvcreate -a a'
check --alloc=cling 'lvcreate --alloc=cl'
check --readahead 'lvcreate --read'
check auto 'lvcreate -r '
check vg0/root 'lvextend -r -L +1G '
check /dev/sdb 'lvextend -l +100%FREE vg0/root '
check backup 'vgs b'
check ay 'vgchange -a '
check vg0 'vgchange -a y '
check vg0 'vgchange -ay '
check /dev/vdc 'vgextend vg0 '
check /dev/sdb 'vgreduce vg0 '
check /dev/vdc 'vgcreate -s 4M newvg '
check /dev/vdc 'pvcreate '
check /dev/sdb 'pvs '
check data 'lvrename vg0 d'
check vg0/root 'lvs vg0/r'
check lv_name,devices 'lvs -o lv_name,dev'
check +devices 'lvs -o +dev'
check G 'lvs --units G'
check vg0 'lvs -a v'
for line in 'vgcreate ' 'vgrename vg0 ' 'lvcreate -n ' 'lvcreate -L ' 'lvcreate -L 1G -s vg0/root ' 'lvrename vg0/root '; do
    none $line
done

check ruleset 'nft list ru'
check inet 'nft add table in'
check filter 'nft list table inet fi'
check input 'nft list chain inet filter in'
check -P 'scp -P'
check production: 'scp prod'
check admin@production: 'scp admin@prod'
none 'scp production:/et'

check --restart 'docker run --rest'
check -it 'docker exec -i'
# -i of exec is --interactive, so the next word is still a container.
check a1b2c3d4e5f6 'docker exec -i a1'
check example-container 'docker stop ex'
check a1b2c3d4e5f6 'docker exec '
check a1b2c3d4e5f6 'docker exec -it a1'
check a1b2c3d4e5f6 'docker exec --user root a1'
check a1b2c3d4e5f6 'docker container exec a1'
check a1b2c3d4e5f6 'docker container exec -it --user root a1'
check -it 'docker container exec -i'
check alpine:latest 'docker run --name example al'
check alpine:latest 'docker run alpine:l'
check alpine:latest 'docker image rm al'
check example-network 'docker run --network ex'
check example-volume 'docker volume inspect ex'
check a1b2c3d4e5f6 'docker inspect a1'
check example-container 'docker inspect exa'
check stopped-db 'docker inspect sto'
check f6e5d4c3b2a1 'docker inspect example-container f6'
check f6e5d4c3b2a1 'docker container inspect f6'
check stopped-db 'docker container inspect sto'
check --input 'docker load --in'
none 'docker exec -it a1b2c3d4e5f6 '
none 'docker container exec -it a1b2c3d4e5f6 '
# A remote endpoint must never be queried, even through an environment override.
none 'docker --context remote stop '
run 'export DOCKER_HOST=tcp://remote:2375'
none 'docker stop '
run 'unset DOCKER_HOST'
none 'docker --context remote cp a1b2c3d4e5f6:/ro'
check a1b2c3d4e5f6: 'docker cp a1'
check example-container: 'docker cp exa'
check stopped-db: 'docker cp sto'
check f6e5d4c3b2a1: 'docker cp ./local f6'
check stopped-db: 'docker container cp ./local st'
check a1b2c3d4e5f6:/root/ 'docker cp a1b2c3d4e5f6:/ro'
check a1b2c3d4e5f6:/root/ 'docker cp ./local a1b2c3d4e5f6:/ro'
check a1b2c3d4e5f6:/root/ 'docker container cp a1b2c3d4e5f6:/ro'
check a1b2c3d4e5f6:/root/reports/ 'docker cp a1b2c3d4e5f6:/root/re'
check a1b2c3d4e5f6:/root/report.txt 'docker cp a1b2c3d4e5f6:/root/re'
check 'a1b2c3d4e5f6:/root/report with spaces.txt' 'docker cp a1b2c3d4e5f6:/root/re'
check a1b2c3d4e5f6:root/ 'docker cp a1b2c3d4e5f6:ro'
check a1b2c3d4e5f6:/.hidden 'docker cp a1b2c3d4e5f6:/.h'
check 'a1b2c3d4e5f6:/file with spaces/nested.txt' 'docker cp a1b2c3d4e5f6:/file\ with\ spaces/ne'
check 'a1b2c3d4e5f6:/file with spaces/nested.txt' 'docker cp "a1b2c3d4e5f6:/file with spaces/ne'
check 'a1b2c3d4e5f6:/root/report.txt' "docker cp 'a1b2c3d4e5f6:/root/re"
check 'a1b2c3d4e5f6:/root/' 'docker cp a1b2c3d4e5f6\:/ro'
run 'export TEST_DOCKER_LS=busybox'
check a1b2c3d4e5f6:/root/ 'docker cp a1b2c3d4e5f6:/ro'
for mode in timeout stopped; do
    run "export TEST_DOCKER_LS=$mode"
    none 'docker cp a1b2c3d4e5f6:/ro'
done
run 'unset TEST_DOCKER_LS'
check "$data/file with spaces" "docker cp $data/fi"
check "$data/file with spaces" "docker cp a1b2c3d4e5f6:/root/report.txt $data/fi"
check "$data/file with spaces" "docker load -i $data/fi"
check "$data/file with spaces" "docker load --input $data/fi"
check "--input=$data/file with spaces" "docker load --input=$data/fi"
check "$data/file with spaces" "docker image load -i $data/fi"
check "--input=$data/file with spaces" "docker image load --input=$data/fi"
check "$data/file with spaces" "docker save -o $data/fi"
check "--output=$data/file with spaces" "docker save --output=$data/fi"
check "$data/file with spaces" "docker load < $data/fi"
check "$data/file with spaces" "docker save alpine:latest > $data/fi"

check --expression 'sed --exp'
check -F 'awk -F'
check --max-procs 'xargs --max-p'
check bash 'xargs -n 1 bas'
check bash 'xargs -- bas'
check TCP 'lsof -i T'
check TCP:LISTEN 'lsof -s TCP:L'
check -iTCP:443 'lsof -iTCP:4'
check -sTCP:LISTEN 'lsof -sTCP:L'
check --extract 'tar --ext'
check -xzvf 'tar -xz'
check xzvf 'tar xz'
check pax 'tar --format pa'
check --format=pax 'tar --format=pa'
check gnu 'tar -H gn'
check shell 'tar --quoting-style sh'
check bash 'tar -I bas'

check up 'docker-compose u'
check --build 'docker-compose up --bu'
check --follow 'docker-compose logs --fo'
check --no-TTY 'docker-compose exec --no'
check auto 'docker-compose --ansi a'
check --ansi=auto 'docker-compose --ansi=a'
check always 'docker-compose pull --policy a'
check web 'docker-compose up w'
check worker 'docker-compose logs wo'
check db 'docker-compose exec d'
check web 'docker-compose exec --user root w'
check web 'docker-compose run --name temporary w'
check web 'docker-compose run -v /tmp:/tmp w'
check web 'docker-compose up --exit-code-from w'
check production 'docker-compose --profile pro'
run "export COMPOSE_TEST_ARGS='-f compose.yml -f override.yml -p demo config --services'"
check web 'docker-compose -f compose.yml -f override.yml -p demo up w'
run "export COMPOSE_TEST_ARGS='--file=compose.yml --project-name=demo config --services'"
check web 'docker-compose --file=compose.yml --project-name=demo up w'
run "export COMPOSE_TEST_ARGS='--project-directory . --env-file .env --profile debug config --services'"
check web 'docker-compose --project-directory . --env-file .env --profile debug up w'
run "unset COMPOSE_TEST_ARGS; export COMPOSE_TEST_FILE='project with spaces/compose.yml'"
check web 'docker-compose -f "project with spaces/compose.yml" up w'
check web 'docker-compose -f project\ with\ spaces/compose.yml up w'
run 'unset COMPOSE_TEST_FILE'
for line in 'docker-compose exec web ' 'docker-compose run --rm web ' 'docker-compose -f - up ' 'docker-compose -f https://example.invalid/compose.yml up '; do
    none $line
done
run 'export COMPOSE_TEST_FAIL=yes'
none 'docker-compose up '
run 'unset COMPOSE_TEST_FAIL'
check "$data/file with spaces" "docker-compose -f $data/fi"
check "--file=$data/file with spaces" "docker-compose --file=$data/fi"
check "-f$data/file with spaces" "docker-compose -f$data/fi"
check "$data/file with spaces" "docker-compose --env-file $data/fi"
check "$data" "docker-compose --project-directory ${data:h}/da"

check select-window 'tmux select-w'
check selectw 'tmux sel'
check -L 'tmux -'
check work 'tmux attach -t w'
check db 'tmux a -t '
check db 'tmux kill-session -at d'
check -t 'tmux attach -d -'
check work:1 'tmux selectw -t work:1'
check work:1.1 'tmux select-pane -t work:1.'
check %1 'tmux select-pane -t %'
check mouse 'tmux set -g mou'
check update-environment 'tmux show-options -g upd'
check on 'tmux set -g mouse '
check pane-died 'tmux set-hook -g pane-d'
check after-new-session 'tmux set-hook -g after-n'
check buffer0 'tmux pasteb -b buf'
check tiled 'tmux selectl ti'
check copy-mode-vi 'tmux bind -T copy'
check command 'tmux clearphist -T com'
check bash 'tmux new-window -t work bas'
check db 'tmux ls \; attach -t d'
check "$data/file with spaces" "tmux source-file $data/fi"
check "$data" "tmux new -d -c ${data:h}/da"
run 'export TMUX_TEST_SOCKET=/tmp/tmux-test'
check work 'tmux -S /tmp/tmux-test attach -t w'
run 'unset TMUX_TEST_SOCKET'
for line in 'tmux set -g status-left ' 'tmux set -g mouse on ' 'tmux attach -t work ' 'tmux new -s ' 'tmux kill-server '; do
    none $line
done

check status 'git sta'
check lg 'git l'
check --no-pager 'git --no-p'
check dev 'git checkout d'
check feature 'git switch fea'
check origin/feature 'git log origin/f'
check v1.0 'git show v'
check main..dev 'git log main..d'
check v1.0...main 'git diff v1.0...ma'
check 'new file.txt' 'git add new'
check untracked/ 'git add un'
check changed.txt 'git restore ch'
check changed.txt 'git checkout -- ch'
check staged.txt 'git restore --staged st'
check staged.txt 'git reset HEAD -- st'
check origin 'git push '
check dev 'git push origin d'
check feature 'git fetch origin fe'
check main 'git pull origin ma'
check dev:feature 'git push origin dev:fe'
check dev 'git branch -d d'
check origin/main 'git branch -u origin/m'
check --set-upstream-to=origin/main 'git branch --set-upstream-to=origin/m'
check v1.0 'git tag -d v'
check 'stash@{0}' 'git stash pop '
check push 'git stash pu'
check set-url 'git remote set-u'
check origin 'git remote show '
check user.name 'git config user.n'
check --force-with-lease 'git push --force-w'
check --cached 'git diff --cach'
check --amend 'git commit --am'
check ort 'git merge -s o'
check --untracked-files=normal 'git status --untracked-files=n'
check stash 'git help sta'
check "$data/file with spaces" "git log -- $data/fi"
check "$data/file with spaces" "git commit -F $data/fi"
run 'export GIT_TEST_DIR=/srv/repo'
check dev 'git -C /srv/repo checkout d'
run 'unset GIT_TEST_DIR'
for line in 'git commit -m ' 'git checkout -b ' 'git log -n '; do none $line; done

for command in find grep rg scp lsof sed awk; do
    check "$data/file with spaces" "$command $data/fi"
done
check "$data/file with spaces" "xargs cat $data/fi"
check "$data/file with spaces" "ipset restore -file $data/fi"
check "$data/file with spaces" "tar -czvf $data/fi"
check "$data/file with spaces" "tar xzvf $data/fi"
check "$data/file with spaces" "tar -f $data/fi"
check "--file=$data/file with spaces" "tar --file=$data/fi"
check "$data/file with spaces" "tar -cf archive.tar -- $data/fi"
check "$data/file with spaces" "tar -cfarchive.tar $data/fi"
check "$data/file with spaces" "tar -T $data/fi"
check "$data" "tar -C ${data:h}/da"
check "--directory=$data" "tar --directory=${data:h}/da"
none "tar -C $data/fi"

# Without timeout(1): no container queries for docker cp, no Compose queries.
run "unfunction timeout; path=($tmp/no-timeout); rehash"
none 'docker cp a1b2c3d4e5f6:/ro'
check "$data/file with spaces" "docker cp $data/fi"
none 'docker-compose up '
run "path=(/usr/bin /bin); source $root/test/mocks.zsh"

zpty -d t

# init.zsh in a fresh shell: compinit started by init.zsh itself, and
# MINI_ZSH_OFFICIAL_COMPLETION keeps zsh's own git completion.
for official in '' git; do
    zpty -b t "exec env HOME=$tmp/home TERM=dumb MINI_ZSH_OFFICIAL_COMPLETION=$official zsh -f -i"
    run "PS1='ZCLPROMPT> '; unsetopt promptcr"
    run "source $install_dir/init.zsh; print -r -- \$_comps[git] \$_comps[docker] > $tmp/registered"
    zpty -d t
    (( ++checks ))
    case $official:$(<$tmp/registered) in
        :'_mini_git _mini_docker'|git:'_git _mini_docker') ;;
        *) print -r -- "FAIL: MINI_ZSH_OFFICIAL_COMPLETION=$official -> $(<$tmp/registered)"; (( ++failures )) ;;
    esac
done

print -r -- "$checks checks, $failures failures"
(( failures == 0 ))
