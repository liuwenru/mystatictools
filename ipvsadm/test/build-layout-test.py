#!/usr/bin/env python3
"""用 mock Docker 验证 build.sh 参数和导出路径；不代表真实镜像构建通过。"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

project = Path(__file__).resolve().parents[1]
parent = Path('/tmp/opencode') if Path('/tmp/opencode').is_dir() else None
with tempfile.TemporaryDirectory(prefix='ipvsadm-build-test-', dir=parent) as temporary:
    root = Path(temporary)
    shutil.copy2(project / 'build.sh', root / 'build.sh')
    mock = root / 'docker'
    mock.write_text('''#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$DOCKER_LOG"
case "$1" in
    buildx) exit 0 ;;
    create) echo test-container ;;
    cp) cp "$FIXTURES/${2##*/}" "$3" ;;
    rm) exit 0 ;;
    *) exit 99 ;;
esac
''')
    mock.chmod(0o755)
    environment = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}',
                       DOCKER_LOG=str(root / 'docker.log'))
    for arch, alias in [('amd64', 'linux/amd64'), ('arm64', 'aarch64')]:
        environment['FIXTURES'] = str(project / 'dist' / arch)
        subprocess.run(['bash', str(root / 'build.sh'), alias, 'ipvsadm:test'],
                       cwd=root, env=environment, check=True, capture_output=True, timeout=30)
        output = root / 'dist' / arch
        for name in ['ipvsadm', 'ipvsadm-save', 'ipvsadm-restore']:
            assert (output / name).read_bytes() == (project / 'dist' / arch / name).read_bytes()
        subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=output,
                       check=True, capture_output=True, timeout=30)
    log = (root / 'docker.log').read_text()
    for arch in ['amd64', 'arm64']:
        assert f'buildx build --builder default --platform linux/{arch} -t ipvsadm:test --load .' in log
    invalid = subprocess.run(['bash', str(root / 'build.sh'), 'linux/ppc64le'],
                             cwd=root, env=environment, capture_output=True, timeout=30)
    assert invalid.returncode == 2
    assert (root / 'docker.log').read_text() == log
print('PASS mock Docker: 两种架构导出、校验清单、默认 builder、非法参数拒绝')
