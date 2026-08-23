#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

namespace {

    constexpr auto EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;

    struct SPointerState {
        bool        active = false;
        int         showThreshold = 20;
        int         hideThreshold = 60;
        std::string lastZone;
        std::string lastMonitor;
    };

    HANDLE                             g_handle = nullptr;
    SP<Event::CEventBus::CCustomEvent> g_zoneEvent;
    CHyprSignalListener                g_mouseMoveListener;
    CHyprSignalListener                g_preReloadListener;
    SPointerState                      g_state;

    void stopPointer() {
        g_state = {};
    }

    std::string_view zoneFor(double distance) {
        if (distance <= g_state.showThreshold)
            return "show";
        if (distance <= g_state.hideThreshold)
            return "neutral";
        return "hide";
    }

    bool emitZone(bool force) {
        if (!g_state.active || !g_zoneEvent || !g_pInputManager || !State::monitorState())
            return false;

        const auto pointer = g_pInputManager->getMouseCoordsInternal();
        const auto monitor = State::monitorState()->query().vec(pointer).run();
        if (!monitor)
            return false;

        const auto distance = monitor->m_position.y + monitor->m_size.y - pointer.y;
        const auto zone     = std::string{zoneFor(distance)};
        if (!force && zone == g_state.lastZone && monitor->m_name == g_state.lastMonitor)
            return true;

        if (!g_zoneEvent->emit({zone, monitor->m_name}))
            return false;

        g_state.lastZone    = zone;
        g_state.lastMonitor = monitor->m_name;
        return true;
    }

    int startPointer(lua_State* state) {
        const auto showThreshold = static_cast<int>(luaL_checkinteger(state, 1));
        const auto hideThreshold = static_cast<int>(luaL_checkinteger(state, 2));
        if (showThreshold < 0)
            return luaL_argerror(state, 1, "show threshold must be non-negative");
        if (hideThreshold <= showThreshold)
            return luaL_argerror(state, 2, "hide threshold must be greater than show threshold");

        g_state.active        = true;
        g_state.showThreshold = showThreshold;
        g_state.hideThreshold = hideThreshold;
        g_state.lastZone.clear();
        g_state.lastMonitor.clear();

        lua_pushboolean(state, emitZone(true));
        return 1;
    }

    int stopPointerLua(lua_State* state) {
        const bool active = g_state.active;
        stopPointer();
        lua_pushboolean(state, active);
        return 1;
    }

    int syncPointer(lua_State* state) {
        lua_pushboolean(state, emitZone(true));
        return 1;
    }

    // Config reloads replace Lua handlers without notifying already-loaded
    // plugins. Re-registering the custom event exposes it to the new Lua state.
    int rebindZoneEvent(lua_State* state) {
        if (!g_handle || !g_zoneEvent) {
            lua_pushboolean(state, false);
            return 1;
        }

        HyprlandAPI::removeEvent(g_handle, g_zoneEvent->m_name);
        lua_pushboolean(state, HyprlandAPI::addEvent(g_handle, g_zoneEvent));
        return 1;
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("waybar-pointer: unsupported Hyprland commit");

    g_handle = handle;
    g_zoneEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "waybar_pointer.zone",
        std::vector{
            Event::CEventBus::CCustomEvent::TYPE_STRING,
            Event::CEventBus::CCustomEvent::TYPE_STRING,
        });

    if (!HyprlandAPI::addEvent(handle, g_zoneEvent))
        throw std::runtime_error("waybar-pointer: failed to register zone event");

    if (!HyprlandAPI::addLuaFunction(handle, "waybar_pointer", "start", startPointer) ||
        !HyprlandAPI::addLuaFunction(handle, "waybar_pointer", "stop", stopPointerLua) ||
        !HyprlandAPI::addLuaFunction(handle, "waybar_pointer", "sync", syncPointer) ||
        !HyprlandAPI::addLuaFunction(handle, "waybar_pointer", "rebind", rebindZoneEvent)) {
        HyprlandAPI::removeEvent(handle, g_zoneEvent->m_name);
        g_zoneEvent.reset();
        throw std::runtime_error("waybar-pointer: failed to register Lua functions");
    }

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { emitZone(false); });
    g_preReloadListener = Event::bus()->m_events.config.preReload.listen([] { stopPointer(); });

    return {
        "waybar-pointer",
        "Emit Waybar bottom-edge zone transitions from native Hyprland pointer state",
        "local",
        "0.1.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    stopPointer();
    g_mouseMoveListener.reset();
    g_preReloadListener.reset();

    if (g_handle && g_zoneEvent)
        HyprlandAPI::removeEvent(g_handle, g_zoneEvent->m_name);

    g_zoneEvent.reset();
    g_handle = nullptr;
}
