#!/usr/bin/env python3
"""检查两种架构；仅在独立 netns/chroot 中操作本机架构的 IPVS。"""
import argparse
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


def run(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, timeout=30, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{args}: exit {result.returncode}\n{result.stdout}{result.stderr}")
    return result.stdout


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--static-only', action='store_true', help='不执行内核功能测试')
parser.add_argument('--net-parent', help=argparse.SUPPRESS)
args = parser.parse_args()
project = Path(__file__).resolve().parents[1]

if args.net_parent is None:
    for directory in [project / 'src', project / 'dist/amd64', project / 'dist/arm64']:
        run(['sha256sum', '-c', 'SHA256SUMS'], cwd=directory)
    with tarfile.open(project / 'src/ipvsadm.tar.gz') as source:
        for arch, machine in [('amd64', 'Advanced Micro Devices X86-64'), ('arm64', 'AArch64')]:
            directory = project / 'dist' / arch
            binary = directory / 'ipvsadm'
            header = run(['readelf', '-hW', str(binary)])
            assert machine in header, header
            assert 'INTERP' not in run(['readelf', '-lW', str(binary)])
            assert 'NEEDED' not in run(['readelf', '-dW', str(binary)])
            for name in ['ipvsadm-save', 'ipvsadm-restore']:
                script = directory / name
                assert os.access(script, os.X_OK), script
                assert script.read_bytes() == source.extractfile(f'ipvsadm-1.31/{name}').read()
                run(['bash', '-n', str(script)])
            print(f'PASS {arch}: 架构、静态 ELF、SHA256、原版辅助脚本及语法', flush=True)
    run(['bash', '-n', str(project / 'build.sh')])
    if args.static_only:
        sys.exit(0)
    if os.geteuid() != 0:
        raise SystemExit('功能测试需要 root、CAP_SYS_ADMIN/CAP_NET_ADMIN；未执行功能测试')
    # unshare 失败直接报错，禁止退回宿主网络命名空间。
    result = subprocess.run([
        'unshare', '--net', '--', sys.executable, str(Path(__file__).resolve()),
        '--net-parent', os.readlink('/proc/self/ns/net'),
    ], timeout=180)
    sys.exit(result.returncode)

assert os.readlink('/proc/self/ns/net') != args.net_parent, '拒绝在宿主网络中测试'
arch = {'x86_64': 'amd64', 'aarch64': 'arm64'}.get(platform.machine())
if arch is None:
    raise SystemExit(f'未支持的本机架构: {platform.machine()}')
directory = project / 'dist' / arch
# 后端地址必须有单播路由；所有网络设置仅发生在新建的 netns 内。
run(['ip', 'link', 'set', 'lo', 'up'])
run(['ip', 'route', 'add', '192.0.2.0/24', 'dev', 'lo'])
temp_parent = Path('/tmp/opencode') if Path('/tmp/opencode').is_dir() else None
with tempfile.TemporaryDirectory(prefix='ipvsadm-test-', dir=temp_parent) as temporary:
    root = Path(temporary)
    (root / 'usr/sbin').mkdir(parents=True)
    shutil.copy2(directory / 'ipvsadm', root / 'usr/sbin/ipvsadm')
    chroot = shutil.which('chroot')

    def ipvs(*options, **kwargs):
        return run([chroot, str(root), '/usr/sbin/ipvsadm', *options], **kwargs)

    # 此时 chroot 中只有一个静态 ELF，没有共享库、shell、modprobe、配置文件。
    assert 'v1.31' in ipvs('--version')
    assert 'ipvsadm' in ipvs('--help')
    ipvs('-A', '-t', '192.0.2.10:8080', '-s', 'rr')
    ipvs('-a', '-t', '192.0.2.10:8080', '-r', '192.0.2.20:8080', '-m', '-w', '2')
    saved = ipvs('-S', '-n')
    assert '192.0.2.10:8080' in saved and '192.0.2.20:8080' in saved, saved
    ipvs('-C')
    assert not ipvs('-S', '-n').strip()
    ipvs('-R', input=saved)
    assert ipvs('-S', '-n') == saved
    ipvs('-d', '-t', '192.0.2.10:8080', '-r', '192.0.2.20:8080')
    ipvs('-D', '-t', '192.0.2.10:8080')
    assert not ipvs('-S', '-n').strip()
    print(f'PASS {arch} 原生: 最小 chroot 版本、帮助、服务/后端增删、保存恢复', flush=True)

    # 再加入真实辅助脚本及其宿主 Bash/工具依赖，测试原版脚本，不改写 PATH。
    for name in ['bash', 'grep', 'basename']:
        host = Path(shutil.which(name))
        target = root / 'bin' / name
        target.parent.mkdir(exist_ok=True)
        shutil.copy2(host, target)
        dependencies = run(['ldd', str(host)])
        for library in re.findall(r'(/[^\s()]+)', dependencies):
            destination = root / library.lstrip('/')
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(library, destination)
    for name in ['ipvsadm-save', 'ipvsadm-restore']:
        shutil.copy2(directory / name, root / 'usr/sbin' / name)
    run([chroot, str(root), '/usr/sbin/ipvsadm-restore'], input='# test comment\n' + saved)
    assert run([chroot, str(root), '/usr/sbin/ipvsadm-save', '-n']) == saved
    # restore 必须清除旧规则，而不是追加。
    run([chroot, str(root), '/usr/sbin/ipvsadm-restore'], input='# empty rules\n')
    assert not ipvs('-S', '-n').strip()
    print(f'PASS {arch} 原生: 原版 save/restore 脚本往返、注释过滤、清空旧规则', flush=True)
print('其他架构仅完成静态检查；未验证转发流量或真实目标机。', flush=True)
