-- Export each server-to-client TCP payload separately for latency analysis.

local script_args        = {...}
local server_port        = tonumber(script_args[1]) or 8900
local client_port        = tonumber(script_args[2])
local f_frame_time       = Field.new("frame.time")
local f_frame_time_epoch = Field.new("frame.time_epoch")
local f_ip_src           = Field.new("ip.src")
local f_ip_dst           = Field.new("ip.dst")
local f_ipv6_src         = Field.new("ipv6.src")
local f_ipv6_dst         = Field.new("ipv6.dst")
local f_tcp_srcport      = Field.new("tcp.srcport")
local f_tcp_dstport      = Field.new("tcp.dstport")
local f_tcp_stream       = Field.new("tcp.stream")
local f_tcp_payload      = Field.new("tcp.payload")
local f_http_chunk_data  = Field.new("http.chunk_data")
local f_http_file_data   = Field.new("http.file_data")
local f_http2_data       = Field.new("http2.data.data")
local f_data_data        = Field.new("data.data")
local tls_keylog_enabled = os.getenv("SSLKEYLOGFILE") ~= nil

local request_started = {}
local previous_response = {}
local response_packet_count = 0

local function value(fi)
    return fi and tostring(fi) or nil
end

local function address(v4, v6)
    return value(v4()) or value(v6()) or "?"
end

local function raw_field(field)
    local fi = field()
    if fi == nil or fi.range == nil then
        return nil
    end

    local ok, raw = pcall(function()
        return fi.range:raw()
    end)
    return ok and raw or nil
end

local function raw_fields(field)
    local result = {}
    local fields = {field()}
    for _, fi in ipairs(fields) do
        if fi.range ~= nil then
            local ok, raw = pcall(function()
                return fi.range:raw()
            end)
            if ok and raw ~= nil and #raw > 0 then
                result[#result + 1] = raw
            end
        end
    end
    return result
end

-- Keep valid UTF-8 unchanged; escape only invalid or unsafe binary bytes.
local function printable_utf8(s)
    local out = {}
    local i = 1

    while i <= #s do
        local b = string.byte(s, i)
        if b == 9 or b == 10 or b == 13 or (b >= 32 and b <= 126) then
            out[#out + 1] = string.char(b)
        else
            local length = 0
            local b2 = string.byte(s, i + 1)
            if b >= 0xC2 and b <= 0xDF and b2 and b2 >= 0x80 and b2 <= 0xBF then
                length = 2
            elseif b == 0xE0 and b2 and b2 >= 0xA0 and b2 <= 0xBF then
                length = 3
            elseif ((b >= 0xE1 and b <= 0xEC) or (b >= 0xEE and b <= 0xEF))
                    and b2 and b2 >= 0x80 and b2 <= 0xBF then
                length = 3
            elseif b == 0xED and b2 and b2 >= 0x80 and b2 <= 0x9F then
                length = 3
            elseif b == 0xF0 and b2 and b2 >= 0x90 and b2 <= 0xBF then
                length = 4
            elseif b >= 0xF1 and b <= 0xF3 and b2 and b2 >= 0x80 and b2 <= 0xBF then
                length = 4
            elseif b == 0xF4 and b2 and b2 >= 0x80 and b2 <= 0x8F then
                length = 4
            end

            local valid = length > 0 and i + length - 1 <= #s
            for j = 2, length - 1 do
                local continuation = string.byte(s, i + j)
                valid = valid and continuation >= 0x80 and continuation <= 0xBF
            end

            if valid then
                out[#out + 1] = string.sub(s, i, i + length - 1)
                i = i + length - 1
            else
                out[#out + 1] = string.format("\\x%02X", b)
            end
        end
        i = i + 1
    end

    return table.concat(out)
end

local packet_filter = string.format("tcp.port == %d && tcp.len > 0", server_port)
if client_port then
    packet_filter = packet_filter .. string.format(" && tcp.port == %d", client_port)
end
local tap = Listener.new("frame", packet_filter)

function tap.packet(pinfo, tvb)
    local src_port = tonumber(value(f_tcp_srcport()))
    local dst_port = tonumber(value(f_tcp_dstport()))
    local stream = value(f_tcp_stream()) or "?"
    local epoch_text = value(f_frame_time_epoch()) or tostring(pinfo.abs_ts)
    local epoch = tonumber(epoch_text)

    if dst_port == server_port then
        request_started[stream] = request_started[stream] or epoch
        return
    end
    if src_port ~= server_port then
        return
    end
    if client_port and dst_port ~= client_port then
        return
    end

    local payload = raw_field(f_tcp_payload)
    if payload == nil or #payload == 0 then
        return
    end

    response_packet_count = response_packet_count + 1
    local since_request = request_started[stream] and (epoch - request_started[stream]) * 1000
    local since_previous = previous_response[stream] and (epoch - previous_response[stream]) * 1000
    previous_response[stream] = epoch

    print(string.rep("=", 88))
    print(string.format("frame.number               : %s", tostring(pinfo.number)))
    print(string.format("frame.time                 : %s", value(f_frame_time()) or tostring(pinfo.abs_ts)))
    print(string.format("frame.time_epoch           : %s", epoch_text))
    print(string.format("tcp.stream                 : %s", stream))
    print(string.format(
        "network                    : %s:%d -> %s:%d",
        address(f_ip_src, f_ipv6_src), src_port,
        address(f_ip_dst, f_ipv6_dst), dst_port
    ))
    print(string.format("tcp.payload_bytes          : %d", #payload))
    print(string.format(
        "time.since_request_ms      : %s",
        since_request and string.format("%.3f", since_request) or "unknown"
    ))
    print(string.format(
        "time.since_previous_tcp_ms : %s",
        since_previous and string.format("%.3f", since_previous) or "first response packet"
    ))
    print("--- TCP PAYLOAD BEGIN ---")
    print(printable_utf8(payload))
    print("--- TCP PAYLOAD END ---")

    if tls_keylog_enabled then
        local decrypted = raw_fields(f_http2_data)
        local protocol = "HTTP/2 DATA"
        if #decrypted == 0 then
            decrypted = raw_fields(f_http_chunk_data)
            protocol = "HTTP/1 CHUNK DATA"
        end
        if #decrypted == 0 then
            decrypted = raw_fields(f_http_file_data)
            protocol = "HTTP/1 FILE DATA"
        end
        if #decrypted == 0 then
            decrypted = raw_fields(f_data_data)
            protocol = "TLS APPLICATION DATA"
        end

        for index, plaintext in ipairs(decrypted) do
            print(string.format(
                "--- DECRYPTED %s BEGIN (%d/%d, available at frame %s) ---",
                protocol, index, #decrypted, tostring(pinfo.number)
            ))
            print(printable_utf8(plaintext))
            print(string.format("--- DECRYPTED %s END ---", protocol))
        end
    end
end

function tap.draw()
    io.stderr:write(string.format(
        "[http_export.lua] exported %d response TCP packet(s)\n",
        response_packet_count
    ))
end

function tap.reset()
    request_started = {}
    previous_response = {}
    response_packet_count = 0
end
