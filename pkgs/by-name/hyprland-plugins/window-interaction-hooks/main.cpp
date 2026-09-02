#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

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

    constexpr auto EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;

    // Hyprland clears the controller latch after invoking a bind, but zero disables the threshold entirely.
    constexpr bool interactionThresholdReached(Config::INTEGER configuredThreshold, bool controllerReached) {
        return configuredThreshold <= 0 || controllerReached;
    }

    static_assert(interactionThresholdReached(0, false));
    static_assert(!interactionThresholdReached(1, false));
    static_assert(interactionThresholdReached(1, true));

    struct SPendingUpdate {
        PHLMONITORREF monitor;
        CBox          geometry;
    };

    struct SInteraction {
        PHLWINDOWREF                  window;
        std::string                   kind;
        std::optional<CBox>           lastGeometry;
        std::optional<SPendingUpdate> pendingUpdate;
    };

    HANDLE                             g_handle = nullptr;
    SP<Event::CEventBus::CCustomEvent> g_finishedEvent;
    SP<Event::CEventBus::CCustomEvent> g_updatedEvent;
    CHyprSignalListener                g_mouseMoveListener;
    CHyprSignalListener                g_mouseButtonListener;
    CHyprSignalListener                g_keyListener;
    CHyprSignalListener                g_renderPreListener;
    std::optional<SInteraction>        g_interaction;
    uint64_t                           g_syncSequence = 0;
    uint64_t                           g_deliverySequence = 0;

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

    void postSocketUpdate(PHLWINDOW window, PHLMONITOR monitor, std::string_view kind, const CBox& geometry) {
        if (!window || !monitor || !IPC::Socket2::sock())
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

    void cancelPendingDelivery() {
        if (g_deliverySequence && g_pEventLoopManager)
            g_pEventLoopManager->removeDoLater(g_deliverySequence);
        g_deliverySequence = 0;
    }

    void deliverPendingUpdate() {
        g_deliverySequence = 0;
        if (!g_interaction || !g_interaction->pendingUpdate)
            return;

        auto update = std::move(*g_interaction->pendingUpdate);
        g_interaction->pendingUpdate.reset();

        const auto window = g_interaction->window.lock();
        if (!Desktop::View::validMapped(window))
            return;

        if (g_interaction->lastGeometry && sameGeometry(*g_interaction->lastGeometry, update.geometry))
            return;

        if (g_updatedEvent) {
            g_updatedEvent->emit({
                window,
                g_interaction->kind,
                update.geometry.x,
                update.geometry.y,
                update.geometry.width,
                update.geometry.height,
            });
        }

        postSocketUpdate(window, update.monitor.lock(), g_interaction->kind, update.geometry);
        g_interaction->lastGeometry = update.geometry;
    }

    void schedulePendingDelivery() {
        if (g_deliverySequence || !g_pEventLoopManager)
            return;

        g_deliverySequence = g_pEventLoopManager->doLater([] { deliverPendingUpdate(); });
    }

    bool captureActiveInteraction() {
        if (!g_handle || !g_layoutManager)
            return false;

        const auto& controller = g_layoutManager->dragController();
        if (!controller)
            return false;

        static auto PDRAGTHRESHOLD = CConfigValue<Config::INTEGER>("binds:drag_threshold");

        const auto  target = controller->target();
        if (!target || !interactionThresholdReached(*PDRAGTHRESHOLD, controller->dragThresholdReached()))
            return false;

        const auto kind   = interactionKind(controller->mode());
        const auto window = target->window();
        if (!kind || !Desktop::View::validMapped(window))
            return false;

        const auto captured = g_interaction ? g_interaction->window.lock() : nullptr;
        if (!g_interaction || captured != window || g_interaction->kind != *kind) {
            cancelPendingDelivery();
            g_interaction = SInteraction{.window = window, .kind = std::string{*kind}};
        }

        return true;
    }

    void captureFrameUpdate(PHLMONITOR monitor) {
        if (!monitor || !captureActiveInteraction() || !g_interaction)
            return;

        const auto window = g_interaction->window.lock();
        if (!Desktop::View::validMapped(window) || window->m_monitor.lock() != monitor)
            return;

        const auto geometry = window->layoutBox();
        if (g_interaction->lastGeometry && sameGeometry(*g_interaction->lastGeometry, geometry))
            return;
        if (g_interaction->pendingUpdate && sameGeometry(g_interaction->pendingUpdate->geometry, geometry))
            return;

        g_interaction->pendingUpdate = SPendingUpdate{.monitor = monitor, .geometry = geometry};
        schedulePendingDelivery();
    }

    void flushFinalUpdate() {
        if (!g_interaction)
            return;

        cancelPendingDelivery();

        const auto window = g_interaction->window.lock();
        if (!Desktop::View::validMapped(window))
            return;

        g_interaction->pendingUpdate = SPendingUpdate{
            .monitor  = window->m_monitor,
            .geometry = window->layoutBox(),
        };
        deliverPendingUpdate();
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

    void finishInteraction() {
        if (!g_interaction)
            return;

        flushFinalUpdate();

        auto finished = std::move(*g_interaction);
        g_interaction.reset();
        emitFinished(std::move(finished));
    }

    void syncInteraction() {
        if (!g_handle || !g_layoutManager)
            return;

        const auto& controller = g_layoutManager->dragController();
        if (!controller)
            return;

        const auto target = controller->target();
        if (target) {
            captureActiveInteraction();
            return;
        }

        if (g_interaction)
            finishInteraction();
    }

    void scheduleSync(bool captureCurrent) {
        // Input events are emitted before Hyprland mutates the drag controller.
        // Preserve the active target before button/key release, then observe the
        // resulting lifecycle state from idle. Geometry delivery is frame-driven.
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
        cancelPendingDelivery();

        g_mouseMoveListener.reset();
        g_mouseButtonListener.reset();
        g_keyListener.reset();
        g_renderPreListener.reset();
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
    g_renderPreListener   = Event::bus()->m_events.render.pre.listen([](PHLMONITOR monitor) { captureFrameUpdate(monitor); });

    const auto description = PLUGIN_DESCRIPTION_INFO{
        "window-interaction-hooks",
        "Emit frame-coalesced and completed interactive window move and resize events",
        "local",
        "0.2.0",
    };
    cleanup.release();
    return description;
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
