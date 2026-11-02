"""Export matching upstream sources and dependency license notices."""
from pathlib import Path
import shutil

sources = Path('/out/sources')
sources.mkdir()
shutil.copy('/build/neovim.tar.gz', sources)
shutil.copytree('/build/downloads', sources / 'dependencies')
licenses = Path('/out/nvim/licenses')
for dependency in Path('.deps/build/src').iterdir():
    if not dependency.is_dir():
        continue
    for notice in dependency.iterdir():
        if notice.is_file() and notice.name.upper().startswith(('LICENSE', 'COPYING', 'COPYRIGHT')):
            target = licenses / dependency.name / notice.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(notice, target)
