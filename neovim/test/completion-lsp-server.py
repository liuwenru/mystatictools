"""Local LSP fixture: no dependencies or network, not a real Nginx server."""
import json
import sys
import time

while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        if line == b"\r\n":
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    message = json.loads(sys.stdin.buffer.read(int(headers["content-length"])))
    method = message.get("method")
    if method == "exit":
        break
    if "id" not in message:
        continue
    result = None
    if method == "initialize":
        result = {"capabilities": {"textDocumentSync": 1, "completionProvider": {}}}
    elif method == "textDocument/completion":
        time.sleep(0.15)  # Exercise replies that arrive after the session switch was turned off.
        result = [{"label": "server_name", "kind": 14}]
    data = json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}).encode()
    sys.stdout.buffer.write(f"Content-Length: {len(data)}\r\n\r\n".encode() + data)
    sys.stdout.buffer.flush()
