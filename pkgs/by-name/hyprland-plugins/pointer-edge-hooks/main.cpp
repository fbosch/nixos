#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <format>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

namespace {

    struct SPointerState {
        bool        active = false;
        int         showThreshold = 20;
        int         hideThreshold = 60;
        std::string lastZone;
        int         lastMonitor = -1;
    };

    CHyprSignalListener g_mouseMoveListener;
    CHyprSignalListener g_monitorRemovedListener;
    CHyprSignalListener g_monitorAddedListener;
    CHyprSignalListener g_monitorLayoutListener;
    SPointerState       g_state;

    void postZone(std::string_view zone, int monitor) {
        if (auto& sock = IPC::Socket2::sock(); sock)
            sock->postEvent({.event = "pointeredgezone", .data = std::format("{},{}", zone, monitor)});
    }

    void clearZone() {
        if (g_state.active && g_state.lastMonitor >= 0)
            postZone("neutral", g_state.lastMonitor);
        g_state.lastZone.clear();
        g_state.lastMonitor = -1;
    }

    void stopPointer() {
        clearZone();
        g_state = {};
    }

    void cleanupPluginState() {
        stopPointer();
        g_mouseMoveListener.reset();
        g_monitorRemovedListener.reset();
        g_monitorAddedListener.reset();
        g_monitorLayoutListener.reset();
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
        if (!g_state.active || !g_pInputManager || !State::monitorState())
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
        if (!monitor) {
            clearZone();
            return false;
        }

        const auto distance = monitor->m_position.y + monitor->m_size.y - pointer.y;
        const auto zone     = zoneFor(distance);
        if (!force && zone == g_state.lastZone && monitor->m_id == g_state.lastMonitor)
            return true;

        postZone(zone, monitor->m_id);
        g_state.lastZone    = zone;
        g_state.lastMonitor = monitor->m_id;
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

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    CPluginInitializationGuard cleanup;
    if (!HyprlandAPI::addLuaFunction(handle, "pointer_edge_hooks", "start", startPointer) ||
        !HyprlandAPI::addLuaFunction(handle, "pointer_edge_hooks", "stop", stopPointerLua) ||
        !HyprlandAPI::addLuaFunction(handle, "pointer_edge_hooks", "sync", syncPointer)) {
        throw std::runtime_error("pointer-edge-hooks: failed to register Lua functions");
    }

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { emitZone(false); });
    // MonitorState removes disconnected outputs on this signal; invalidate a removed ID
    // before sampling again so a stationary pointer cannot leave an obsolete zone cached.
    g_monitorRemovedListener = Event::bus()->m_events.monitor.removed.listen([](PHLMONITOR monitor) {
        if (monitor && monitor->m_id == g_state.lastMonitor)
            clearZone();
        emitZone(false);
    });
    g_monitorAddedListener  = Event::bus()->m_events.monitor.added.listen([](PHLMONITOR) { emitZone(false); });
    g_monitorLayoutListener = Event::bus()->m_events.monitor.layoutChanged.listen([] { emitZone(false); });

    const auto description = PLUGIN_DESCRIPTION_INFO{
        "pointer-edge-hooks",
        "Emit bottom-edge pointer zone transitions from native Hyprland pointer state",
        "local",
        "0.2.0",
    };
    cleanup.release();
    return description;
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
