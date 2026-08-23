#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include <algorithm>
#include <chrono>
#include <optional>
#include <stdexcept>
#include <vector>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

namespace {

    constexpr auto EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr int  DEFAULT_INTERVAL_MS       = 8;
    constexpr int  MINIMUM_INTERVAL_MS       = 1;
    constexpr int  MAXIMUM_INTERVAL_MS       = 100;

    HANDLE                                      g_handle = nullptr;
    SP<Event::CEventBus::CCustomEvent>           g_motionEvent;
    CHyprSignalListener                          g_mouseMoveListener;
    CHyprSignalListener                          g_preReloadListener;
    bool                                         g_active = false;
    int                                          g_intervalMs = DEFAULT_INTERVAL_MS;
    std::optional<std::chrono::steady_clock::time_point> g_lastEmission;

    void stopBridge() {
        g_active = false;
        g_lastEmission.reset();
    }

    void emitMotion() {
        if (!g_active || !g_motionEvent || !g_pInputManager)
            return;

        const auto now = std::chrono::steady_clock::now();
        if (g_lastEmission && now - *g_lastEmission < std::chrono::milliseconds(g_intervalMs))
            return;

        g_lastEmission = now;
        const auto position = g_pInputManager->getMouseCoordsInternal();
        const auto emitted = g_motionEvent->emit({
            static_cast<double>(position.x),
            static_cast<double>(position.y),
        });
        if (!emitted)
            stopBridge();
    }

    int startBridge(lua_State* state) {
        const auto interval = static_cast<int>(luaL_optinteger(state, 1, DEFAULT_INTERVAL_MS));
        g_intervalMs = std::clamp(interval, MINIMUM_INTERVAL_MS, MAXIMUM_INTERVAL_MS);
        g_lastEmission.reset();
        g_active = g_motionEvent && g_pInputManager;
        lua_pushboolean(state, g_active);
        return 1;
    }

    int stopBridgeLua(lua_State*) {
        stopBridge();
        return 0;
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("custom-layout-pointer: unsupported Hyprland commit");

    g_handle = handle;
    g_motionEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "custom_layout_pointer.motion",
        std::vector{
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
        });

    if (!HyprlandAPI::addEvent(handle, g_motionEvent))
        throw std::runtime_error("custom-layout-pointer: failed to register motion event");

    if (!HyprlandAPI::addLuaFunction(handle, "custom_layout_pointer", "start", startBridge) ||
        !HyprlandAPI::addLuaFunction(handle, "custom_layout_pointer", "stop", stopBridgeLua)) {
        HyprlandAPI::removeEvent(handle, g_motionEvent->m_name);
        g_motionEvent.reset();
        throw std::runtime_error("custom-layout-pointer: failed to register Lua functions");
    }

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { emitMotion(); });
    g_preReloadListener = Event::bus()->m_events.config.preReload.listen([] { stopBridge(); });

    return {
        "custom-layout-pointer",
        "Expose throttled absolute pointer motion to Hyprland Lua layouts",
        "local",
        "0.1.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    stopBridge();
    g_mouseMoveListener.reset();
    g_preReloadListener.reset();

    if (g_handle && g_motionEvent)
        HyprlandAPI::removeEvent(g_handle, g_motionEvent->m_name);

    g_motionEvent.reset();
    g_handle = nullptr;
}
