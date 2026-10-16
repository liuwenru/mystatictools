# 构建方法

`launcher.py` 是 PyInstaller 的入口。构建后的可执行文件会动态执行同目录下的
`benchmark_response_stats.py`，因此修改统计逻辑后不需要重新构建可执行文件。

```bash
pyinstaller --clean --noconfirm benchmark_response_stats.spec
```

发布时需要同时复制以下两个文件：

```text
dist/
├── benchmark_response_stats
└── benchmark_response_stats.py
```

Linux/macOS 可执行文件没有扩展名，Windows 下为 `benchmark_response_stats.exe`。

构建完成后，将业务脚本复制到发布目录：

```bash
cp benchmark_response_stats.py dist/benchmark_response_stats.py
```

运行方式保持不变：

```bash
./dist/benchmark_response_stats input.txt
```

## 修改依赖

`launcher.py` 中的 `_collect_pyinstaller_dependencies()` 会静态导入
`benchmark_response_stats`。这个函数不会在运行时调用，只用于让 PyInstaller 在构建时
自动扫描业务脚本及其静态依赖，因此通常不需要手动配置 `--hidden-import`。

该分析会在可执行文件中内嵌一份业务模块，但启动器不会执行内嵌版本，而是始终通过
`runpy.run_path()` 执行可执行文件同目录下的外部 `benchmark_response_stats.py`。因此只修改
业务逻辑时不需要重新构建；新增依赖后需要重新构建，PyInstaller 才能把依赖加入可执行文件。

普通的 `import` 和 `from ... import ...` 可以自动扫描。通过 `importlib`、变量或插件机制
进行的动态导入可能无法识别，这类依赖仍需添加到 spec 的 `hiddenimports` 或在构建命令中
使用 `--hidden-import`。第三方依赖还必须先安装在构建环境。目标机器需要兼容构建机器的
操作系统和 CPU 架构。

## 直接构建方法

直接运行 PyInstaller 时，入口也必须使用 `launcher.py`。该命令会重新生成
`benchmark_response_stats.spec`。

```bash
pyinstaller --clean --noconfirm \
  --onefile \
  --name benchmark_response_stats \
  launcher.py
```

## 独立单文件构建

如果不需要外部脚本，可以跳过 `launcher.py`，将业务脚本直接打包。这里使用不同的名称，
避免覆盖以 `launcher.py` 为入口的 `benchmark_response_stats.spec` 和可执行文件。

```bash
pyinstaller --onefile \
  --name benchmark_response_stats_standalone \
  benchmark_response_stats.py
```

# 其他注意事项

## executable stack error

```bash

[PYI-2256301:ERROR] Failed to load Python shared library '/tmp/\_MEI00226da0gWnhtE/libpython3.15.so.1.0': /tmp/\_MEI00226da0gWnhtE/libpython3.15.so.1.0: cannot enable executable stack as shared object requires: Invalid argument

```

如上所示，如果出现该问题，可以如下操作

```bash
LIBPYTHON=$(python3.15 -c '
import os
import sysconfig
print(os.path.join(
    sysconfig.get_config_var("LIBDIR"),
    sysconfig.get_config_var("LDLIBRARY")
))
')

echo "$LIBPYTHON"
cp -a "$LIBPYTHON" "${LIBPYTHON}.bak"
patchelf --clear-execstack "$LIBPYTHON"

```
