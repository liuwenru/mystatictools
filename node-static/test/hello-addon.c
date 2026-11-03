/* 最小 N-API 扩展：仅用于确认纯静态 node 加载 .node 时给出明确错误，不随运行包交付。 */
#include <node_api.h>

static napi_value init(napi_env env, napi_value exports) {
    napi_value value;
    napi_create_string_utf8(env, "hello", NAPI_AUTO_LENGTH, &value);
    napi_set_named_property(env, exports, "hello", value);
    return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, init)
