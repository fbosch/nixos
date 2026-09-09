#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <limits>
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
    SPointerState                      g_state;

    void stopPointer() {
        g_state = {};
    }

    void cleanupPluginState() {
        stopPointer();
        g_mouseMoveListener.reset();

        if (g_handle && g_zoneEvent)
            HyprlandAPI::removeEvent(g_handle, g_zoneEvent->m_name);

        g_zoneEvent.reset();
        g_handle = nullptr;
    }

    class CPluginInitializationGuard final {
      public:
        CPluginInitializationGuard() = default;

        ~CPluginInitializationGuard() {
            if (m_active)
                cleanupPluginState();
        }

        CPluginInitializationGuard(const CPluginInitializationGuard&)            = delete;
        CPluginInitializationGuard& operator=(const CPluginInitializationGuard&) = delete;
        CPluginInitializationGuard(CPluginInitializationGuard&&)                 = delete;
        CPluginInitializationGuard& operator=(CPluginInitializationGuard&&)      = delete;

        void release() noexcept {
            m_active = false;
        }

      private:
        bool m_active = true;
    };

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
        PHLMONITOR monitor;
        for (const auto& candidate : State::monitorState()->monitors()) {
            const auto right  = candidate->m_position.x + candidate->m_size.x;
            const auto bottom = candidate->m_position.y + candidate->m_size.y;
            if (pointer.x >= candidate->m_position.x && pointer.x < right && pointer.y >= candidate->m_position.y && pointer.y < bottom) {
                monitor = candidate;
                break;
            }
        }
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
        const auto showThreshold = luaL_checkinteger(state, 1);
        const auto hideThreshold = luaL_checkinteger(state, 2);
        if (showThreshold < 0 || showThreshold > std::numeric_limits<int>::max())
            return luaL_argerror(state, 1, "show threshold must be a non-negative int");
        if (hideThreshold <= showThreshold)
            return luaL_argerror(state, 2, "hide threshold must be greater than show threshold");
        if (hideThreshold > std::numeric_limits<int>::max())
            return luaL_argerror(state, 2, "hide threshold must fit in an int");

        g_state.active        = true;
        g_state.showThreshold = static_cast<int>(showThreshold);
        g_state.hideThreshold = static_cast<int>(hideThreshold);
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
        throw std::runtime_error("pointer-edge-hooks: unsupported Hyprland commit");

    g_handle = handle;
    g_zoneEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "pointer_edge_hooks.zone",
        std::vector{
            Event::CEventBus::CCustomEvent::TYPE_STRING,
            Event::CEventBus::CCustomEvent::TYPE_STRING,
        });

    if (!HyprlandAPI::addEvent(handle, g_zoneEvent))
        throw std::runtime_error("pointer-edge-hooks: failed to register zone event");

    CPluginInitializationGuard cleanup;
    if (!HyprlandAPI::addLuaFunction(handle, "pointer_edge_hooks", "start", startPointer) ||
        !HyprlandAPI::addLuaFunction(handle, "pointer_edge_hooks", "stop", stopPointerLua) ||
        !HyprlandAPI::addLuaFunction(handle, "pointer_edge_hooks", "sync", syncPointer) ||
        !HyprlandAPI::addLuaFunction(handle, "pointer_edge_hooks", "rebind", rebindZoneEvent)) {
        throw std::runtime_error("pointer-edge-hooks: failed to register Lua functions");
    }

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { emitZone(false); });

    const auto description = PLUGIN_DESCRIPTION_INFO{
        "pointer-edge-hooks",
        "Emit bottom-edge pointer zone transitions from native Hyprland pointer state",
        "local",
        "0.1.0",
    };
    cleanup.release();
    return description;
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
