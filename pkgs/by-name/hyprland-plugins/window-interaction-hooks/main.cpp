#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include <cstdint>
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

    struct SInteraction {
        PHLWINDOWREF window;
        std::string  kind;
    };

    HANDLE                             g_handle = nullptr;
    SP<Event::CEventBus::CCustomEvent> g_finishedEvent;
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
            if (kind && Desktop::View::validMapped(window))
                g_interaction = SInteraction{window, std::string{*kind}};
            return;
        }

        if (!target && g_interaction) {
            auto finished = std::move(*g_interaction);
            g_interaction.reset();
            emitFinished(std::move(finished));
        }
    }

    void scheduleSync() {
        // Input events are emitted before Hyprland mutates the drag controller.
        // Capture the active interaction now, then observe its final state from idle.
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

        g_finishedEvent.reset();
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
    // plugins. Re-registering the custom event exposes it to the new Lua state.
    int rebindFinishedEvent(lua_State* state) {
        if (!g_handle || !g_finishedEvent) {
            lua_pushboolean(state, false);
            return 1;
        }

        HyprlandAPI::removeEvent(g_handle, g_finishedEvent->m_name);
        lua_pushboolean(state, HyprlandAPI::addEvent(g_handle, g_finishedEvent));
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

    CPluginInitializationGuard cleanup;
    if (!HyprlandAPI::addEvent(handle, g_finishedEvent))
        throw std::runtime_error("window-interaction-hooks: failed to register finished event");

    if (!HyprlandAPI::addLuaFunction(handle, "window_interaction_hooks", "rebind", rebindFinishedEvent))
        throw std::runtime_error("window-interaction-hooks: failed to register Lua functions");

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) { scheduleSync(); });
    g_mouseButtonListener = Event::bus()->m_events.input.mouse.button.listen([](const auto&, auto&) { scheduleSync(); });
    g_keyListener = Event::bus()->m_events.input.keyboard.key.listen([](const auto&, auto&) { scheduleSync(); });

    const auto description = PLUGIN_DESCRIPTION_INFO{
        "window-interaction-hooks",
        "Emit completed interactive window move and resize events",
        "local",
        "0.1.0",
    };
    cleanup.release();
    return description;
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
