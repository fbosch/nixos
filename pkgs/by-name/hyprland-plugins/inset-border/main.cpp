#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/GradientValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/pass/BorderPassElement.hpp>

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace {

    constexpr auto            EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr int             DEFAULT_THICKNESS         = 1;
    constexpr int             MAXIMUM_THICKNESS         = 4;
    constexpr int             DEFAULT_INSET             = 0;
    constexpr int             MAXIMUM_INSET             = 8;
    constexpr int             DAMAGE_BAND               = MAXIMUM_INSET + MAXIMUM_THICKNESS + 2;
    constexpr uint64_t        DEFAULT_ACTIVE_COLOR      = 0x73FFFFFF;
    constexpr uint64_t        DEFAULT_INACTIVE_COLOR    = 0x1AFFFFFF;

    HANDLE                             g_handle = nullptr;
    SP<Config::Values::CBoolValue>     g_enabled;
    SP<Config::Values::CIntValue>      g_thickness;
    SP<Config::Values::CIntValue>      g_inset;
    SP<Config::Values::CGradientValue> g_activeColor;
    SP<Config::Values::CGradientValue> g_inactiveColor;
    CHyprSignalListener                g_windowOpenListener;

    int thickness() {
        return std::clamp(static_cast<int>(g_thickness->value()), 1, MAXIMUM_THICKNESS);
    }

    int inset() {
        return std::clamp(static_cast<int>(g_inset->value()), 0, MAXIMUM_INSET);
    }

    const Config::CGradientValueData& colorForWindow(PHLWINDOW window) {
        return window == Desktop::focusState()->window() ? g_activeColor->value() : g_inactiveColor->value();
    }

    class CInsetBorderDecoration final : public IHyprWindowDecoration {
      public:
        explicit CInsetBorderDecoration(PHLWINDOW window) : IHyprWindowDecoration(window), m_window(window) {
            m_lastWindowPos  = window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            m_lastWindowSize = window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
        }

        ~CInsetBorderDecoration() override {
            damageEntire();
        }

        SDecorationPositioningInfo getPositioningInfo() override {
            SDecorationPositioningInfo info;
            info.policy = DECORATION_POSITION_ABSOLUTE;
            info.edges  = DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT | DECORATION_EDGE_RIGHT | DECORATION_EDGE_TOP;
            return info;
        }

        void onPositioningReply(const SDecorationPositioningReply&) override {
            updateWindow(m_window.lock());
        }

        void draw(PHLMONITOR monitor, float const& alpha) override {
            if (!monitor || !visible())
                return;

            const auto window = m_window.lock();
            if (!window)
                return;

            const auto workspace = window->m_workspace;
            const auto workspaceOffset = workspace && !(window->m_state & Desktop::View::WINDOW_STATE_PINNED) ? workspace->m_renderOffset->value() : Vector2D{};
            const auto borderThickness = thickness();
            const auto borderInset     = inset();

            CBox windowBox = {m_lastWindowPos.x, m_lastWindowPos.y, m_lastWindowSize.x, m_lastWindowSize.y};
            windowBox.translate(-monitor->m_position + workspaceOffset + window->presentation().floatingOffset());
            windowBox.expand(-(borderInset + borderThickness));
            windowBox.scale(monitor->m_scale).round();

            if (windowBox.width < 1 || windowBox.height < 1)
                return;

            const auto roundingPower = static_cast<double>(window->presentation().roundingPower());
            const auto innerRounding = std::max(0.0, static_cast<double>(window->presentation().rounding()) - borderInset - borderThickness);
            const auto correctionOffset =
                borderThickness * (std::sqrt(2.0) - 1.0) * std::max(2.0 - roundingPower, 0.0);
            const auto outerRounding = std::max(0.0, innerRounding + borderThickness - correctionOffset);

            CBorderPassElement::SBorderData data;
            data.box           = windowBox;
            data.grad1         = colorForWindow(window);
            data.round         = static_cast<int>(innerRounding * monitor->m_scale);
            data.outerRound    = static_cast<int>(outerRounding * monitor->m_scale);
            data.roundingPower = static_cast<float>(roundingPower);
            data.a             = alpha;
            data.borderSize    = borderThickness;
            data.window        = m_window;

            g_pHyprRenderer->addPassElement(makeUnique<CBorderPassElement>(data));
        }

        eDecorationType getDecorationType() override {
            return DECORATION_CUSTOM;
        }

        void updateWindow(PHLWINDOW window) override {
            if (!window)
                return;

            damageEntire();
            m_lastWindowPos  = window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            m_lastWindowSize = window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            damageEntire();
        }

        void damageEntire() override {
            const auto window = m_window.lock();
            if (!validMapped(window))
                return;

            const auto workspace = window->m_workspace;
            const auto workspaceOffset = workspace && !(window->m_state & Desktop::View::WINDOW_STATE_PINNED) ? workspace->m_renderOffset->value() : Vector2D{};

            CBox windowBox = {m_lastWindowPos.x, m_lastWindowPos.y, m_lastWindowSize.x, m_lastWindowSize.y};
            windowBox.translate(workspaceOffset + window->presentation().floatingOffset());

            CRegion damage{windowBox};
            const auto inner = windowBox.copy().expand(-DAMAGE_BAND);
            if (inner.width > 0 && inner.height > 0)
                damage.subtract(inner);

            g_pHyprRenderer->damageRegion(damage);
        }

        eDecorationLayer getDecorationLayer() override {
            return DECORATION_LAYER_OVER;
        }

        uint64_t getDecorationFlags() override {
            return DECORATION_NON_SOLID;
        }

        std::string getDisplayName() override {
            return "Inset Border";
        }

        void updateState() override {
            damageEntire();
        }

        void onWindowMap() override {
            damageEntire();
        }

        void onWindowFocus() override {
            damageEntire();
        }

      private:
        bool visible() const {
            if (!g_enabled || !g_enabled->value())
                return false;

            const auto window = m_window.lock();
            if (!validMapped(window))
                return false;

            const auto traits = window->backend().traits();
            if (traits.overrideRedirect || traits.suggestsNoBorder || !window->m_ruleApplicator->decorate().valueOrDefault())
                return false;

            if (window->presentation().borderSize() <= 0)
                return false;

            return !window->m_workspace || Fullscreen::controller()->getFullscreenModes(window).internal != Fullscreen::FSMODE_FULLSCREEN;
        }

        PHLWINDOWREF m_window;
        Vector2D     m_lastWindowPos;
        Vector2D     m_lastWindowSize;
    };

    void attachDecoration(PHLWINDOW window) {
        if (!g_handle || !validMapped(window))
            return;

        if (std::ranges::any_of(window->presentation().decorations(), [](const auto& decoration) {
                return decoration && decoration->getDisplayName() == "Inset Border";
            }))
            return;

        HyprlandAPI::addWindowDecoration(g_handle, window, makeShared<CInsetBorderDecoration>(window));
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("inset-border: unsupported Hyprland commit");

    g_handle = handle;

    g_enabled = makeShared<Config::Values::CBoolValue>("plugin:inset_border:enabled", "Draw the inset window keyline", true);
    g_thickness = makeShared<Config::Values::CIntValue>("plugin:inset_border:thickness", "Inset keyline thickness in logical pixels", DEFAULT_THICKNESS,
                                                        Config::Values::SIntValueOptions{.min = 1, .max = MAXIMUM_THICKNESS});
    g_inset = makeShared<Config::Values::CIntValue>("plugin:inset_border:inset", "Distance from the client edge in logical pixels", DEFAULT_INSET,
                                                    Config::Values::SIntValueOptions{.min = 0, .max = MAXIMUM_INSET});
    g_activeColor = makeShared<Config::Values::CGradientValue>("plugin:inset_border:active_color", "Inset keyline color for the focused window",
                                                               CHyprColor{DEFAULT_ACTIVE_COLOR});
    g_inactiveColor = makeShared<Config::Values::CGradientValue>("plugin:inset_border:inactive_color", "Inset keyline color for unfocused windows",
                                                                 CHyprColor{DEFAULT_INACTIVE_COLOR});

    if (!HyprlandAPI::addConfigValueV2(handle, g_enabled) || !HyprlandAPI::addConfigValueV2(handle, g_thickness) || !HyprlandAPI::addConfigValueV2(handle, g_inset) ||
        !HyprlandAPI::addConfigValueV2(handle, g_activeColor) || !HyprlandAPI::addConfigValueV2(handle, g_inactiveColor))
        throw std::runtime_error("inset-border: failed to register configuration");

    g_windowOpenListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW window) { attachDecoration(window); });

    for (const auto& window : Desktop::windowState()->windows())
        attachDecoration(window);

    HyprlandAPI::reloadConfig();

    return {
        "inset-border",
        "Draw a focus-aware keyline inside Hyprland window content",
        "local",
        "0.1.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_windowOpenListener.reset();
    g_handle = nullptr;
}
