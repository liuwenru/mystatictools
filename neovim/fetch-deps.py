"""Download the upstream-pinned dependencies with retries, preserving SHA-256 checks."""
import hashlib
import pathlib
import re
import subprocess

manifest = pathlib.Path('cmake.deps/deps.txt')
text = manifest.read_text()
required = {'LIBUV', 'LUAJIT', 'UNIBILIUM', 'LUV', 'LPEG', 'LUA_COMPAT53',
            'UTF8PROC', 'TREESITTER', 'TREESITTER_C', 'TREESITTER_LUA',
            'TREESITTER_VIM', 'TREESITTER_VIMDOC', 'TREESITTER_QUERY', 'TREESITTER_MARKDOWN'}
destination = pathlib.Path('/build/downloads')
destination.mkdir(parents=True, exist_ok=True)
for name, url in re.findall(r'^(\w+)_URL (\S+)', text, re.M):
    if name not in required:
        continue
    expected = re.search(rf'^{name}_SHA256 (\S+)', text, re.M)[1]
    # GitHub's archive redirect and raw endpoint are less reliable on some networks.
    url = re.sub(r'https://github.com/([^/]+/[^/]+)/archive/(.+)\.tar\.gz',
                 r'https://codeload.github.com/\1/tar.gz/\2', url)
    url = re.sub(r'https://github.com/([^/]+/[^/]+)/raw/',
                 r'https://raw.githubusercontent.com/\1/', url)
    archive = destination / (name.lower() + '.tar.gz')
    subprocess.run(['curl', '-fL', '--retry', '4', '--retry-all-errors',
                    '--connect-timeout', '30', '--max-time', '600',
                    '-o', str(archive), url], check=True)
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual != expected:
        raise RuntimeError(f'{name}: SHA-256 mismatch: {actual} != {expected}')
    text = re.sub(rf'^{name}_URL \S+', f'{name}_URL {archive.as_uri()}', text, flags=re.M)
manifest.write_text(text)
