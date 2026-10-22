"""Fetch pinned extras; retain source archives and upstream binaries for provenance."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tarfile

arch = sys.argv[1]
root = pathlib.Path('/out/nvim')
sources = pathlib.Path('/out/sources/extras')
sources.mkdir(parents=True, exist_ok=True)
(root / 'libexec').mkdir(parents=True, exist_ok=True)
manifest = pathlib.Path('/build/extras.json')
shutil.copy(manifest, sources / 'extras.json')
for item in json.loads(manifest.read_text()):
    if item.get('arch', arch) != arch:
        continue
    name, kind = item['name'], item['kind']
    suffix = '.tar.xz' if item['url'].endswith('.xz') else '.tar.gz'
    archive = sources / (name + '-' + kind + (suffix if kind != 'binary' else '.bin'))
    subprocess.run(['curl', '-fL', '--retry', '4', '--retry-all-errors',
                    '--connect-timeout', '30', '--max-time', '600',
                    '-o', str(archive), item['url']], check=True)
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual != item['sha256']:
        raise RuntimeError(f'{name} {kind}: SHA256 {actual} != {item["sha256"]}')
    if kind == 'binary':
        shutil.copy(archive, root / 'libexec' / name)
        (root / 'libexec' / name).chmod(0o755)
    elif kind == 'binary-tar':
        with tarfile.open(archive) as tar:
            matches = [m for m in tar.getmembers() if m.isfile() and pathlib.PurePosixPath(m.name).name == name]
            if len(matches) != 1:
                raise RuntimeError(f'{archive}: expected exactly one {name} executable')
            with tar.extractfile(matches[0]) as src, (root / 'libexec' / name).open('wb') as dst:
                shutil.copyfileobj(src, dst)
        (root / 'libexec' / name).chmod(0o755)
    else:
        destination = (root / 'share/nvim/runtime/pack/offline/opt' / name
                       if kind == 'plugin' else pathlib.Path('/build') / name)
        destination.mkdir(parents=True, exist_ok=True)
        subprocess.run(['tar', '-xf', str(archive), '--strip-components=1', '-C', str(destination)], check=True)
        for notice in destination.iterdir():
            if notice.is_file() and notice.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE', 'COPYRIGHT')):
                target = root / 'licenses' / name / notice.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(notice, target)
shutil.copy(manifest, root / 'EXTRAS-VERSIONS.json')
