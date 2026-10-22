"""Isolated headless and real-PTY/tmux tests; no connection to existing sessions."""
import errno
import fcntl
import os
import pathlib
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

nvim = str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='nvim-test-') as root:
    env = os.environ.copy()
    env.pop('VIMRUNTIME', None)
    env.pop('VIM', None)
    env.pop('TMUX', None)
    env.update(HOME=root, XDG_CONFIG_HOME=root + '/config', XDG_DATA_HOME=root + '/data',
               XDG_STATE_HOME=root + '/state', XDG_CACHE_HOME=root + '/cache',
               TEST_ROOT=root, LANG='C.UTF-8', TERMINFO=root + '/no-terminfo',
               TERMINFO_DIRS=root + '/no-terminfo')
    subprocess.run([nvim, '--headless', '-u', 'NONE', '-l',
                    str(pathlib.Path(__file__).with_name('smoke-test.lua'))],
                   env=env, check=True, timeout=30)
    assert pathlib.Path(root, 'headless.ok').exists()
    subprocess.run([nvim, '--headless', '-u',
                    str(pathlib.Path(nvim).parent.parent / 'examples/init.lua'),
                    '-i', 'NONE', '+lua assert(vim.g.clipboard == nil and vim.o.clipboard == "" and vim.o.mouse == "")',
                    '+qa!'], env=env, check=True, timeout=15)
    tmux = env.get('NVIM_TEST_TMUX') or shutil.which('tmux')
    if not tmux:
        raise RuntimeError('tmux is required for the PTY integration tests')
    config = pathlib.Path(root, 'tmux.conf')
    config.write_text('set -g default-terminal tmux-256color\nset -g mouse on\n'
                      'set -s set-clipboard on\nset -as terminal-features ",xterm*:RGB"\n')
    socket = root + '/tmux.sock'
    base = [tmux, '-S', socket, '-f', str(config)]
    try:
        for term in ('xterm-256color', 'screen-256color', 'tmux-256color', 'linux'):
            for multiplexed in (False, True):
                target = pathlib.Path(root, term + ('-tmux' if multiplexed else '-direct'))
                env['TERM'] = term
                master, slave = pty.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 100, 0, 0))
                command = [nvim, '-u', 'NONE', '-i', 'NONE', str(target)]
                process_env = env.copy()
                if multiplexed:
                    # The test tmux uses its own database, not available to nvim.
                    process_env['TERMINFO'] = '/build/test-terminfo'
                    command = base + ['new-session', '-s', 'test', '/usr/bin/env',
                                      'TERMINFO=' + root + '/no-terminfo',
                                      'TERMINFO_DIRS=' + root + '/no-terminfo'] + command
                process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                                           env=process_env, start_new_session=True)
                os.close(slave)
                output = bytearray()
                deadline = time.monotonic() + 20
                sent = False
                pasted_at = None
                exited = False
                try:
                    while time.monotonic() < deadline:
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                data = os.read(master, 65536)
                            except OSError as exc:
                                if exc.errno == errno.EIO:
                                    break
                                raise
                            if not data:
                                break
                            output.extend(data)
                        if not sent and time.monotonic() > deadline - 16:
                            # Exercise OSC52 emission, mouse enablement and bracketed Unicode paste.
                            os.write(master, b':set termguicolors mouse=a\r')
                            os.write(master, b":lua require('vim.ui.clipboard.osc52').copy('+')({'OSC52test'}, 'v')\r")
                            os.write(master, b'i\x1b[200~' + 'PTY中文-test'.encode()
                                     + b'\x1b[201~')
                            sent = True
                            pasted_at = time.monotonic()
                        # Bracketed paste is scheduled asynchronously; do not save ahead of it.
                        if pasted_at is not None and not exited and time.monotonic() - pasted_at > 1:
                            os.write(master, b'\x1b[D!\x1b:wq\r')
                            exited = True
                        if process.poll() is not None:
                            break
                    process.wait(timeout=5)
                    assert process.returncode == 0, bytes(output[-2000:])
                    assert 'PTY中文' in target.read_text(), bytes(output[-2000:])
                    if term == 'xterm-256color':
                        assert b'T1NDNTJ0ZXN0' in output, 'OSC52 payload not forwarded: ' + repr(bytes(output[-2000:]))
                        assert b'38;2;' in output or b'38:2:' in output, 'RGB color sequence missing'
                        assert b'?1002h' in output or b'?1000h' in output, 'Mouse mode sequence missing'
                    print(f'PASS PTY TERM={term} tmux={multiplexed}', flush=True)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    os.close(master)
                if multiplexed:
                    subprocess.run(base + ['kill-server'], env=env, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
    finally:
        subprocess.run(base + ['kill-server'], env=env, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
