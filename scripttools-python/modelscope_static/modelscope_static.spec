# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path
import os
import sys

from PyInstaller.utils.hooks import collect_data_files, collect_submodules, copy_metadata

# The umbrella SDK is not imported: its inference/training plugins are out of scope.
# Keep its version/license metadata and the official Hub download implementation.
datas = collect_data_files('modelscope_hub')
for distribution in (
    'modelscope', 'modelscope-hub', 'requests', 'urllib3', 'certifi',
    'charset-normalizer', 'idna', 'tqdm', 'filelock', 'cryptography', 'cffi',
):
    datas += copy_metadata(distribution)
datas.append((str(Path(sys.base_prefix) / 'lib/python3.12/LICENSE.txt'), 'licenses/python'))
libgcc_dir = Path(os.environ['MODELSCOPE_BUILD_LIBGCC_DIR'])
datas.append((str(libgcc_dir / 'usr/share/doc/libgcc-4.8.5'), 'licenses/libgcc'))
pyinstaller_source = Path(os.environ['MODELSCOPE_BUILD_PYINSTALLER_SOURCE'])
datas.append((str(pyinstaller_source / 'COPYING.txt'), 'licenses/pyinstaller'))
datas.append((str(pyinstaller_source / 'bootloader/zlib/README'), 'licenses/zlib'))
datas.append((str(pyinstaller_source / 'bootloader/zlib/zlib.h'), 'licenses/zlib'))

a = Analysis(
    ['launcher.py'],
    pathex=[],
    binaries=[(str(libgcc_dir / 'lib64/libgcc_s.so.1'), '.')],
    datas=datas,
    hiddenimports=collect_submodules('modelscope_hub'),
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['modelscope', 'torch', 'tensorflow', 'transformers', 'datasets'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, a.binaries, a.datas, [],
    name='modelscope',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    runtime_tmpdir=None,
    console=True,
)
