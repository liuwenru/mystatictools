#!/bin/sh
# 真实挂载测试：sshd 服务端容器 + 只有本包静态程序的 chroot 客户端。
#   test/run-test.sh dist/x86_64
# 需要 Docker、宿主 /dev/fuse；容器从 Alpine 仓库安装测试用 sshd/busybox，需联网。
# 只创建本次测试专用的网络和容器，退出时删除。
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dist_dir=$(CDPATH= cd -- "${1:?用法: $0 <dist 目录>}" && pwd)
alpine=${ALPINE_IMAGE:-alpine:3.24}
name=sshfs-test-$$
work=$(mktemp -d "${TMPDIR:-/tmp}/sshfs-test.XXXXXX")

cleanup() {
    docker rm -f "${name}-server" "${name}-client" >/dev/null 2>&1 || true
    docker network rm "$name" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

test -e /dev/fuse || { echo "缺少 /dev/fuse" >&2; exit 1; }
(cd "$dist_dir" && sha256sum -c SHA256SUMS >/dev/null)

ssh-keygen -q -t ed25519 -N '' -C sshfs-test -f "$work/id_ed25519"

docker network create "$name" >/dev/null
docker run -d --name "${name}-server" --network "$name" --network-alias server \
    -v "$work/id_ed25519.pub:/key.pub:ro" "$alpine" sh -c '
        set -e
        apk add -q --no-cache openssh-server openssh-sftp-server >/dev/null
        ssh-keygen -A >/dev/null
        adduser -D -u 2000 test
        echo test:testpass | chpasswd 2>/dev/null
        install -d -m 700 -o test -g test /home/test/.ssh /data
        install -m 600 -o test -g test /key.pub /home/test/.ssh/authorized_keys
        echo hello-from-server > /data/server.txt && chown test:test /data/server.txt
        printf "PasswordAuthentication yes\nKbdInteractiveAuthentication yes\n" \
            > /etc/ssh/sshd_config.d/test.conf
        touch /ready
        exec /usr/sbin/sshd -D -e' >/dev/null

i=0
until docker exec "${name}-server" test -e /ready 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 120 ] || { docker logs "${name}-server"; exit 1; }
    sleep 1
done

# 客户端：外层 Alpine 只负责准备 chroot；测试全部在 chroot 内执行。
docker run --rm --name "${name}-client" --network "$name" \
    --device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor=unconfined \
    -v "$dist_dir:/dist:ro" -v "$test_dir:/test:ro" -v "$work:/work:ro" \
    "$alpine" sh -c '
        set -e
        apk add -q --no-cache busybox-static coreutils >/dev/null
        r=/r
        mkdir -p $r/bin $r/usr/local/bin $r/etc $r/tmp $r/dev $r/proc $r/root/.ssh $r/home/tuser
        cp /bin/busybox.static $r/bin/busybox
        chroot $r /bin/busybox --install -s /bin
        for f in /dist/*; do [ "${f##*/}" = SHA256SUMS ] || cp "$f" $r/usr/local/bin/; done
        ln -s sshfs $r/usr/local/bin/mount.sshfs
        ln -s sshfs $r/usr/local/bin/mount.fuse.sshfs
        chown root:root $r/usr/local/bin/fusermount3
        chmod 4755 $r/usr/local/bin/fusermount3
        printf "root:x:0:0:root:/root:/bin/sh\ntuser:x:1000:1000::/home/tuser:/bin/sh\n" > $r/etc/passwd
        printf "root:x:0:\ntuser:x:1000:\n" > $r/etc/group
        cp /etc/hosts /etc/resolv.conf $r/etc/   # server 由 Docker DNS 解析
        ln -s /proc/self/mounts $r/etc/mtab   # 与常见发行版一致；非 root 卸载需要
        chmod 1777 $r/tmp
        cp /work/id_ed25519 $r/root/.ssh/ && chmod 600 $r/root/.ssh/id_ed25519
        install -d -m 700 -o 1000 -g 1000 $r/home/tuser/.ssh
        install -m 600 -o 1000 -g 1000 /work/id_ed25519 $r/home/tuser/.ssh/
        cp /test/client-test.sh $r/client-test.sh
        mount --bind $r $r   # 根目录须是挂载点，fusermount3 auto_unmount 的检查依赖这一点
        mount --rbind /dev $r/dev
        mount -t proc proc $r/proc
        ! ls $r/lib/ld-musl-* 2>/dev/null
        chroot $r /bin/sh /client-test.sh root
        chroot --userspec=1000:1000 $r /bin/sh /client-test.sh user
        echo "== chroot 测试完成"'

docker exec "${name}-server" sh -c 'cat /data/from-client.txt; ls -l /data'
echo "全部测试通过"
