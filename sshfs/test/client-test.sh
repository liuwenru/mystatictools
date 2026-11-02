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
