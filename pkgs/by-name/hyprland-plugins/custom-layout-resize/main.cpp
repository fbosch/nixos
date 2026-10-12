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

    constexpr int  DEFAULT_INTERVAL_MS       = 8;
    constexpr int  MINIMUM_INTERVAL_MS       = 6;
    constexpr int  MAXIMUM_INTERVAL_MS       = 17;

    struct SResizeConfig {
        std::string ultrawideLayout;
        std::string portraitLayout;
        std::string portraitMonitor;
        std::string blockedTag;
    };

    struct SResizeSession {
        bool                                                 active = false;
        SResizeConfig                                        config;
        char                                                 axis = 'x';
        std::string                                          command;
        std::string                                          targetId;
        std::string                                          edge;
        int                                                  intervalMs = DEFAULT_INTERVAL_MS;
        uint64_t                                             generation = 0;
        PHLWINDOWREF                                         target;
        PHLWORKSPACEREF                                      workspace;
        WP<Layout::CSpace>                                   space;
        WP<Layout::CAlgorithm>                               algorithm;
        const Layout::ITiledAlgorithm*                       tiledAlgorithm = nullptr;
        std::optional<int>                                   lastPosition;
        std::optional<std::chrono::steady_clock::time_point> lastEmission;
    };

    HANDLE              g_handle = nullptr;
    CHyprSignalListener g_mouseMoveListener;
    CHyprSignalListener g_preReloadListener;
    SResizeSession      g_session;
    uint64_t            g_sessionGeneration = 0;

    int returnStartStatus(lua_State* state, bool started, bool handled) {
        lua_pushboolean(state, started);
        lua_pushboolean(state, handled);
        return 2;
    }

    void clearSession() {
        ++g_sessionGeneration;
        g_session = {};
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
            Desktop::focusState()->fullWindowFocus(target, Desktop::FOCUS_REASON_CLICK);

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
        if (!window || window->isFloating() || !window->m_workspace)
            return std::nullopt;

        const auto space = window->m_workspace->space();
        if (!space)
            return std::nullopt;

        const auto& algorithm = space->algorithm();
        if (!algorithm || !algorithm->tiledAlgo())
            return std::nullopt;

        return Layout::Supplementary::algoMatcher()->getNameForTiledAlgo(algorithm->tiledAlgo().get());
    }

    std::optional<char> resizeAxis(PHLWINDOW window, const SResizeConfig& config) {
        const auto layout = tiledLayoutName(window);
        if (!layout)
            return std::nullopt;

        if (*layout == config.portraitLayout)
            return 'y';

        if (*layout == config.ultrawideLayout) {
            const auto monitor = window->m_monitor.lock();
            return monitor && monitor->m_name == config.portraitMonitor ? 'y' : 'x';
        }

        return std::nullopt;
    }

    bool eligibleTarget(PHLWINDOW window, const SResizeConfig& config) {
        return window && !window->isFloating() && !hasTag(window, config.blockedTag) && resizeAxis(window, config).has_value();
    }

    int pointerInterval(PHLWINDOW window) {
        const auto monitor = window ? window->m_monitor.lock() : nullptr;
        const auto refresh = monitor && monitor->m_refreshRate > 0 ? monitor->m_refreshRate : 60.0;
        return std::clamp(static_cast<int>(std::lround(1000.0 / refresh)), MINIMUM_INTERVAL_MS, MAXIMUM_INTERVAL_MS);
    }

    struct SResizePlan {
        char                           axis;
        std::string                    command;
        std::string                    targetId;
        std::string                    edge;
        int                            intervalMs;
        PHLWORKSPACE                   workspace;
        SP<Layout::CSpace>             space;
        SP<Layout::CAlgorithm>         algorithm;
        const Layout::ITiledAlgorithm* tiledAlgorithm;
    };

    void applyPlan(const SResizePlan& plan, PHLWINDOW target) {
        g_session.axis           = plan.axis;
        g_session.command        = plan.command;
        g_session.targetId       = plan.targetId;
        g_session.edge           = plan.edge;
        g_session.intervalMs     = plan.intervalMs;
        g_session.target         = target;
        g_session.workspace      = plan.workspace;
        g_session.space          = plan.space;
        g_session.algorithm      = plan.algorithm;
        g_session.tiledAlgorithm = plan.tiledAlgorithm;
        g_session.lastPosition.reset();
        g_session.lastEmission.reset();
    }

    std::optional<SResizePlan> resizePlan(PHLWINDOW target, const SResizeConfig& config, const Vector2D& cursor) {
        const auto axis = resizeAxis(target, config);
        if (!axis)
            return std::nullopt;

        const auto geometry   = windowGeometry(target);
        const auto coordinate = *axis == 'x' ? cursor.x : cursor.y;
        const auto midpoint   = *axis == 'x' ? geometry.x + geometry.width / 2.0 : geometry.y + geometry.height / 2.0;

        const auto workspace = target->m_workspace;
        const auto space     = workspace ? workspace->space() : nullptr;
        const auto algorithm = space ? space->algorithm() : nullptr;
        if (!workspace || !space || !algorithm || !algorithm->tiledAlgo())
            return std::nullopt;

        return SResizePlan{
            .axis           = *axis,
            .command        = *axis == 'x' ? "resize-x-at" : "resize-y-at",
            .targetId       = std::format("address:0x{:x}", reinterpret_cast<uintptr_t>(target.get())),
            .edge           = *axis == 'x' ? (coordinate < midpoint ? "left" : "right") : (coordinate < midpoint ? "up" : "down"),
            .intervalMs     = pointerInterval(target),
            .workspace      = workspace,
            .space          = space,
            .algorithm      = algorithm,
            .tiledAlgorithm = algorithm->tiledAlgo().get(),
        };
    }

    bool validSessionRoute(PHLWINDOW& target, SP<Layout::CSpace>& space) {
        target               = g_session.target.lock();
        const auto workspace = g_session.workspace.lock();
        space                = g_session.space.lock();
        const auto algorithm = g_session.algorithm.lock();
        if (!target || !target->mapped() || !workspace || !space || !algorithm || target->m_workspace != workspace || workspace->space() != space ||
            space->algorithm() != algorithm || !algorithm->tiledAlgo() || algorithm->tiledAlgo().get() != g_session.tiledAlgorithm || !eligibleTarget(target, g_session.config) ||
            resizeAxis(target, g_session.config) != g_session.axis)
            return false;
        return true;
    }

    bool emitPosition(bool force) {
        if (!g_session.active || !g_pInputManager)
            return false;

        const auto         cursor = g_pInputManager->getMouseCoordsInternal();
        PHLWINDOW          target;
        SP<Layout::CSpace> space;
        if (!validSessionRoute(target, space)) {
            clearSession();
            return false;
        }

        const auto generation = g_session.generation;
        const auto now        = std::chrono::steady_clock::now();
        if (!force && g_session.lastEmission && now - *g_session.lastEmission < std::chrono::milliseconds(g_session.intervalMs))
            return true;

        const auto raw     = g_session.axis == 'x' ? cursor.x : cursor.y;
        const auto current = static_cast<int>(std::lround(raw));
        if (g_session.lastPosition && *g_session.lastPosition == current)
            return true;

        if (!space->layoutMsg(std::format("{} {} {} {}", g_session.command, g_session.targetId, g_session.edge, current))) {
            if (g_session.active && g_session.generation == generation)
                clearSession();
            return false;
        }

        if (!g_session.active || g_session.generation != generation)
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

        const auto generation = g_session.generation;
        if (save && emitPosition(true) && g_session.active && g_session.generation == generation) {
            PHLWINDOW          target;
            SP<Layout::CSpace> space;
            if (validSessionRoute(target, space) && !space->layoutMsg("save-resize")) {
                if (g_session.active && g_session.generation == generation)
                    clearSession();
                return;
            }
        }

        if (g_session.active && g_session.generation == generation)
            clearSession();
    }

    int startResize(lua_State* state) {
        const SResizeConfig config{
            .ultrawideLayout = luaL_checkstring(state, 1),
            .portraitLayout  = luaL_checkstring(state, 2),
            .portraitMonitor = luaL_checkstring(state, 3),
            .blockedTag      = luaL_checkstring(state, 4),
        };

        stopResize(false);
        if (!g_pInputManager || !Desktop::viewState())
            return returnStartStatus(state, false, false);

        const auto cursor = g_pInputManager->getMouseCoordsInternal();
        const auto target = targetWindow(cursor);
        if (!eligibleTarget(target, config))
            return returnStartStatus(state, false, true);

        const auto plan = resizePlan(target, config, cursor);
        if (!plan)
            return returnStartStatus(state, false, true);

        g_session.active     = true;
        g_session.generation = ++g_sessionGeneration;
        g_session.config     = config;
        applyPlan(*plan, target);

        return returnStartStatus(state, true, true);
    }

    int stopResizeLua(lua_State* state) {
        const bool active = g_session.active;
        stopResize(true);
        lua_pushboolean(state, active);
        return 1;
    }

    int supportsDirectUpdates(lua_State* state) {
        lua_pushboolean(state, true);
        return 1;
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_handle = handle;

    if (!HyprlandAPI::addLuaFunction(handle, "custom_layout_resize", "start", startResize) || !HyprlandAPI::addLuaFunction(handle, "custom_layout_resize", "stop", stopResizeLua) ||
        !HyprlandAPI::addLuaFunction(handle, "custom_layout_resize", "supports_direct_updates", supportsDirectUpdates))
        throw std::runtime_error("custom-layout-resize: failed to register Lua functions");

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { emitPosition(false); });
    g_preReloadListener = Event::bus()->m_events.config.preReload.listen([] { stopResize(false); });

    return {
        "custom-layout-resize",
        "Drive custom-layout drag resize from native Hyprland pointer state",
        "local",
        "0.4.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    stopResize(false);
    g_mouseMoveListener.reset();
    g_preReloadListener.reset();

    g_handle = nullptr;
}
