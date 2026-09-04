#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/helpers/AsyncDialogBox.hpp>
#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprutils/os/FileDescriptor.hpp>
#include <hyprutils/os/Process.hpp>

#include <algorithm>
#include <chrono>
#include <ranges>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

// Hyprland has no public ANR interception API. Exact-commit validation below
// confines this private access to the compositor version used for the build.
#define private public
#include <hyprland/src/managers/ANRManager.hpp>
#undef private

namespace {

    constexpr auto EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr auto ON_TICK_SIGNATURE        = "CANRManager::onTick()";

    HANDLE                           g_handle = nullptr;
    SP<Config::Values::CStringValue> g_ignoredTags;
    CFunctionHook*                   g_onTickHook = nullptr;

    using OnTickFn = void (*)(CANRManager*);

    std::string_view trim(std::string_view value) {
        constexpr std::string_view WHITESPACE = " \t\r\n";
        const auto                 first      = value.find_first_not_of(WHITESPACE);
        if (first == std::string_view::npos)
            return {};

        const auto last = value.find_last_not_of(WHITESPACE);
        return value.substr(first, last - first + 1);
    }

    std::vector<std::string> configuredTags() {
        std::vector<std::string> tags;
        if (!g_ignoredTags)
            return tags;

        const std::string configured = g_ignoredTags->value();
        size_t            start      = 0;
        while (start <= configured.size()) {
            const auto end = configured.find(',', start);
            const auto tag = trim(std::string_view{configured}.substr(start, end - start));
            if (!tag.empty())
                tags.emplace_back(tag);

            if (end == std::string::npos)
                break;
            start = end + 1;
        }

        return tags;
    }

    bool hasIgnoredTag(PHLWINDOW window, const std::vector<std::string>& ignoredTags) {
        if (!window || !window->m_ruleApplicator)
            return false;

        return std::ranges::any_of(ignoredTags, [&window](const auto& tag) {
            return window->m_ruleApplicator->m_tagKeeper.isTagged(tag);
        });
    }

    bool resetIfIgnored(const SP<CANRManager::SANRData>& data, const std::vector<std::string>& ignoredTags) {
        if (!data || ignoredTags.empty())
            return false;

        std::vector<PHLWINDOW> mappedWindows;
        for (const auto& windowData : data->windows) {
            const auto window = windowData.window.lock();
            if (!Desktop::View::validMapped(window))
                continue;
            if (!hasIgnoredTag(window, ignoredTags))
                return false;
            mappedWindows.emplace_back(window);
        }

        if (mappedWindows.empty())
            return false;

        data->missedResponses = 0;
        data->dialogSaidWait  = false;
        data->killDialog();
        for (const auto& window : mappedWindows)
            window->presentation().setNotResponding(false);
        return true;
    }

    void resetIgnoredClients(CANRManager* manager) {
        if (!manager)
            return;

        const auto ignoredTags = configuredTags();
        if (ignoredTags.empty())
            return;

        for (const auto& data : manager->m_data)
            resetIfIgnored(data, ignoredTags);
    }

    void hookedOnTick(CANRManager* manager) {
        resetIgnoredClients(manager);

        const auto original = g_onTickHook ? reinterpret_cast<OnTickFn>(g_onTickHook->m_original) : nullptr;
        if (original)
            original(manager);

        // Keep the counter at zero rather than allowing one missed ping to
        // accumulate on every intentionally ignored ANR pass.
        resetIgnoredClients(manager);
    }

    bool installOnTickHook() {
        const auto            functions = HyprlandAPI::findFunctionsByName(g_handle, "onTick");
        const SFunctionMatch* match     = nullptr;

        for (const auto& function : functions) {
            if (function.demangled != ON_TICK_SIGNATURE)
                continue;
            if (match)
                return false;
            match = &function;
        }

        if (!match)
            return false;

        g_onTickHook = HyprlandAPI::createFunctionHook(g_handle, match->address, reinterpret_cast<void*>(&hookedOnTick));
        if (g_onTickHook && g_onTickHook->hook())
            return true;

        if (g_onTickHook)
            HyprlandAPI::removeFunctionHook(g_handle, g_onTickHook);
        g_onTickHook = nullptr;
        return false;
    }

    void cleanupPluginState() {
        if (g_onTickHook && g_handle)
            HyprlandAPI::removeFunctionHook(g_handle, g_onTickHook);
        g_onTickHook = nullptr;
        g_ignoredTags.reset();
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

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("anr-tag-ignore: unsupported Hyprland commit");

    g_handle      = handle;
    g_ignoredTags = makeShared<Config::Values::CStringValue>(
        "plugin:anr_tag_ignore:ignored_tags",
        "Comma-separated tags that reset ANR state when present on every mapped window for a client",
        Config::STRING{});

    CPluginInitializationGuard cleanup;
    if (!HyprlandAPI::addConfigValueV2(handle, g_ignoredTags))
        throw std::runtime_error("anr-tag-ignore: failed to register configuration");
    if (!installOnTickHook())
        throw std::runtime_error("anr-tag-ignore: failed to hook CANRManager::onTick()");

    HyprlandAPI::reloadConfig();
    cleanup.release();
    return {
        "anr-tag-ignore",
        "Reset Hyprland ANR state for clients whose windows carry configured tags",
        "local",
        "0.1.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
