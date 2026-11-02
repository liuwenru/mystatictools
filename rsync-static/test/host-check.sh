#!/bin/bash
# 宿主机验证（不经容器）：本地 ACL/xattr、与其他版本 rsync 的远程 shell 和守护进程互通、GBK 文件名转换。
# 用法（root，bash）：test/host-check.sh dist/<架构>/rsync /usr/bin/rsync [旧版本 rsync ...]
# 需要 setfacl、setfattr/getfattr、iconv；GBK 测试用系统 /usr/bin/rsync（glibc）作对端。
# 全部在 /var/tmp 下的独立临时目录进行，守护进程只监听 127.0.0.1 的随机端口，结束后删除临时目录。
set -u
NEW=$(readlink -f "$1"); shift
peers=(); for P in "$@"; do peers+=("$(readlink -f "$P")"); done
W=$(mktemp -d /var/tmp/rsync-host.XXXXXX); cd $W
pass=0; fail=0
ok(){ if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }
printf '#!/bin/sh\nwhile [ "$1" = -l ]; do shift 2; done\nshift\nexec /bin/sh -c "$*"\n' > rsh; chmod +x rsh
mkdir src; echo hello > src/f; dd if=/dev/urandom of=src/big bs=1M count=8 status=none; ln -s f src/l; ln src/f src/h; mkdir src/d
setfacl -m u:4321:rwx src/f; setfattr -n user.k -v v src/f; setfattr -n trusted.k -v t src/f; mkdir src/中文; echo cn > src/中文/文件
FULL=1
same(){ diff -r --no-dereference src "$1" >/dev/null && [ "$(stat -c %i $1/f)" = "$(stat -c %i $1/h)" ] || return 1
  [ $FULL = 1 ] || return 0
  [ "$(getfacl -cp src/f)" = "$(getfacl -cp $1/f)" ] && [ "$(getfattr -d -m - src/f 2>/dev/null | tail -n +2)" = "$(getfattr -d -m - $1/f 2>/dev/null | tail -n +2)" ]; }
waitport(){ for i in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null && return 0; sleep 0.1; done; return 1; }
ok "静态版本 env -i 运行" "env -i $NEW --version | head -1 | grep -q '3.5.1'"
env -i $NEW -aHAX src/ local/; ok "宿主文件系统 -aHAX（ACL、user.*、trusted.* xattr、硬链接）" "same local"
for P in "${peers[@]}"; do
  v=$($P --version | head -1 | awk '{print $3}')
  # 对端不支持 ACL/xattr（如 3.1.2 旧二进制）时只比较内容、链接和硬链接
  if $P --version | grep -qE 'no ACLs|no xattrs'; then F=-aH; FULL=0; else F=-aHAX; FULL=1; fi
  rm -rf a b c d; 
  env -i PATH=/usr/bin:/bin $NEW ${F}z -e ./rsh --rsync-path=$P src/ h:$W/a/ ; ok "静态 → 对端 $v（远程 shell）" "same a"
  env -i PATH=/usr/bin:/bin $NEW ${F}z -e ./rsh --rsync-path=$P h:$W/src/ b/ ; ok "静态 ← 对端 $v（远程 shell）" "same b"
  env -i PATH=/usr/bin:/bin $P ${F}z -e ./rsh --rsync-path=$NEW src/ h:$W/c/ ; ok "对端 $v → 静态（远程 shell）" "same c"
  # 守护进程互通
  printf 'use chroot = no\nmunge symlinks = no\nuid = root\ngid = root\n[m]\npath = %s\nread only = no\n' $W > rsyncd.conf
  for D in $NEW $P; do
    port=$((20000 + RANDOM % 20000)); $D --daemon --no-detach --config=rsyncd.conf --address=127.0.0.1 --port=$port & dpid=$!; waitport $port || echo "daemon $D not listening on $port"
    C=$([ $D = $NEW ] && echo $P || echo $NEW); rm -rf $W/dd
    env -i PATH=/usr/bin:/bin $C -aHz src/ rsync://127.0.0.1:$port/m/dd/
    ok "守护进程 $([ $D = $NEW ] && echo 静态 || echo $v)，客户端 $([ $C = $NEW ] && echo 静态 || echo $v)" "diff -r --no-dereference src $W/dd >/dev/null"
    kill $dpid; wait $dpid 2>/dev/null
  done
done
# GBK：静态版作为 UTF-8 一端，系统 glibc rsync 作为 GBK 一端；以及反过来
rm -rf g1 g2 g3; mkdir g1
env -i LANG=C.UTF-8 $NEW -r --iconv=UTF-8,GBK -e ./rsh --rsync-path=/usr/bin/rsync src/中文/ h:$W/g1/x/
ok "静态 UTF-8 → glibc 对端 GBK" "[ -f \"g1/x/\$(printf 文件 | iconv -f UTF-8 -t GBK)\" ] && [ ! -e g1/x/文件 ]"
env -i LANG=C.UTF-8 /usr/bin/rsync -r --iconv=GBK,UTF-8 -e ./rsh --rsync-path=$NEW g1/x/ h:$W/g2/
ok "glibc GBK → 静态 UTF-8" "[ -f g2/文件 ]"
env -i LANG=C.UTF-8 $NEW -r --iconv=GBK,UTF-8 -e ./rsh --rsync-path=/usr/bin/rsync g1/x/ h:$W/g3/
ok "静态作为 GBK 一端 → glibc 对端 UTF-8" "[ -f g3/文件 ]"
echo "host-check: $pass passed, $fail failed ($(uname -m), $(uname -r))"
cd /; rm -rf $W
[ $fail = 0 ]
