#!/bin/sh
# 在只有静态 busybox + 本包程序的 chroot 内执行（由 run-test.sh 调用）。
#   client-test.sh root|user
set -eu
export PATH=/usr/local/bin:/bin
mode=$1
if [ "$mode" = root ]; then HOME=/root; else HOME=/home/tuser; fi
export HOME
cd "$HOME"
key=$HOME/.ssh/id_ed25519
ssh_opts="StrictHostKeyChecking=accept-new,UserKnownHostsFile=$HOME/.ssh/known_hosts"
remote=test@server:/data

step() { echo "== [$mode] $*"; }
mounted() { grep -q " $1 fuse.sshfs " /proc/mounts; }
umount_fuse() {
    fusermount3 -u "$1"
    ! mounted "$1" || { echo "卸载失败: $1" >&2; exit 1; }
}

# 读写、目录、改名、符号链接、权限、截断、大文件、statvfs
file_ops() {
    m=$1 p=$2
    test "$(cat "$m/server.txt")" = hello-from-server
    echo "$p" > "$m/$p.txt"
    test "$(cat "$m/$p.txt")" = "$p"
    mkdir "$m/$p.d"
    mv "$m/$p.txt" "$m/$p.d/f"
    ln -s f "$m/$p.d/link"
    test "$(readlink "$m/$p.d/link")" = f
    test "$(cat "$m/$p.d/link")" = "$p"
    chmod 640 "$m/$p.d/f"
    test "$(stat -c %a "$m/$p.d/f")" = 640
    truncate -s 2 "$m/$p.d/f"
    test "$(wc -c < "$m/$p.d/f")" -eq 2
    dd if=/dev/urandom of="/tmp/$p.big" bs=1M count=16 2>/dev/null
    cp "/tmp/$p.big" "$m/$p.big"
    cmp "/tmp/$p.big" "$m/$p.big"
    df "$m" | tail -1
    rm -r "$m/$p.d" "$m/$p.big" "/tmp/$p.big"
}

if [ "$mode" = root ]; then
    test ! -e /lib
    sshfs --version

    step "密钥认证挂载与文件操作"
    mkdir -p /mnt/a
    sshfs -o "$ssh_opts,IdentityFile=$key" "$remote" /mnt/a
    file_ops /mnt/a root
    echo from-client > /mnt/a/from-client.txt
    umount_fuse /mnt/a

    step "压缩/重连/多连接/idmap/allow_other"
    sshfs -C -o "$ssh_opts,IdentityFile=$key,reconnect,ServerAliveInterval=5,max_conns=4,idmap=user,allow_other" \
        "$remote" /mnt/a
    file_ops /mnt/a rootc
    test "$(stat -c %u /mnt/a/server.txt)" -eq 0   # idmap=user 远端 test 映射为本地当前用户
    umount_fuse /mnt/a

    step "password_stdin（禁用公钥）"
    echo testpass | sshfs -o "$ssh_opts,password_stdin,PubkeyAuthentication=no" "$remote" /mnt/a
    test "$(cat /mnt/a/server.txt)" = hello-from-server
    umount_fuse /mnt/a

    step "ssh-agent + ssh-add"
    eval "$(ssh-agent -s)" >/dev/null
    mv "$key" /tmp/agent-key
    ssh-add /tmp/agent-key
    ssh-add -l
    sshfs -o "$ssh_opts" "$remote" /mnt/a
    test "$(cat /mnt/a/server.txt)" = hello-from-server
    umount_fuse /mnt/a
    mv /tmp/agent-key "$key"
    ssh-agent -k >/dev/null

    step "mount.sshfs 与 mount.fuse3 'sshfs#' 形式"
    mount.sshfs "$remote" /mnt/a -o "$ssh_opts,IdentityFile=$key"
    test "$(cat /mnt/a/server.txt)" = hello-from-server
    umount_fuse /mnt/a
    mount.fuse3 "sshfs#$remote" /mnt/a -o "$ssh_opts,IdentityFile=$key"
    test "$(cat /mnt/a/server.txt)" = hello-from-server
    umount_fuse /mnt/a

    # 3.7.6 默认 contain_symlinks：绝对路径或含 .. 的链接 readlink 返回 EPERM
    step "符号链接：默认 contain_symlinks"
    sshfs -o "$ssh_opts,IdentityFile=$key" "$remote" /mnt/a
    s=/mnt/a/sl
    test "$(readlink $s/rel)" = ok.txt && test "$(cat $s/rel)" = ok
    for l in dotdot abs inbase; do
        test -L "$s/$l"   # 链接本身仍可见
        ! readlink "$s/$l" 2>/dev/null
        cat "$s/$l" 2>&1 | grep -q 'Operation not permitted'
    done
    umount_fuse /mnt/a

    step "符号链接：no_contain_symlinks（目标原样交给本地解析）"
    sshfs -o "$ssh_opts,IdentityFile=$key,no_contain_symlinks" "$remote" /mnt/a
    test "$(readlink $s/dotdot)" = ../server.txt && test "$(cat $s/dotdot)" = hello-from-server
    test "$(readlink $s/abs)" = /etc/passwd
    grep -q '^tuser:' $s/abs   # 绝对链接读到的是本地 /etc/passwd，不是远端
    umount_fuse /mnt/a

    step "符号链接：follow_symlinks（由服务端解析）"
    sshfs -o "$ssh_opts,IdentityFile=$key,follow_symlinks" "$remote" /mnt/a
    test ! -L $s/abs && grep -q '^test:x:2000:' $s/abs   # 远端 /etc/passwd
    test "$(cat $s/dotdot)" = hello-from-server
    umount_fuse /mnt/a

    step "符号链接：transform_symlinks 与 contain 冲突"
    sshfs -o "$ssh_opts,IdentityFile=$key,transform_symlinks" "$remote" /mnt/a 2>/tmp/sshfs.err
    grep -q no_contain_symlinks /tmp/sshfs.err   # 启动时提示加 no_contain_symlinks
    cat $s/inbase 2>&1 | grep -q 'Operation not permitted'   # 改写成 ../server.txt 后被拒绝
    umount_fuse /mnt/a
    sshfs -o "$ssh_opts,IdentityFile=$key,transform_symlinks,no_contain_symlinks" "$remote" /mnt/a
    test "$(readlink $s/inbase)" = ../server.txt && test "$(cat $s/inbase)" = hello-from-server
    umount_fuse /mnt/a
    rm /tmp/sshfs.err

    step "ssh-keyscan"
    ssh-keyscan -t ed25519 server 2>/dev/null | grep -q ssh-ed25519

    # 供 user 阶段验证 /etc/fuse.conf 生效
    echo user_allow_other > /etc/fuse.conf
    mkdir -p /mnt/u && chown 1000:1000 /mnt/u
else
    test "$(id -u)" -eq 1000
    m=/mnt/u

    step "非 root 经 setuid fusermount3 挂载"
    sshfs -o "$ssh_opts,IdentityFile=$key" "$remote" "$m"
    file_ops "$m" user
    umount_fuse "$m"

    step "非 root allow_other（读取 /etc/fuse.conf user_allow_other）"
    sshfs -o "$ssh_opts,IdentityFile=$key,allow_other" "$remote" "$m"
    umount_fuse "$m"

    step "auto_unmount：sshfs 被杀后自动卸载"
    sshfs -f -o "$ssh_opts,IdentityFile=$key,auto_unmount" "$remote" "$m" &
    pid=$!
    i=0; until mounted "$m"; do i=$((i + 1)); [ $i -lt 50 ] || exit 1; sleep 0.2; done
    kill -9 "$pid"
    i=0; while mounted "$m"; do i=$((i + 1)); [ $i -lt 50 ] || { echo "未自动卸载" >&2; exit 1; }; sleep 0.2; done
fi
step "通过"
