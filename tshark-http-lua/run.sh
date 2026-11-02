#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCH="$(uname -m)"
TSHARK_BIN="${SCRIPT_DIR}/tshark-${ARCH}"
DUMPCAP_BIN="${SCRIPT_DIR}/dumpcap-${ARCH}"

if [[ ! -f "$TSHARK_BIN" ]]; then
  echo "错误：当前脚本目录下未找到 ${ARCH} 架构的 tshark：$TSHARK_BIN" >&2
  exit 1
fi
if [[ ! -f "$DUMPCAP_BIN" ]]; then
  echo "错误：当前脚本目录下未找到 ${ARCH} 架构的 dumpcap：$DUMPCAP_BIN" >&2
  exit 1
fi

if [[ "${1:-}" == "capture" ]]; then
  MODE="capture"
  INTERFACE="${2:-any}"
  PCAP="${3:-llm.pcap}"
  OUTPUT="${4:-http_output.txt}"
  SERVER_PORT="${5:-8900}"
  CLIENT_PORT="${6:-}"
else
  MODE="analyze"
  PCAP="${1:-llm.pcap}"
  OUTPUT="${2:-http_output.txt}"
  SERVER_PORT="${3:-8900}"
  CLIENT_PORT="${4:-}"
fi

if [[ "$MODE" == "analyze" && ! -f "$PCAP" ]]; then
  echo "错误：找不到抓包文件：$PCAP" >&2
  echo "用法：$0 [pcap文件] [输出文件] [服务端端口] [客户端端口]" >&2
  echo "实时抓包：$0 capture [网卡] [pcap文件] [输出文件] [服务端端口] [客户端端口]" >&2
  exit 1
fi

if [[ ! "$SERVER_PORT" =~ ^[0-9]+$ ]] || ((SERVER_PORT < 1 || SERVER_PORT > 65535)); then
  echo "错误：无效的服务端端口：$SERVER_PORT" >&2
  exit 1
fi
if [[ -n "$CLIENT_PORT" ]] && { [[ ! "$CLIENT_PORT" =~ ^[0-9]+$ ]] || ((CLIENT_PORT < 1 || CLIENT_PORT > 65535)); }; then
  echo "错误：无效的客户端端口：$CLIENT_PORT" >&2
  exit 1
fi

TSHARK_ARGS=(
  -q
)
if [[ -n "${SSLKEYLOGFILE:-}" ]]; then
  TSHARK_ARGS+=(
    -o "tls.keylog_file:${SSLKEYLOGFILE}"
    -o "http.desegment_body:FALSE"
    -d "tcp.port==${SERVER_PORT},tls"
  )
  echo "TLS 解密已启用：$SSLKEYLOGFILE" >&2
fi

LUA_ARGS=(-X "lua_script1:${SERVER_PORT}")
if [[ -n "$CLIENT_PORT" ]]; then
  LUA_ARGS+=(-X "lua_script1:${CLIENT_PORT}")
fi

if [[ "$MODE" == "capture" ]]; then
  CAPTURE_FILTER="tcp port ${SERVER_PORT}"
  if [[ -n "$CLIENT_PORT" ]]; then
    CAPTURE_FILTER+=" and tcp port ${CLIENT_PORT}"
  fi

  echo "开始抓包：网卡=$INTERFACE，服务端端口=$SERVER_PORT，按 Ctrl+C 停止" >&2
  "$TSHARK_BIN" -i "$INTERFACE" -f "$CAPTURE_FILTER" -s 0 -l "${TSHARK_ARGS[@]}" -w "$PCAP" \
    -X "lua_script:${SCRIPT_DIR}/http_export.lua" "${LUA_ARGS[@]}" >"$OUTPUT"
else
  "$TSHARK_BIN" -r "$PCAP" "${TSHARK_ARGS[@]}" \
    -X "lua_script:${SCRIPT_DIR}/http_export.lua" "${LUA_ARGS[@]}" >"$OUTPUT"
fi

echo "完成：分析结果=$OUTPUT，抓包文件=$PCAP"
