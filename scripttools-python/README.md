# build环境准备

```bash

uv venv -p 3.15 --seed

pip3 install pyinstaller

# 一定要记得使用如下命令对于配置可以行的 so 文件
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
