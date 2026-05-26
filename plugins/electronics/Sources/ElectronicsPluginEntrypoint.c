#include <stddef.h>

const char *merlin_electronics_plugin_bootstrap_json(void) {
    return "{\"status\":\"loaded-dynamic\",\"factory\":\"electronics\"}";
}

const char *merlin_electronics_plugin_handle_json(const char *request_json) {
    (void)request_json;
    return "{\"status\":\"host-handled\",\"factory\":\"electronics\"}";
}
