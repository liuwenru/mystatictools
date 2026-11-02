# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path
import os
import sys

from PyInstaller.utils.hooks import collect_submodules

# launcher.py runs the external benchmark_response_stats.py, which may be edited
# later without a rebuild. Bundle the whole standard library so new stdlib
# imports keep working. GUI, test suites and packaging tools are left out.
# crypt/_crypt (deprecated, removed in 3.13) need the host's libcrypt.so.1,
# which PyInstaller does not bundle and RHEL 9/Fedora lack by default.
excluded = {
    'tkinter', '_tkinter', 'turtle', 'turtledemo', 'idlelib', 'test', 'ensurepip',
    'venv', 'lib2to3', 'crypt', '_crypt', '__phello__', 'antigravity', 'this',
}


def keep(name):
    return not any(part in ('test', 'tests', 'idle_test') for part in name.split('.')[1:])


hiddenimports = []
for module in sorted(sys.stdlib_module_names - excluded):
    hiddenimports += collect_submodules(module, filter=keep)

pyinstaller_source = Path(os.environ['BENCHMARK_BUILD_PYINSTALLER_SOURCE'])
datas = [
    (str(Path(sys.base_prefix) / 'lib/python3.12/LICENSE.txt'), 'licenses/python'),
    (str(pyinstaller_source / 'COPYING.txt'), 'licenses/pyinstaller'),
    (str(pyinstaller_source / 'bootloader/zlib/README'), 'licenses/zlib'),
    (str(pyinstaller_source / 'bootloader/zlib/zlib.h'), 'licenses/zlib'),
]

binaries = []
if os.environ.get('BENCHMARK_BUILD_LIBGCC_DIR'):
    libgcc_dir = Path(os.environ['BENCHMARK_BUILD_LIBGCC_DIR'])
    binaries.append((str(libgcc_dir / 'lib64/libgcc_s.so.1'), '.'))
    datas.append((str(libgcc_dir / 'usr/share/doc/libgcc-4.8.5'), 'licenses/libgcc'))

a = Analysis(
    ['launcher.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=sorted(excluded),
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, a.binaries, a.datas, [],
    name='benchmark_response_stats',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    runtime_tmpdir=None,
    console=True,
)
