#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/GradientValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/pass/BorderPassElement.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <expected>
#include <numbers>
#include <optional>
#include <ranges>
#include <stdexcept>
#include <string_view>
#include <utility>
#include <vector>

using namespace Render;
using namespace Render::GL;

namespace {

    constexpr auto     EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr int      DEFAULT_THICKNESS         = 1;
    constexpr int      MAXIMUM_THICKNESS         = 4;
    constexpr int      DEFAULT_INSET             = 0;
    constexpr int      MAXIMUM_INSET             = 8;
    constexpr uint64_t DEFAULT_ACTIVE_COLOR      = 0x73FFFFFF;
    constexpr uint64_t DEFAULT_INACTIVE_COLOR    = 0x1AFFFFFF;
    constexpr size_t   MAXIMUM_GRADIENT_COLORS   = 10;

    struct SBlendMode {
        std::string_view name;
        GLenum          equation;
    };

    constexpr SBlendMode DEFAULT_BLEND_MODE{"normal", GL_FUNC_ADD};
    constexpr std::array BLEND_MODES{
        DEFAULT_BLEND_MODE,
        SBlendMode{"multiply", GL_MULTIPLY_KHR},
        SBlendMode{"screen", GL_SCREEN_KHR},
        SBlendMode{"overlay", GL_OVERLAY_KHR},
        SBlendMode{"darken", GL_DARKEN_KHR},
        SBlendMode{"lighten", GL_LIGHTEN_KHR},
        SBlendMode{"color-dodge", GL_COLORDODGE_KHR},
        SBlendMode{"color-burn", GL_COLORBURN_KHR},
        SBlendMode{"hard-light", GL_HARDLIGHT_KHR},
        SBlendMode{"soft-light", GL_SOFTLIGHT_KHR},
        SBlendMode{"difference", GL_DIFFERENCE_KHR},
        SBlendMode{"exclusion", GL_EXCLUSION_KHR},
        SBlendMode{"hsl-hue", GL_HSL_HUE_KHR},
        SBlendMode{"hsl-saturation", GL_HSL_SATURATION_KHR},
        SBlendMode{"hsl-color", GL_HSL_COLOR_KHR},
        SBlendMode{"hsl-luminosity", GL_HSL_LUMINOSITY_KHR},
    };

    constexpr std::string_view VERTEX_SHADER = R"GLSL(#version 300 es

uniform mat3 proj;

in vec2 pos;
in vec2 texcoord;

out vec2 v_texcoord;

void main() {
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
    v_texcoord = texcoord;
}
)GLSL";

    constexpr std::string_view FRAGMENT_SHADER = R"GLSL(#version 300 es
#extension GL_KHR_blend_equation_advanced : require

precision highp float;

layout(blend_support_all_equations) out;

in vec2 v_texcoord;

uniform vec2 topLeft;
uniform vec2 fullSize;
uniform vec2 fullSizeUntransformed;
uniform float radius;
uniform float radiusOuter;
uniform float roundingPower;
uniform float thick;
uniform float alpha;
uniform int gradientLength;
uniform vec4 gradient[10];
uniform float angle;

layout(location = 0) out vec4 fragColor;

const float SMOOTHING_CONSTANT = 3.14159265358979323846 / 5.34665792551;

vec4 okLabAToSrgb(vec4 lab) {
    float l_ = lab.x + lab.y * 0.3963377774 + lab.z * 0.2158037573;
    float m_ = lab.x - lab.y * 0.1055613458 - lab.z * 0.0638541728;
    float s_ = lab.x - lab.y * 0.0894841775 - lab.z * 1.2914855480;

    float l = l_ * l_ * l_;
    float m = m_ * m_ * m_;
    float s = s_ * s_ * s_;
    vec3 linear = vec3(
        l * 4.0767416621 - m * 3.3077115913 + s * 0.2309699292,
        -l * 1.2684380046 + m * 2.6097574011 - s * 0.3413193965,
        -l * 0.0041960863 - m * 0.7034186147 + s * 1.7076147010
    );
    return vec4(pow(max(linear, vec3(0.0)), vec3(1.0 / 2.2)), lab.a);
}

vec4 gradientColor(vec2 normalizedCoord) {
    if (gradientLength <= 0)
        return vec4(0.0);
    if (gradientLength == 1)
        return okLabAToSrgb(gradient[0]);

    float finalAngle;
    if (angle > 4.71) {
        normalizedCoord.y = 1.0 - normalizedCoord.y;
        finalAngle = 6.28 - angle;
    } else if (angle > 3.14) {
        normalizedCoord = vec2(1.0) - normalizedCoord;
        finalAngle = angle - 3.14;
    } else if (angle > 1.57) {
        normalizedCoord.x = 1.0 - normalizedCoord.x;
        finalAngle = 3.14 - angle;
    } else {
        finalAngle = angle;
    }

    float sine = sin(finalAngle);
    float progress = (normalizedCoord.y * sine + normalizedCoord.x * (1.0 - sine)) * float(gradientLength - 1);
    if (progress >= float(gradientLength - 1))
        return okLabAToSrgb(gradient[gradientLength - 1]);

    int lower = int(floor(progress));
    int upper = lower + 1;
    return okLabAToSrgb(mix(gradient[lower], gradient[upper], progress - float(lower)));
}

void main() {
    vec2 pixel = vec2(gl_FragCoord);
    vec2 outerPixel = pixel;
    vec2 originalPixel = v_texcoord * fullSizeUntransformed;
    float coverage = 1.0;
    bool rounded = false;

    pixel -= topLeft + fullSize * 0.5;
    pixel *= vec2(lessThan(pixel, vec2(0.0))) * -2.0 + 1.0;
    outerPixel = pixel;
    pixel -= fullSize * 0.5 - radius;
    outerPixel -= fullSize * 0.5 - radiusOuter;
    pixel += vec2(1.0) / fullSize;
    outerPixel += vec2(1.0) / fullSize;

    if (min(pixel.x, pixel.y) > 0.0 && radius > 0.0) {
        float innerDistance = pow(pow(pixel.x, roundingPower) + pow(pixel.y, roundingPower), 1.0 / roundingPower);
        float outerDistance = pow(pow(outerPixel.x, roundingPower) + pow(outerPixel.y, roundingPower), 1.0 / roundingPower);
        float halfThickness = thick * 0.5;

        if (innerDistance < radius - halfThickness) {
            coverage *= smoothstep(0.0, 1.0, (innerDistance - radius + thick + SMOOTHING_CONSTANT) / (SMOOTHING_CONSTANT * 2.0));
            rounded = true;
        } else if (min(outerPixel.x, outerPixel.y) > 0.0) {
            coverage *= 1.0 - smoothstep(0.0, 1.0, (outerDistance - radiusOuter + SMOOTHING_CONSTANT) / (SMOOTHING_CONSTANT * 2.0));
            rounded = true;
        } else if (outerDistance < radiusOuter - halfThickness) {
            rounded = true;
        }
    }

    if (!rounded) {
        float distanceTop = originalPixel.y;
        float distanceBottom = fullSizeUntransformed.y - originalPixel.y;
        float distanceLeft = originalPixel.x;
        float distanceRight = fullSizeUntransformed.x - originalPixel.x;
        if (min(min(distanceTop, distanceBottom), min(distanceLeft, distanceRight)) > thick)
            discard;
    }

    coverage *= alpha;
    if (coverage <= 0.0)
        discard;

    vec4 color = gradientColor(v_texcoord);
    color.a *= coverage;
    color.rgb *= color.a;
    fragColor = color;
}
)GLSL";

    HANDLE                             g_handle = nullptr;
    SP<Config::Values::CBoolValue>     g_enabled;
    SP<Config::Values::CIntValue>      g_thickness;
    SP<Config::Values::CIntValue>      g_inset;
    SP<Config::Values::CGradientValue> g_activeColor;
    SP<Config::Values::CGradientValue> g_inactiveColor;
    SP<Config::Values::CStringValue>   g_blendMode;
    SP<CShader>                        g_advancedBlendShader;
    CHyprSignalListener                g_windowOpenListener;
    bool                               g_capabilitiesChecked    = false;
    bool                               g_advancedBlendSupported = false;
    bool                               g_gradientLimitWarned    = false;

    std::optional<GLenum> blendEquationFor(std::string_view name) {
        const auto mode = std::ranges::find(BLEND_MODES, name, &SBlendMode::name);
        if (mode == BLEND_MODES.end())
            return std::nullopt;
        return mode->equation;
    }

    std::expected<void, std::string> validateBlendMode(const Config::STRING& value) {
        if (blendEquationFor(value).has_value())
            return {};
        return std::unexpected(
            "expected one of: normal, multiply, screen, overlay, darken, lighten, color-dodge, color-burn, hard-light, soft-light, difference, exclusion, hsl-hue, "
            "hsl-saturation, hsl-color, hsl-luminosity");
    }

    GLenum blendEquation() {
        return blendEquationFor(g_blendMode->value()).value_or(DEFAULT_BLEND_MODE.equation);
    }

    constexpr bool sourceOverEquivalentForSolidBlack(GLenum equation) {
        return equation == GL_MULTIPLY_KHR || equation == GL_DARKEN_KHR || equation == GL_HARDLIGHT_KHR;
    }

    bool isSolidBlack(const Config::CGradientValueData& color) {
        if (color.m_colors.size() != 1)
            return false;

        const auto& solid = color.m_colors.front();
        return solid.r == 0.0 && solid.g == 0.0 && solid.b == 0.0;
    }

    float normalizedGradientAngle(float angle) {
        if (!std::isfinite(angle))
            return 0.F;

        constexpr auto FULL_ROTATION = 2.F * std::numbers::pi_v<float>;
        angle = std::fmod(angle, FULL_ROTATION);
        return angle < 0.F ? angle + FULL_ROTATION : angle;
    }

    size_t gradientColorCount(const Config::CGradientValueData& color) {
        return std::min(color.m_colorsOkLabA.size() / 4, MAXIMUM_GRADIENT_COLORS);
    }

    void warnAboutTruncatedGradient(const Config::CGradientValueData& color) {
        if (g_gradientLimitWarned || color.m_colors.size() <= MAXIMUM_GRADIENT_COLORS)
            return;

        g_gradientLimitWarned = true;
        HyprlandAPI::addNotification(g_handle, "inset-border: gradients are limited to 10 colors in advanced blend modes", CHyprColor{1.F, 0.7F, 0.2F, 1.F}, 5000.F);
    }

    bool hasExtension(std::string_view requested) {
        GLint count = 0;
        glGetIntegerv(GL_NUM_EXTENSIONS, &count);
        for (GLint index = 0; index < count; ++index) {
            const auto* extension = rc<const char*>(glGetStringi(GL_EXTENSIONS, index));
            if (extension && requested == extension)
                return true;
        }
        return false;
    }

    bool ensureAdvancedBlendShader() {
        if (g_capabilitiesChecked)
            return g_advancedBlendSupported;

        g_capabilitiesChecked = true;
        if (!g_pHyprOpenGL || !hasExtension("GL_KHR_blend_equation_advanced") || !hasExtension("GL_KHR_blend_equation_advanced_coherent") ||
            glIsEnabled(GL_BLEND_ADVANCED_COHERENT_KHR) != GL_TRUE) {
            HyprlandAPI::addNotification(g_handle, "inset-border: advanced blending unavailable; using normal blending", CHyprColor{1.F, 0.7F, 0.2F, 1.F}, 5000.F);
            return false;
        }

        g_advancedBlendShader = makeShared<CShader>();
        g_advancedBlendSupported = g_advancedBlendShader->createProgram(std::string(VERTEX_SHADER), std::string(FRAGMENT_SHADER), true, true);
        if (!g_advancedBlendSupported) {
            g_advancedBlendShader.reset();
            HyprlandAPI::addNotification(g_handle, "inset-border: advanced blend shader failed; using normal blending", CHyprColor{1.F, 0.3F, 0.3F, 1.F}, 5000.F);
        }

        return g_advancedBlendSupported;
    }

    bool canUseAdvancedBlend() {
        if (!ensureAdvancedBlendShader())
            return false;

        const auto& renderData = g_pHyprRenderer->m_renderData;
        if (!renderData.currentFB || !renderData.pMonitor || renderData.renderingTransformedSource)
            return false;

        const auto imageDescription = renderData.currentFB->imageDescription();
        if (!imageDescription)
            return false;

        const auto& description = imageDescription->value();
        if ((description.transferFunction != NColorManagement::CM_TRANSFER_FUNCTION_GAMMA22 &&
             description.transferFunction != NColorManagement::CM_TRANSFER_FUNCTION_SRGB) ||
            description.getPrimaries() != NColorManagement::getPrimaries(NColorManagement::CM_PRIMARIES_SRGB))
            return false;

        return !(renderData.pMonitor->needsUnmodifiedCopy() && renderData.currentFB->getMirrorTexture());
    }

    void renderFallback(const CBorderPassElement::SBorderData& data) {
        const auto& color = data.grad1;
        warnAboutTruncatedGradient(color);
        const auto colorCount = std::min(color.m_colors.size(), MAXIMUM_GRADIENT_COLORS);
        std::vector<CHyprColor> colors{color.m_colors.begin(), color.m_colors.begin() + colorCount};
        const Config::CGradientValueData boundedColor{std::move(colors), normalizedGradientAngle(color.m_angle)};
        g_pHyprOpenGL->renderBorder(data.box, boundedColor,
                                    {.round         = data.round,
                                     .roundingPower = data.roundingPower,
                                     .borderSize    = data.borderSize,
                                     .a             = data.a,
                                     .outerRound    = data.outerRound});
    }

    void renderAdvancedBlend(const CBorderPassElement::SBorderData& data) {
        auto& renderData = g_pHyprRenderer->m_renderData;
        if (renderData.damage.empty() || data.borderSize < 1)
            return;

        CBox innerBox = data.box;
        renderData.renderModif.applyToBox(innerBox);

        int scaledBorderSize = std::round(data.borderSize * renderData.pMonitor->m_scale);
        scaledBorderSize = std::round(scaledBorderSize * renderData.renderModif.combinedScale());

        CBox box = innerBox;
        box.expand(scaledBorderSize);
        const auto rounding = data.round + (data.round == 0 ? 0 : scaledBorderSize);
        const auto matrix = g_pHyprRenderer->projectBoxToTarget(box);

        const auto previousBlend = g_pHyprOpenGL->blendEnabled();
        g_pHyprOpenGL->blend(true);
        const Hyprutils::Utils::CScopeGuard restoreGlState{[previousBlend] {
            glBlendEquation(GL_FUNC_ADD);
            glBindVertexArray(0);
            g_pHyprOpenGL->blend(previousBlend);
        }};

        const auto shader = g_pHyprOpenGL->useShader(g_advancedBlendShader);
        shader->setUniformMatrix3fv(SHADER_PROJ, 1, GL_TRUE, matrix.getMatrix());
        shader->setUniformFloat2(SHADER_TOP_LEFT, static_cast<float>(box.x), static_cast<float>(box.y));
        shader->setUniformFloat2(SHADER_FULL_SIZE, static_cast<float>(box.width), static_cast<float>(box.height));
        shader->setUniformFloat2(SHADER_FULL_SIZE_UNTRANSFORMED, static_cast<float>(box.width), static_cast<float>(box.height));
        shader->setUniformFloat(SHADER_RADIUS, rounding);
        shader->setUniformFloat(SHADER_RADIUS_OUTER, data.outerRound == -1 ? rounding : data.outerRound);
        shader->setUniformFloat(SHADER_ROUNDING_POWER, data.roundingPower);
        shader->setUniformFloat(SHADER_THICK, scaledBorderSize);
        shader->setUniformFloat(SHADER_ALPHA, data.a);

        const auto& color = data.grad1;
        warnAboutTruncatedGradient(color);
        const auto colorCount = gradientColorCount(color);
        shader->setUniform4fv(SHADER_GRADIENT, static_cast<int>(colorCount), color.m_colorsOkLabA);
        shader->setUniformInt(SHADER_GRADIENT_LENGTH, static_cast<int>(colorCount));
        shader->setUniformFloat(SHADER_ANGLE, normalizedGradientAngle(color.m_angle));

        CRegion borderRegion = renderData.damage.copy().intersect(box);
        borderRegion.subtract(innerBox.copy().expand(-scaledBorderSize - rounding));
        if (renderData.clipBox.width != 0 && renderData.clipBox.height != 0)
            borderRegion.intersect(renderData.clipBox);

        glBindVertexArray(shader->getUniformLocation(SHADER_SHADER_VAO));
        const auto equation = blendEquation();
        glBlendEquation(isSolidBlack(color) && sourceOverEquivalentForSolidBlack(equation) ? GL_FUNC_ADD : equation);
        borderRegion.forEachRect([](const auto& rect) {
            g_pHyprOpenGL->scissor(&rect, g_pHyprRenderer->m_renderData.transformDamage);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        });
    }

    int thickness() {
        return std::clamp(static_cast<int>(g_thickness->value()), 1, MAXIMUM_THICKNESS);
    }

    int inset() {
        return std::clamp(static_cast<int>(g_inset->value()), 0, MAXIMUM_INSET);
    }

    const Config::CGradientValueData& colorForWindow(PHLWINDOW window) {
        return window == Desktop::focusState()->window() ? g_activeColor->value() : g_inactiveColor->value();
    }

    class CInsetBorderPassElement final : public IPassElement {
      public:
        explicit CInsetBorderPassElement(const CBorderPassElement::SBorderData& data) : m_data(data) {}

        std::vector<UP<IPassElement>> draw() override {
            const auto previousWindow = g_pHyprRenderer->m_renderData.currentWindow;
            const Hyprutils::Utils::CScopeGuard restoreWindow{[previousWindow] { g_pHyprRenderer->m_renderData.currentWindow = previousWindow; }};
            g_pHyprRenderer->m_renderData.currentWindow = m_data.window;

            if (canUseAdvancedBlend())
                renderAdvancedBlend(m_data);
            else
                renderFallback(m_data);
            return {};
        }

        bool needsLiveBlur() override {
            return false;
        }

        bool needsPrecomputeBlur() override {
            return false;
        }

        const char* passName() override {
            return "CInsetBorderPassElement";
        }

        ePassElementType type() override {
            return EK_CUSTOM;
        }

      private:
        CBorderPassElement::SBorderData m_data;
    };

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

            if (blendEquation() == GL_FUNC_ADD)
                g_pHyprRenderer->addPassElement(makeUnique<CBorderPassElement>(data));
            else
                g_pHyprRenderer->addPassElement(makeUnique<CInsetBorderPassElement>(data));
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

            g_pHyprRenderer->damageBox(windowBox);
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
    g_blendMode = makeShared<Config::Values::CStringValue>("plugin:inset_border:blend_mode", "Inset keyline blend equation", Config::STRING{DEFAULT_BLEND_MODE.name},
                                                            Config::Values::SStringValueOptions{.validator = validateBlendMode,
                                                                                               .refresh = Config::Supplementary::REFRESH_WINDOW_STATES});

    if (!HyprlandAPI::addConfigValueV2(handle, g_enabled) || !HyprlandAPI::addConfigValueV2(handle, g_thickness) || !HyprlandAPI::addConfigValueV2(handle, g_inset) ||
        !HyprlandAPI::addConfigValueV2(handle, g_activeColor) || !HyprlandAPI::addConfigValueV2(handle, g_inactiveColor) || !HyprlandAPI::addConfigValueV2(handle, g_blendMode))
        throw std::runtime_error("inset-border: failed to register configuration");

    g_windowOpenListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW window) { attachDecoration(window); });

    for (const auto& window : Desktop::windowState()->windows())
        attachDecoration(window);

    HyprlandAPI::reloadConfig();

    return {
        "inset-border",
        "Draw a focus-aware keyline inside Hyprland window content",
        "local",
        "0.2.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_windowOpenListener.reset();
    if (g_pHyprRenderer)
        g_pHyprRenderer->currentPass().clear();
    if (g_advancedBlendShader && g_pHyprOpenGL)
        g_pHyprOpenGL->makeEGLCurrent();
    g_advancedBlendShader.reset();
    g_handle = nullptr;
}
