#include <hyprland/src/animation/AnimationManager.hpp>
#include <hyprland/src/config/shared/animation/AnimationTree.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cmath>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <unordered_map>

extern "C" {
#include <lauxlib.h>
}

namespace {

    constexpr auto        EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr const char* FOCUS_ANIMATION_LEAF     = "windowsFocus";
    constexpr float       DEFAULT_START_SCALE      = 0.96F;
    constexpr float       MINIMUM_SCALE            = 0.5F;
    constexpr float       MAXIMUM_SCALE            = 1.2F;
    constexpr auto        RAPID_FOCUS_INTERVAL     = std::chrono::milliseconds{120};

    using SAnimationPropertyConfig = Hyprutils::Animation::SAnimationPropertyConfig;
    using AnimationConfigMap       = std::unordered_map<std::string, SP<SAnimationPropertyConfig>>;

    CHyprSignalListener g_focusListener;
    CHyprSignalListener g_destroyListener;
    PHLWINDOWREF        g_window;
    PHLANIMVAR<float>   g_scale;
    std::chrono::steady_clock::time_point g_lastFocusTrigger;

    SP<SAnimationPropertyConfig> prepareAnimationLeaf() {
        // Hyprland has no plugin API for adding animation leaves. Plugins are
        // commit-bound already, so add this single node to the internal tree.
        auto&      animations = const_cast<AnimationConfigMap&>(Config::animationTree()->getAnimationConfig());
        const auto parent     = animations.find("windows");
        if (parent == animations.end() || !parent->second)
            return nullptr;

        auto& focus = animations[FOCUS_ANIMATION_LEAF];
        if (!focus)
            focus = makeShared<SAnimationPropertyConfig>();

        focus->overridden       = true;
        focus->internalBezier   = "linear";
        focus->internalStyle    = "popin 96%";
        focus->internalSpeed    = 1.F;
        focus->internalEnabled  = 0;
        focus->pValues          = focus;
        focus->pParentAnimation = parent->second;

        return focus;
    }

    void disableAnimationLeaf() {
        const auto focus = Config::animationTree()->getAnimationPropertyConfig(FOCUS_ANIMATION_LEAF);
        if (focus)
            focus->internalEnabled = 0;
    }

    float startScaleFromStyle(std::string_view style) {
        if (!style.starts_with("popin"))
            return DEFAULT_START_SCALE;

        const auto percent = style.rfind('%');
        if (percent == std::string_view::npos)
            return DEFAULT_START_SCALE;

        const auto separator = style.rfind(' ', percent);
        if (separator == std::string_view::npos || separator + 1 >= percent)
            return DEFAULT_START_SCALE;

        float       value = 0.F;
        const auto* begin = style.data() + separator + 1;
        const auto* end   = style.data() + percent;
        const auto [position, error] = std::from_chars(begin, end, value);
        if (error != std::errc{} || position != end || !std::isfinite(value))
            return DEFAULT_START_SCALE;

        return std::clamp(value / 100.F, MINIMUM_SCALE, MAXIMUM_SCALE);
    }

    void restoreWindowGeometry() {
        const auto window = g_window.lock();
        if (!validMapped(window))
            return;

        auto& position = window->positionAnimation();
        auto& size     = window->sizeAnimation();
        if (!position || !size || position->isBeingAnimated() || size->isBeingAnimated())
            return;

        position->value() = position->goal();
        size->value()     = size->goal();

        const auto monitor = window->m_monitor.lock();
        if (g_pHyprRenderer && monitor)
            g_pHyprRenderer->damageMonitor(monitor);
    }

    void stopAnimation() {
        if (g_scale)
            g_scale->resetAllCallbacks();

        restoreWindowGeometry();
        g_scale.reset();
        g_window.reset();
    }

    void updateScale(WP<Hyprutils::Animation::CBaseAnimatedVariable> animation) {
        const auto window = g_window.lock();
        if (!validMapped(window))
            return;

        auto& position = window->positionAnimation();
        auto& size     = window->sizeAnimation();
        if (!position || !size || position->isBeingAnimated() || size->isBeingAnimated())
            return;

        const auto* scaleAnimation = static_cast<CAnimatedVariable<float>*>(animation.get());
        if (!scaleAnimation)
            return;

        const auto goalPosition = position->goal();
        const auto goalSize     = size->goal();
        const auto scale        = std::clamp(scaleAnimation->value(), MINIMUM_SCALE, MAXIMUM_SCALE);
        const auto scaledSize   = goalSize * scale;

        size->value()     = scaledSize;
        position->value() = goalPosition + goalSize / 2.F - scaledSize / 2.F;

        const auto monitor = window->m_monitor.lock();
        if (g_pHyprRenderer && monitor)
            g_pHyprRenderer->damageMonitor(monitor);
    }

    void animateFocus(PHLWINDOW window) {
        if (!validMapped(window) || window->isHidden()) {
            stopAnimation();
            return;
        }

        // Cross-monitor cursor warps can re-emit focus for the same window;
        // preserve its in-flight feedback instead of cancelling it early.
        const auto animatedWindow = g_window.lock();
        if (animatedWindow && animatedWindow == window)
            return;

        stopAnimation();

        const auto now = std::chrono::steady_clock::now();
        const auto isRapidFocus = g_lastFocusTrigger != std::chrono::steady_clock::time_point{} &&
            now - g_lastFocusTrigger < RAPID_FOCUS_INTERVAL;
        g_lastFocusTrigger = now;
        if (isRapidFocus)
            return;

        auto& position = window->positionAnimation();
        auto& size     = window->sizeAnimation();
        if (!position || !size || position->isBeingAnimated() || size->isBeingAnimated())
            return;

        const auto config = Config::animationTree()->getAnimationPropertyConfig(FOCUS_ANIMATION_LEAF);
        if (!config)
            return;

        g_window = window;
        // Expanded focus geometry is outside Hyprland's layout bounds. Damage
        // the monitor in updateScale instead of deriving window rectangles.
        Animation::mgr()->createAnimation(1.F, g_scale, config, AVARDAMAGE_NONE);
        g_scale->setUpdateCallback(updateScale);

        if (!g_scale->enabled()) {
            stopAnimation();
            return;
        }

        const auto startScale = startScaleFromStyle(g_scale->getStyle());
        if (startScale > 1.F) {
            *g_scale = startScale;
            g_scale->setCallbackOnEnd([](WP<Hyprutils::Animation::CBaseAnimatedVariable> animation) {
                auto* scaleAnimation = static_cast<CAnimatedVariable<float>*>(animation.get());
                if (scaleAnimation)
                    *scaleAnimation = 1.F;
            });
            return;
        }

        if (startScale >= 1.F) {
            stopAnimation();
            return;
        }

        g_scale->setValue(startScale);
    }

    int prepareAnimationLeafLua(lua_State* state) {
        if (!prepareAnimationLeaf())
            return luaL_error(state, "focus-animation: windows animation parent is unavailable");

        return 0;
    }

    void cleanupPluginState() {
        g_focusListener.reset();
        g_destroyListener.reset();
        stopAnimation();
        g_lastFocusTrigger = {};
        disableAnimationLeaf();
    }

    class CPluginInitializationGuard final {
      public:
        ~CPluginInitializationGuard() {
            if (m_active)
                cleanupPluginState();
        }

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
        throw std::runtime_error("focus-animation: unsupported Hyprland commit");

    CPluginInitializationGuard cleanup;

    if (!prepareAnimationLeaf())
        throw std::runtime_error("focus-animation: failed to register windowsFocus animation leaf");

    if (!HyprlandAPI::addLuaFunction(handle, "focus_animation", "prepare", prepareAnimationLeafLua))
        throw std::runtime_error("focus-animation: failed to register Lua function");

    g_focusListener = Event::bus()->m_events.window.active.listen([](PHLWINDOW window, Desktop::eFocusReason) { animateFocus(window); });
    g_destroyListener = Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF window) {
        const auto current = g_window.lock();
        const auto closing = window.lock();
        if (!current || (closing && current == closing))
            stopAnimation();
    });

    cleanup.release();
    return {
        "focus-animation",
        "Animate focused windows through a native Hyprland animation leaf",
        "local",
        "0.1.8",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    cleanupPluginState();
}
