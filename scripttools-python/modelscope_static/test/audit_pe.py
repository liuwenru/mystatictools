#!/usr/bin/env python3
"""Check x64 PE architecture and the DLL closure of a onefile Windows build."""

import argparse
import json
import os
from pathlib import Path
import tempfile

import pefile
from PyInstaller.archive.readers import CArchiveReader

parser = argparse.ArgumentParser()
parser.add_argument('binary', type=Path)
args = parser.parse_args()
binary = args.binary.resolve(strict=True)
results = Path(__file__).resolve().parent / 'results'
results.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix='pe-windows-amd64-', dir=results))
archive = CArchiveReader(str(binary))
entries = [(binary.name, binary.read_bytes())]
for name, entry in archive.toc.items():
    if entry[-1] == 'b':
        data = archive.extract(name)
        if data.startswith(b'MZ'):
            entries.append((name, data))
embedded = {Path(name).name.lower() for name, _ in entries}
assert 'python312.dll' in embedded
assert 'vcruntime140.dll' in embedded and 'vcruntime140_1.dll' in embedded
assert 'certifi/cacert.pem' in {name.replace('\\', '/') for name in archive.toc}

system32 = Path(os.environ['SystemRoot']) / 'System32'
report = []
for name, data in entries:
    pe = pefile.PE(data=data)
    assert pe.FILE_HEADER.Machine == 0x8664, (name, hex(pe.FILE_HEADER.Machine))
    assert pe.OPTIONAL_HEADER.Magic == 0x20b, (name, 'not PE32+')
    if name == binary.name:
        assert pe.OPTIONAL_HEADER.Subsystem == 3, 'Expected console executable'
    imports = sorted({
        item.dll.decode('ascii').lower()
        for attr in ('DIRECTORY_ENTRY_IMPORT', 'DIRECTORY_ENTRY_DELAY_IMPORT')
        for item in getattr(pe, attr, [])
    })
    for dll in imports:
        if dll.startswith(('python', 'vcruntime', 'msvcp', 'libssl', 'libcrypto', 'libffi')):
            assert dll in embedded, (name, 'unbundled vendor DLL', dll)
        else:
            assert (dll in embedded or dll.startswith(('api-ms-win-', 'ext-ms-'))
                    or (system32 / dll).is_file()), (name, 'unresolved DLL', dll)
    report.append({'file': name, 'machine': 'AMD64', 'imports': imports})
    pe.close()

(work / 'summary.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(f'PASS {len(report)} x64 PE files; DLL imports resolved; Python, VC runtime and CA bundled')
print(f'Results: {work}')
