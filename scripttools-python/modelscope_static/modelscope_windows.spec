# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path
import sys

from PyInstaller.utils.hooks import collect_data_files, collect_submodules, copy_metadata

# Keep Windows-specific DLL handling separate from the validated Linux spec.
datas = collect_data_files('modelscope_hub')
for distribution in (
    'modelscope', 'modelscope-hub', 'requests', 'urllib3', 'certifi',
    'charset-normalizer', 'idna', 'tqdm', 'filelock', 'cryptography', 'cffi', 'colorama',
):
    datas += copy_metadata(distribution)
python_root = Path(sys.base_prefix)
datas.append((str(python_root / 'LICENSE.txt'), 'licenses/python'))
datas += copy_metadata('pyinstaller')
binaries = [(str(path), '.') for path in python_root.glob('vcruntime*.dll')]

a = Analysis(
    ['launcher.py'],
    pathex=[],
    binaries=binaries,
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
    pyz, a.scripts, a.binaries, a.datas, [('X utf8', None, 'OPTION')],
    name='modelscope',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    runtime_tmpdir=None,
    console=True,
    uac_admin=False,
    uac_uiaccess=False,
)
