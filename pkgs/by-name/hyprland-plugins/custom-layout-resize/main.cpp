#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/supplementary/WorkspaceAlgoMatcher.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <format>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

using namespace Desktop::View;

namespace {

    constexpr auto EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr int  DEFAULT_INTERVAL_MS       = 8;
    constexpr int  MINIMUM_INTERVAL_MS       = 6;
    constexpr int  MAXIMUM_INTERVAL_MS       = 17;

    struct SResizeSession {
        bool                                                 active = false;
        char                                                 axis = 'x';
        std::string                                          command;
        std::string                                          targetId;
        std::string                                          edge;
        int                                                  intervalMs = DEFAULT_INTERVAL_MS;
        std::optional<int>                                   lastPosition;
        std::optional<std::chrono::steady_clock::time_point> lastEmission;
    };

    HANDLE                             g_handle = nullptr;
    SP<Event::CEventBus::CCustomEvent> g_commandEvent;
    CHyprSignalListener                g_mouseMoveListener;
    CHyprSignalListener                g_preReloadListener;
    SResizeSession                     g_session;

    int returnStartStatus(lua_State* state, bool started, bool handled) {
        lua_pushboolean(state, started);
        lua_pushboolean(state, handled);
        return 2;
    }

    void clearSession() {
        g_session = {};
    }

    bool emitCommand(std::string command) {
        if (!g_commandEvent)
            return false;

        const auto emitted = g_commandEvent->emit({std::move(command)});
        if (!emitted) {
            clearSession();
            return false;
        }

        return true;
    }

    CBox windowGeometry(PHLWINDOW window) {
        const auto position = window->position(IGeometric::GEOMETRIC_GOAL);
        const auto size     = window->size(IGeometric::GEOMETRIC_GOAL);
        return {position.x, position.y, size.x, size.y};
    }

    PHLWINDOW targetWindow(const Vector2D& cursor) {
        const auto active = Desktop::focusState()->window();
        if (active && windowGeometry(active).containsPoint(cursor))
            return active;

        if (!Desktop::viewState())
            return active;

        auto target = Desktop::viewState()->hitTest().windowAt(cursor, ALLOW_FLOATING);
        if (!target)
            return active;

        if (target != active)
            Desktop::focusState()->fullWindowFocus(target, Desktop::FOCUS_REASON_DISPATCH_FOCUSWINDOW);

        return target;
    }

    bool hasTag(PHLWINDOW window, std::string_view expected) {
        if (!window || !window->m_ruleApplicator || expected.empty())
            return false;

        for (const auto& tag : window->m_ruleApplicator->m_tagKeeper.getTags()) {
            std::string_view normalized = tag;
            if (!normalized.empty() && normalized.back() == '*')
                normalized.remove_suffix(1);
            if (normalized == expected)
                return true;
        }

        return false;
    }

    std::optional<std::string> tiledLayoutName(PHLWINDOW window) {
        if (!window || window->isFloating() || !window->m_workspace || !window->m_workspace->m_space)
            return std::nullopt;

        const auto& algorithm = window->m_workspace->m_space->algorithm();
        if (!algorithm || !algorithm->tiledAlgo())
            return std::nullopt;

        return Layout::Supplementary::algoMatcher()->getNameForTiledAlgo(algorithm->tiledAlgo().get());
    }

    int pointerInterval(PHLWINDOW window) {
        const auto monitor = window ? window->m_monitor.lock() : nullptr;
        const auto refresh = monitor && monitor->m_refreshRate > 0 ? monitor->m_refreshRate : 60.0;
        return std::clamp(static_cast<int>(std::lround(1000.0 / refresh)), MINIMUM_INTERVAL_MS, MAXIMUM_INTERVAL_MS);
    }

    bool emitPosition(bool force) {
        if (!g_session.active || !g_pInputManager)
            return false;

        const auto now = std::chrono::steady_clock::now();
        if (!force && g_session.lastEmission && now - *g_session.lastEmission < std::chrono::milliseconds(g_session.intervalMs))
            return true;

        const auto cursor  = g_pInputManager->getMouseCoordsInternal();
        const auto raw     = g_session.axis == 'x' ? cursor.x : cursor.y;
        const auto current = static_cast<int>(std::lround(raw));
        if (g_session.lastPosition && *g_session.lastPosition == current)
            return true;

        if (!emitCommand(std::format("{} {} {} {}", g_session.command, g_session.targetId, g_session.edge, current)))
            return false;

        g_session.lastPosition = current;
        g_session.lastEmission = now;
        return true;
    }

    void stopResize(bool save) {
        if (!g_session.active) {
            clearSession();
            return;
        }

        if (save) {
            emitPosition(true);
            if (g_session.active)
                emitCommand("save-resize");
        }

        clearSession();
    }

    int startResize(lua_State* state) {
        const std::string ultrawideLayout = luaL_checkstring(state, 1);
        const std::string portraitLayout  = luaL_checkstring(state, 2);
        const std::string portraitMonitor = luaL_checkstring(state, 3);
        const std::string blockedTag      = luaL_checkstring(state, 4);

        stopResize(false);
        if (!g_commandEvent || !g_pInputManager || !Desktop::viewState())
            return returnStartStatus(state, false, false);

        const auto cursor = g_pInputManager->getMouseCoordsInternal();
        const auto target = targetWindow(cursor);
        if (!target)
            return returnStartStatus(state, false, true);

        if (target->isFloating() || hasTag(target, blockedTag))
            return returnStartStatus(state, false, true);

        const auto layout = tiledLayoutName(target);
        if (!layout)
            return returnStartStatus(state, false, true);

        char axis = 'x';
        if (*layout == portraitLayout)
            axis = 'y';
        else if (*layout == ultrawideLayout) {
            const auto monitor = target->m_monitor.lock();
            axis = monitor && monitor->m_name == portraitMonitor ? 'y' : 'x';
        } else
            return returnStartStatus(state, false, true);

        const auto geometry   = windowGeometry(target);
        const auto coordinate = axis == 'x' ? cursor.x : cursor.y;
        const auto midpoint   = axis == 'x' ? geometry.x + geometry.width / 2.0 : geometry.y + geometry.height / 2.0;

        g_session.active     = true;
        g_session.axis       = axis;
        g_session.command    = axis == 'x' ? "resize-x-at" : "resize-y-at";
        g_session.targetId   = std::format("address:0x{:x}", reinterpret_cast<uintptr_t>(target.get()));
        g_session.edge       = axis == 'x' ? (coordinate < midpoint ? "left" : "right") : (coordinate < midpoint ? "up" : "down");
        g_session.intervalMs = pointerInterval(target);

        return returnStartStatus(state, true, true);
    }

    int stopResizeLua(lua_State* state) {
        const bool active = g_session.active;
        stopResize(true);
        lua_pushboolean(state, active);
        return 1;
    }

    // Re-fires pluginEventAdded so the active Lua config state re-bridges the
    // command event; config reloads replace the Lua handler without notifying
    // already-loaded plugins.
    int rebindCommandEvent(lua_State* state) {
        if (!g_handle || !g_commandEvent) {
            lua_pushboolean(state, false);
            return 1;
        }

        HyprlandAPI::removeEvent(g_handle, g_commandEvent->m_name);
        lua_pushboolean(state, HyprlandAPI::addEvent(g_handle, g_commandEvent));
        return 1;
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("custom-layout-resize: unsupported Hyprland commit");

    g_handle = handle;
    g_commandEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "custom_layout_resize.command",
        std::vector{Event::CEventBus::CCustomEvent::TYPE_STRING});

    if (!HyprlandAPI::addEvent(handle, g_commandEvent))
        throw std::runtime_error("custom-layout-resize: failed to register command event");

    if (!HyprlandAPI::addLuaFunction(handle, "custom_layout_resize", "start", startResize) ||
        !HyprlandAPI::addLuaFunction(handle, "custom_layout_resize", "stop", stopResizeLua) ||
        !HyprlandAPI::addLuaFunction(handle, "custom_layout_resize", "rebind", rebindCommandEvent)) {
        HyprlandAPI::removeEvent(handle, g_commandEvent->m_name);
        g_commandEvent.reset();
        throw std::runtime_error("custom-layout-resize: failed to register Lua functions");
    }

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { emitPosition(false); });
    g_preReloadListener = Event::bus()->m_events.config.preReload.listen([] { stopResize(false); });

    return {
        "custom-layout-resize",
        "Drive custom-layout drag resize from native Hyprland pointer state",
        "local",
        "0.2.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    stopResize(false);
    g_mouseMoveListener.reset();
    g_preReloadListener.reset();

    if (g_handle && g_commandEvent)
        HyprlandAPI::removeEvent(g_handle, g_commandEvent->m_name);

    g_commandEvent.reset();
    g_handle = nullptr;
}
