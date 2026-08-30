#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
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

namespace {

    constexpr auto   EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr double DEFAULT_REFRESH_RATE_HZ  = 60.0;
    constexpr int    MIN_UPDATE_INTERVAL_MS   = 6;
    constexpr int    MAX_UPDATE_INTERVAL_MS   = 17;

    struct SInteraction {
        PHLWINDOWREF                                         window;
        std::string                                          kind;
        std::optional<CBox>                                  lastGeometry;
        std::optional<std::chrono::steady_clock::time_point> lastEmission;
    };

    HANDLE                             g_handle = nullptr;
    SP<Event::CEventBus::CCustomEvent> g_finishedEvent;
    SP<Event::CEventBus::CCustomEvent> g_updatedEvent;
    CHyprSignalListener                g_mouseMoveListener;
    CHyprSignalListener                g_mouseButtonListener;
    CHyprSignalListener                g_keyListener;
    std::optional<SInteraction>        g_interaction;
    uint64_t                           g_syncSequence = 0;

    std::optional<std::string_view> interactionKind(eMouseBindMode mode) {
        switch (mode) {
            case MBIND_MOVE: return "move";
            case MBIND_RESIZE:
            case MBIND_RESIZE_FORCE_RATIO:
            case MBIND_RESIZE_BLOCK_RATIO: return "resize";
            default: return std::nullopt;
        }
    }

    bool sameGeometry(const CBox& first, const CBox& second) {
        return first.x == second.x && first.y == second.y && first.width == second.width && first.height == second.height;
    }

    std::chrono::milliseconds updateInterval(PHLWINDOW window) {
        const auto monitor = window ? window->m_monitor.lock() : nullptr;
        const auto refreshRate = monitor && std::isfinite(monitor->m_refreshRate) && monitor->m_refreshRate > 0.F ?
            static_cast<double>(monitor->m_refreshRate) :
            DEFAULT_REFRESH_RATE_HZ;
        const auto intervalMs = static_cast<int>(std::lround(1000.0 / refreshRate));
        return std::chrono::milliseconds{std::clamp(intervalMs, MIN_UPDATE_INTERVAL_MS, MAX_UPDATE_INTERVAL_MS)};
    }

    void postSocketUpdate(PHLWINDOW window, std::string_view kind, const CBox& geometry) {
        if (!window || !IPC::Socket2::sock())
            return;

        const auto monitor = window->m_monitor.lock();
        if (!monitor)
            return;

        IPC::Socket2::sock()->postEvent({
            .event = "windowinteractionupdated",
            .data  = std::format(
                "0x{:x},{},{},{},{},{},{}",
                reinterpret_cast<uintptr_t>(window.get()),
                kind,
                monitor->m_id,
                geometry.x,
                geometry.y,
                geometry.width,
                geometry.height),
        });
    }

    void emitUpdated(SInteraction& interaction) {
        if (!g_updatedEvent)
            return;

        const auto window = interaction.window.lock();
        if (!Desktop::View::validMapped(window))
            return;

        const auto geometry = window->layoutBox();
        if (interaction.lastGeometry && sameGeometry(*interaction.lastGeometry, geometry))
            return;

        const auto now = std::chrono::steady_clock::now();
        if (interaction.lastEmission && now - *interaction.lastEmission < updateInterval(window))
            return;

        if (!g_updatedEvent->emit({
                window,
                interaction.kind,
                geometry.x,
                geometry.y,
                geometry.width,
                geometry.height,
            }))
            return;

        postSocketUpdate(window, interaction.kind, geometry);
        interaction.lastGeometry = geometry;
        interaction.lastEmission = now;
    }

    void emitFinished(SInteraction interaction) {
        if (!g_finishedEvent)
            return;

        const auto window = interaction.window.lock();
        if (!Desktop::View::validMapped(window))
            return;

        const auto geometry = window->layoutBox();
        g_finishedEvent->emit({
            window,
            interaction.kind,
            geometry.x,
            geometry.y,
            geometry.width,
            geometry.height,
        });
    }

    void syncInteraction() {
        if (!g_handle || !g_layoutManager)
            return;

        const auto& controller = g_layoutManager->dragController();
        if (!controller)
            return;

        const auto target = controller->target();
        if (target && controller->dragThresholdReached()) {
            const auto kind   = interactionKind(controller->mode());
            const auto window = target->window();
            if (!kind || !Desktop::View::validMapped(window))
                return;

            const auto captured = g_interaction ? g_interaction->window.lock() : nullptr;
            if (!g_interaction || captured != window || g_interaction->kind != *kind)
                g_interaction = SInteraction{.window = window, .kind = std::string{*kind}};

            emitUpdated(*g_interaction);
            return;
        }

        if (!target && g_interaction) {
            auto finished = std::move(*g_interaction);
            g_interaction.reset();
            emitFinished(std::move(finished));
        }
    }

    void scheduleSync(bool captureCurrent) {
        // Button and key events can release the drag target before the idle turn,
        // so capture their current state first. Mouse movement is sampled only
        // after Hyprland has applied the new geometry.
        if (captureCurrent)
            syncInteraction();

        if (g_syncSequence || !g_pEventLoopManager)
            return;

        g_syncSequence = g_pEventLoopManager->doLater([] {
            g_syncSequence = 0;
            syncInteraction();
        });
    }

    void cleanupPluginState() {
        if (g_syncSequence && g_pEventLoopManager)
            g_pEventLoopManager->removeDoLater(g_syncSequence);
        g_syncSequence = 0;

        g_mouseMoveListener.reset();
        g_mouseButtonListener.reset();
        g_keyListener.reset();
        g_interaction.reset();

        if (g_handle && g_finishedEvent)
            HyprlandAPI::removeEvent(g_handle, g_finishedEvent->m_name);
        if (g_handle && g_updatedEvent)
            HyprlandAPI::removeEvent(g_handle, g_updatedEvent->m_name);

        g_finishedEvent.reset();
        g_updatedEvent.reset();
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

    // Config reloads replace Lua handlers without notifying already-loaded
    // plugins. Re-registering the custom events exposes them to the new Lua state.
    int rebindEvents(lua_State* state) {
        if (!g_handle || !g_finishedEvent || !g_updatedEvent) {
            lua_pushboolean(state, false);
            return 1;
        }

        HyprlandAPI::removeEvent(g_handle, g_finishedEvent->m_name);
        HyprlandAPI::removeEvent(g_handle, g_updatedEvent->m_name);

        const bool finished = HyprlandAPI::addEvent(g_handle, g_finishedEvent);
        const bool updated  = HyprlandAPI::addEvent(g_handle, g_updatedEvent);
        if (!finished || !updated) {
            if (finished)
                HyprlandAPI::removeEvent(g_handle, g_finishedEvent->m_name);
            if (updated)
                HyprlandAPI::removeEvent(g_handle, g_updatedEvent->m_name);
        }

        lua_pushboolean(state, finished && updated);
        return 1;
    }

    int supportsUpdates(lua_State* state) {
        lua_pushboolean(state, true);
        return 1;
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("window-interaction-hooks: unsupported Hyprland commit");

    g_handle        = handle;
    g_finishedEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "window_interaction_hooks.finished",
        std::vector{
            Event::CEventBus::CCustomEvent::TYPE_WINDOW,
            Event::CEventBus::CCustomEvent::TYPE_STRING,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
        });
    g_updatedEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "window_interaction_hooks.updated",
        std::vector{
            Event::CEventBus::CCustomEvent::TYPE_WINDOW,
            Event::CEventBus::CCustomEvent::TYPE_STRING,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
        });

    CPluginInitializationGuard cleanup;
    if (!HyprlandAPI::addEvent(handle, g_finishedEvent) || !HyprlandAPI::addEvent(handle, g_updatedEvent))
        throw std::runtime_error("window-interaction-hooks: failed to register interaction events");

    if (!HyprlandAPI::addLuaFunction(handle, "window_interaction_hooks", "rebind", rebindEvents) ||
        !HyprlandAPI::addLuaFunction(handle, "window_interaction_hooks", "supports_updates", supportsUpdates)) {
        throw std::runtime_error("window-interaction-hooks: failed to register Lua functions");
    }

    g_mouseMoveListener   = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { scheduleSync(false); });
    g_mouseButtonListener = Event::bus()->m_events.input.mouse.button.listen([](const auto&, auto&) { scheduleSync(true); });
    g_keyListener         = Event::bus()->m_events.input.keyboard.key.listen([](const auto&, auto&) { scheduleSync(true); });

    const auto description = PLUGIN_DESCRIPTION_INFO{
        "window-interaction-hooks",
        "Emit live and completed interactive window move and resize events",
        "local",
        "0.2.0",
    };
    cleanup.release();
    return description;
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
