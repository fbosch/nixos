#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>

#include <algorithm>
#include <array>
#include <stdexcept>
#include <string_view>

namespace {

    constexpr auto EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr auto COMMIT_WINDOW_SIGNATURE  = "CWindow::commitWindow()";
    constexpr std::array<std::string_view, 3> PIP_APP_IDS = {
        "app.zen_browser.zen-pip",
        "one.ablaze.floorp-pip",
        "helium-pip",
    };

    HANDLE         g_handle           = nullptr;
    CFunctionHook* g_commitWindowHook = nullptr;

    using CommitWindowFn = void (*)(CWindow*);

    bool isPictureInPicture(const std::string_view appID) {
        return std::ranges::contains(PIP_APP_IDS, appID);
    }

    void hookedCommitWindow(CWindow* window) {
        const auto original = g_commitWindowHook ? reinterpret_cast<CommitWindowFn>(g_commitWindowHook->m_original) : nullptr;
        if (!original || !window)
            return;

        const auto xdgSurface = window->m_xdgSurface.lock();
        const auto toplevel   = xdgSurface ? xdgSurface->m_toplevel.lock() : nullptr;
        if (!xdgSurface || !toplevel || !xdgSurface->m_initialCommit || !isPictureInPicture(window->fetchClass())) {
            original(window);
            return;
        }

        // Zero lets the client choose its media-derived size instead of accepting a tiled prediction.
        toplevel->setSize(Vector2D{});
    }

    bool installCommitWindowHook() {
        const auto            functions = HyprlandAPI::findFunctionsByName(g_handle, "commitWindow");
        const SFunctionMatch* match     = nullptr;

        for (const auto& function : functions) {
            if (function.demangled != COMMIT_WINDOW_SIGNATURE)
                continue;
            if (match)
                return false;
            match = &function;
        }

        if (!match)
            return false;

        g_commitWindowHook = HyprlandAPI::createFunctionHook(g_handle, match->address, reinterpret_cast<void*>(&hookedCommitWindow));
        if (g_commitWindowHook && g_commitWindowHook->hook())
            return true;

        if (g_commitWindowHook)
            HyprlandAPI::removeFunctionHook(g_handle, g_commitWindowHook);
        g_commitWindowHook = nullptr;
        return false;
    }

    void cleanupPluginState() {
        if (g_commitWindowHook && g_handle)
            HyprlandAPI::removeFunctionHook(g_handle, g_commitWindowHook);
        g_commitWindowHook = nullptr;
        g_handle           = nullptr;
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("pip-pre-map: unsupported Hyprland commit");

    g_handle = handle;
    if (!installCommitWindowHook()) {
        cleanupPluginState();
        throw std::runtime_error("pip-pre-map: failed to hook CWindow::commitWindow()");
    }

    return {
        "pip-pre-map",
        "Prevent tiled initial size prediction for relabeled browser PiP windows",
        "local",
        "0.1.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
