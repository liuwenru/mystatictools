#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

if [[ $(uname -s) != Linux ]]; then
    echo 'error: this script builds Linux only; use a native Linux host.' >&2
    exit 1
fi
case "$(uname -m)" in
    x86_64)
        arch=amd64
        target=x86_64-unknown-linux-gnu
        wheel_platform=manylinux2014_x86_64
        python_sha256=6d7521138fd33afddc1ccd08abb007d9a2829e38117c2576f9efdc0ec73ce772
        rpm_arch=x86_64
        rpm_base=7.9.2009
        libgcc_sha256=cb1967fba485ad3da345e33018c0e8b367359f251c6b1a8847a4976579d74ffa
        zig_target=x86_64-linux-gnu.2.17
        bootloader_platform=Linux-64bit-intel
        ;;
    aarch64)
        arch=aarch64
        target=aarch64-unknown-linux-gnu
        wheel_platform=manylinux2014_aarch64
        python_sha256=b4567aa5a11f51b540c4dfd9e082ebf23e554f8ac17b85caa6cea23e83693394
        rpm_arch=aarch64
        rpm_base=altarch/7.9.2009
        libgcc_sha256=4f44c5be70ed9d8d74c2a616cde92a842b15eefaccd766959e5fbd7fbe965d2d
        zig_target=aarch64-linux-gnu.2.17
        bootloader_platform=Linux-64bit-arm
        ;;
    *) echo "error: unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

archive="cpython-3.12.15+20261021-${target}-install_only_stripped.tar.gz"
python_dir=".cache/python/$arch"
wheel_dir=".cache/wheels/$arch"
venv=".venv-$arch"
output="dist/linux-$arch"
mkdir -p .cache/python "$python_dir" "$wheel_dir" "$output" "build/$arch"
export PYTHONNOUSERSITE=1
unset PYTHONHOME PYTHONPATH

if [[ ! -f ".cache/python/$archive" ]]; then
    curl -fL --retry 3 --connect-timeout 20 \
        "https://github.com/astral-sh/python-build-standalone/releases/download/20261021/${archive/+/%2B}" \
        -o ".cache/python/$archive.part"
    mv ".cache/python/$archive.part" ".cache/python/$archive"
fi
echo "$python_sha256  .cache/python/$archive" | sha256sum -c -
if [[ ! -f "$python_dir/.extracted" ]]; then
    # SSHFS may not support setting ownership/timestamps on symlinks.
    tar --no-same-owner --touch -xzf ".cache/python/$archive" -C "$python_dir"
    touch "$python_dir/.extracted"
fi

# cryptography's Rust extension needs libgcc_s. Do not bundle the build host's
# potentially much newer glibc-linked copy. Extract only this fixed runtime RPM.
libgcc_dir=".cache/libgcc/$arch"
rpm="libgcc-4.8.5-44.el7.$rpm_arch.rpm"
mkdir -p "$libgcc_dir"
if [[ ! -f "$libgcc_dir/$rpm" ]]; then
    curl -fL --retry 3 --connect-timeout 20 \
        "https://vault.centos.org/$rpm_base/os/$rpm_arch/Packages/$rpm" \
        -o "$libgcc_dir/$rpm.part"
    mv "$libgcc_dir/$rpm.part" "$libgcc_dir/$rpm"
fi
echo "$libgcc_sha256  $libgcc_dir/$rpm" | sha256sum -c -
if [[ ! -f "$libgcc_dir/.extracted" ]]; then
    rpm2cpio "$libgcc_dir/$rpm" | (cd "$libgcc_dir"; cpio -idu --no-preserve-owner)
    touch "$libgcc_dir/.extracted"
fi
export MODELSCOPE_BUILD_LIBGCC_DIR="$PWD/$libgcc_dir"

if [[ ! -x "$venv/bin/python" ]]; then
    "$python_dir/python/bin/python3" -m venv --copies "$venv"
fi
python="$venv/bin/python"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_CACHE_DIR="$PWD/.cache/pip/$arch"
export PYINSTALLER_CONFIG_DIR="$PWD/build/$arch/cache"

# Limit wheels to glibc 2.17-compatible builds, even on a newer build host.
"$python" -m pip download --index-url https://pypi.org/simple \
    --retries 3 --timeout 60 --require-hashes --only-binary=:all: \
    --platform "$wheel_platform" --dest "$wheel_dir" -r requirements-linux.lock
"$python" -m pip install --no-index --find-links "$wheel_dir" \
    --require-hashes --only-binary=:all: -r requirements-linux.lock
"$python" -m pip check

# The upstream Linux bootloader itself requires the host's libz.so.1 before it
# can unpack anything. Rebuild it with bundled static zlib and a glibc-2.17 target.
# Zig lives only in the private build venv; no host compiler/toolchain is changed.
"$python" -m pip download --index-url https://pypi.org/simple \
    --retries 3 --timeout 60 --require-hashes --only-binary=:all: \
    --platform "$wheel_platform" --platform "manylinux2010_$rpm_arch" \
    --dest "$wheel_dir" -r requirements-bootloader.lock
"$python" -m pip install --no-index --find-links "$wheel_dir" \
    --require-hashes --only-binary=:all: -r requirements-bootloader.lock
source_archive=.cache/bootloader/pyinstaller-6.22.3.tar.gz
source_dir=".cache/bootloader/$arch/pyinstaller-6.22.3"
mkdir -p .cache/bootloader ".cache/bootloader/$arch"
if [[ ! -f "$source_archive" ]]; then
    curl -fL --retry 3 --connect-timeout 20 \
        'https://files.pythonhosted.org/packages/63/41/f90302845945abd4ed647933ff5ee7c6ac93983187be67f897b6cb613331/pyinstaller-6.22.3.tar.gz' \
        -o "$source_archive.part"
    mv "$source_archive.part" "$source_archive"
fi
echo "05eb2f5615503e72939a7224d68b4aff572c6b0438ee4a17d0a4b481f399362d  $source_archive" | sha256sum -c -
if [[ ! -f "$source_dir/bootloader/waf" ]]; then
    tar --no-same-owner --touch -xzf "$source_archive" -C ".cache/bootloader/$arch"
fi
compiled_bootloader="$source_dir/PyInstaller/bootloader/$bootloader_platform/run"
if [[ ! -x "$compiled_bootloader" ]]; then
    export ZIG_GLOBAL_CACHE_DIR="$PWD/.cache/zig/$arch"
    build_python="$PWD/$python"
    # Zig's macro-only (-E) probe passes the target to clang directly, where the
    # glibc suffix is invalid. Set that suffix on compile/link flags instead.
    export CC="$build_python -m ziglang cc -target ${zig_target%.2.17}"
    export CFLAGS="-target $zig_target -mcpu=baseline"
    export LINKFLAGS="-target $zig_target"
    (
        cd "$source_dir/bootloader"
        "$build_python" waf all --static-zlib --no-tests
    ) 2>&1 | tee "build/$arch/bootloader.log"
    unset CC CFLAGS LINKFLAGS
fi
cp "$compiled_bootloader" "$venv/lib/python3.12/site-packages/PyInstaller/bootloader/$bootloader_platform/run"
export MODELSCOPE_BUILD_PYINSTALLER_SOURCE="$PWD/$source_dir"

"$python" -m PyInstaller --clean --noconfirm \
    --distpath "$output" --workpath "build/$arch/pyinstaller" \
    modelscope_static.spec 2>&1 | tee "build/$arch/pyinstaller.log"
"$python" test/audit_elf.py "$output/modelscope" | tee "build/$arch/elf-audit.log"

cp README.md "$output/README.md"
cp requirements-linux.lock "$output/requirements-linux.lock"
cp requirements-bootloader.lock "$output/requirements-bootloader.lock"
{
    echo "Build host: $(hostname)"
    echo "Native architecture: $(uname -m)"
    echo 'Python distribution: python-build-standalone 20261021'
    echo "Bundled libgcc: $rpm (SHA256 $libgcc_sha256)"
    echo 'Bootloader: PyInstaller 6.22.3, static zlib, Zig 0.15.2 target glibc 2.17'
    "$python" --version
    "$output/modelscope" --version
    echo 'Packaging: PyInstaller onefile; dynamically linked glibc; not musl static'
} > "$output/build-info.txt"
(
    cd "$output"
    sha256sum modelscope README.md requirements-linux.lock requirements-bootloader.lock build-info.txt > SHA256SUMS
)
tar -czf "dist/modelscope-linux-$arch.tar.gz" -C "$output" \
    modelscope README.md requirements-linux.lock requirements-bootloader.lock build-info.txt SHA256SUMS
echo "Built: $output/modelscope"
echo "Archive: dist/modelscope-linux-$arch.tar.gz"
