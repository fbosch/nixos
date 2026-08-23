#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include <stdexcept>
#include <vector>

extern "C" {
#include <lua.h>
}

namespace {

    constexpr auto        EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr const char* MOTION_EVENT              = "custom_layout_pointer.motion";

    HANDLE                             g_handle = nullptr;
    bool                               g_active = false;
    SP<Event::CEventBus::CCustomEvent> g_motionEvent;
    CHyprSignalListener                g_mouseMoveListener;
    CHyprSignalListener                g_preReloadListener;

    int startForwarding(lua_State* L) {
        g_active = true;
        lua_pushboolean(L, true);
        return 1;
    }

    int stopForwarding(lua_State* L) {
        const bool wasActive = g_active;
        g_active             = false;
        lua_pushboolean(L, wasActive);
        return 1;
    }

    void emitPointerPosition(const Vector2D& position) {
        if (!g_active || !g_motionEvent)
            return;

        (void)g_motionEvent->emit({position.x, position.y});
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

    if (!HyprlandAPI::addLuaFunction(handle, "custom_layout_pointer", "start", startForwarding))
        throw std::runtime_error("custom-layout-pointer: failed to register start action");
    if (!HyprlandAPI::addLuaFunction(handle, "custom_layout_pointer", "stop", stopForwarding))
        throw std::runtime_error("custom-layout-pointer: failed to register stop action");

    g_motionEvent = makeShared<Event::CEventBus::CCustomEvent>(
        MOTION_EVENT,
        std::vector{
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
            Event::CEventBus::CCustomEvent::TYPE_DOUBLE,
        });
    if (!HyprlandAPI::addEvent(handle, g_motionEvent))
        throw std::runtime_error("custom-layout-pointer: failed to register motion event");

    g_mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](const Vector2D& position, auto&) {
        emitPointerPosition(position);
    });
    g_preReloadListener = Event::bus()->m_events.config.preReload.listen([] { g_active = false; });

    return {
        "custom-layout-pointer",
        "Forward pointer motion to Lua while a custom layout interaction is active",
        "local",
        "0.1.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_active = false;
    g_mouseMoveListener.reset();
    g_preReloadListener.reset();

    if (g_handle && g_motionEvent)
        HyprlandAPI::removeEvent(g_handle, MOTION_EVENT);

    g_motionEvent.reset();
    g_handle = nullptr;
}
