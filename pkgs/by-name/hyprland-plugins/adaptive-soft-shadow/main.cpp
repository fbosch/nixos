#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/GradientValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/config/values/types/Vec2Value.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/state/MonitorState.hpp>
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
#include <vector>

using namespace Render;
using namespace Render::GL;

namespace {

    constexpr auto  EXPECTED_HYPRLAND_COMMIT = GIT_COMMIT_HASH;
    constexpr int   DEFAULT_RANGE             = 20;
    constexpr int   DEFAULT_RENDER_POWER      = 3;
    constexpr float DEFAULT_STRENGTH          = 0.30F;
    constexpr int   MAXIMUM_RANGE             = 80;
    constexpr size_t MAXIMUM_GRADIENT_COLORS  = 10;

    struct SBlendMode {
        std::string_view name;
        GLenum          equation;
    };

    constexpr SBlendMode DEFAULT_BLEND_MODE{"soft-light", GL_SOFTLIGHT_KHR};
    constexpr std::array BLEND_MODES{
        SBlendMode{"multiply", GL_MULTIPLY_KHR},
        SBlendMode{"screen", GL_SCREEN_KHR},
        SBlendMode{"overlay", GL_OVERLAY_KHR},
        SBlendMode{"darken", GL_DARKEN_KHR},
        SBlendMode{"lighten", GL_LIGHTEN_KHR},
        SBlendMode{"color-dodge", GL_COLORDODGE_KHR},
        SBlendMode{"color-burn", GL_COLORBURN_KHR},
        SBlendMode{"hard-light", GL_HARDLIGHT_KHR},
        DEFAULT_BLEND_MODE,
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
uniform vec2 bottomRight;
uniform vec2 windowTopLeft;
uniform vec2 windowBottomRight;
uniform vec2 fullSize;
uniform float radius;
uniform float roundingPower;
uniform float range;
uniform float shadowPower;
uniform float thick;
uniform float alpha;
uniform int gradientLength;
uniform vec4 gradient[10];
uniform float angle;

layout(location = 0) out vec4 fragColor;

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
    vec4 color = mix(gradient[lower], gradient[upper], progress - float(lower));
    return okLabAToSrgb(color);
}

float distanceWithPower(vec2 delta, float power) {
    return pow(pow(abs(delta.x), power) + pow(abs(delta.y), power), 1.0 / power);
}

float cornerAlpha(float distanceToCorner, float cornerRadius) {
    float outerRadius = range + cornerRadius;
    if (distanceToCorner > outerRadius)
        return 0.0;
    if (distanceToCorner <= outerRadius - range)
        return 1.0;
    return pow((outerRadius - distanceToCorner) / range, shadowPower);
}

bool pointInRoundedRect(vec2 point, vec2 rectTopLeft, vec2 rectBottomRight, float cornerRadius) {
    if (point.x < rectTopLeft.x || point.x > rectBottomRight.x || point.y < rectTopLeft.y || point.y > rectBottomRight.y)
        return false;
    if (cornerRadius <= 0.0)
        return true;

    cornerRadius = min(cornerRadius, min((rectBottomRight.x - rectTopLeft.x) * 0.5, (rectBottomRight.y - rectTopLeft.y) * 0.5));
    vec2 innerTopLeft = rectTopLeft + vec2(cornerRadius);
    vec2 innerBottomRight = rectBottomRight - vec2(cornerRadius);
    if (point.x >= innerTopLeft.x && point.x <= innerBottomRight.x)
        return true;
    if (point.y >= innerTopLeft.y && point.y <= innerBottomRight.y)
        return true;

    vec2 delta;
    delta.x = point.x < innerTopLeft.x ? innerTopLeft.x - point.x : point.x - innerBottomRight.x;
    delta.y = point.y < innerTopLeft.y ? innerTopLeft.y - point.y : point.y - innerBottomRight.y;
    return distanceWithPower(delta, roundingPower) <= cornerRadius;
}

void main() {
    vec2 pixel = fullSize * v_texcoord;
    float mask = 1.0;
    bool corner = false;

    if (pixel.x < topLeft.x) {
        if (pixel.y < topLeft.y) {
            mask = cornerAlpha(distanceWithPower(pixel - topLeft, roundingPower), radius);
            corner = true;
        } else if (pixel.y > bottomRight.y) {
            mask = cornerAlpha(distanceWithPower(pixel - vec2(topLeft.x, bottomRight.y), roundingPower), radius);
            corner = true;
        }
    } else if (pixel.x > bottomRight.x) {
        if (pixel.y < topLeft.y) {
            mask = cornerAlpha(distanceWithPower(pixel - vec2(bottomRight.x, topLeft.y), roundingPower), radius);
            corner = true;
        } else if (pixel.y > bottomRight.y) {
            mask = cornerAlpha(distanceWithPower(pixel - bottomRight, roundingPower), radius);
            corner = true;
        }
    }

    if (!corner) {
        float edgeDistance = min(min(pixel.y, fullSize.y - pixel.y), min(pixel.x, fullSize.x - pixel.x));
        if (edgeDistance < range)
            mask = pow(edgeDistance / range, shadowPower);
    }

    if (pointInRoundedRect(pixel, windowTopLeft, windowBottomRight, thick))
        discard;

    float coverage = alpha * mask;
    if (coverage <= 0.0)
        discard;

    vec4 color = gradientColor(v_texcoord);
    color.a *= coverage;
    color.rgb *= color.a;
    fragColor = color;
}
)GLSL";

    HANDLE                          g_handle = nullptr;
    SP<Config::Values::CBoolValue>     g_enabled;
    SP<Config::Values::CIntValue>      g_range;
    SP<Config::Values::CIntValue>      g_renderPower;
    SP<Config::Values::CVec2Value>     g_offset;
    SP<Config::Values::CFloatValue>    g_strength;
    SP<Config::Values::CGradientValue> g_color;
    SP<Config::Values::CStringValue>   g_blendMode;
    SP<CShader>                        g_advancedBlendShader;
    CHyprSignalListener                g_windowOpenListener;
    bool                               g_capabilitiesChecked  = false;
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
            "expected one of: multiply, screen, overlay, darken, lighten, color-dodge, color-burn, hard-light, soft-light, difference, exclusion, hsl-hue, "
            "hsl-saturation, hsl-color, hsl-luminosity");
    }

    GLenum blendEquation() {
        return blendEquationFor(g_blendMode->value()).value_or(DEFAULT_BLEND_MODE.equation);
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
        HyprlandAPI::addNotification(g_handle, "adaptive-soft-shadow: gradients are limited to 10 colors", CHyprColor{1.F, 0.7F, 0.2F, 1.F}, 5000.F);
    }

    int shadowRange() {
        return std::clamp(static_cast<int>(g_range->value()), 1, MAXIMUM_RANGE);
    }

    int renderPower() {
        return std::clamp(static_cast<int>(g_renderPower->value()), 1, 4);
    }

    float strength() {
        return std::clamp(static_cast<float>(g_strength->value()), 0.F, 1.F);
    }

    Vector2D shadowOffset() {
        const auto offset = g_offset->value();
        return {offset.x, offset.y};
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
            HyprlandAPI::addNotification(g_handle, "adaptive-soft-shadow: advanced blending unavailable; using neutral shadows", CHyprColor{1.F, 0.7F, 0.2F, 1.F}, 5000.F);
            return false;
        }

        g_advancedBlendShader = makeShared<CShader>();
        g_advancedBlendSupported = g_advancedBlendShader->createProgram(std::string(VERTEX_SHADER), std::string(FRAGMENT_SHADER), true, true);
        if (!g_advancedBlendSupported) {
            g_advancedBlendShader.reset();
            HyprlandAPI::addNotification(g_handle, "adaptive-soft-shadow: shader failed; using neutral shadows", CHyprColor{1.F, 0.3F, 0.3F, 1.F}, 5000.F);
        }

        return g_advancedBlendSupported;
    }

    struct SAdaptiveShadowRenderData {
        bool  valid = false;
        CBox  fullBox;
        float rounding      = 0.F;
        float roundingPower = 2.F;
        int   range         = 0;
    };

    class CAdaptiveSoftShadowDecoration;

    class CAdaptiveSoftShadowPassElement final : public IPassElement {
      public:
        struct SData {
            WP<CAdaptiveSoftShadowDecoration> decoration;
            float                             alpha = 1.F;
        };

        explicit CAdaptiveSoftShadowPassElement(const SData& data) : m_data(data) {}

        std::vector<UP<IPassElement>> draw() override;

        bool needsLiveBlur() override {
            return false;
        }

        bool needsPrecomputeBlur() override {
            return false;
        }

        const char* passName() override {
            return "CAdaptiveSoftShadowPassElement";
        }

        ePassElementType type() override {
            return EK_CUSTOM;
        }

      private:
        SData m_data;
    };

    class CAdaptiveSoftShadowDecoration final : public IHyprWindowDecoration {
      public:
        explicit CAdaptiveSoftShadowDecoration(PHLWINDOW window) : IHyprWindowDecoration(window), m_window(window) {
            updateWindow(window);
        }

        ~CAdaptiveSoftShadowDecoration() override {
            damageEntire();
        }

        SDecorationPositioningInfo getPositioningInfo() override {
            SDecorationPositioningInfo info;
            info.policy         = DECORATION_POSITION_ABSOLUTE;
            info.desiredExtents = m_extents;
            info.edges          = DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT | DECORATION_EDGE_RIGHT | DECORATION_EDGE_TOP;
            m_reportedExtents   = m_extents;
            return info;
        }

        void onPositioningReply(const SDecorationPositioningReply&) override {
            updateWindow(m_window.lock());
        }

        void draw(PHLMONITOR, const float& alpha) override {
            const auto self = dynamicPointerCast<CAdaptiveSoftShadowDecoration>(IHyprWindowDecoration::self());
            if (!self)
                return;

            g_pHyprRenderer->addPassElement(makeUnique<CAdaptiveSoftShadowPassElement>(CAdaptiveSoftShadowPassElement::SData{.decoration = self, .alpha = alpha}));
        }

        eDecorationType getDecorationType() override {
            return DECORATION_CUSTOM;
        }

        void updateWindow(PHLWINDOW window) override {
            if (!window)
                return;

            m_lastWindowPos          = window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            m_lastWindowSize         = window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            m_lastWindowBoxWithDecos = g_pDecorationPositioner->getBoxWithIncludedDecos(window);

            const auto range  = shadowRange();
            const auto offset = shadowOffset();
            m_extents = {
                .topLeft     = {range + std::max(0.0, -offset.x) + 2, range + std::max(0.0, -offset.y) + 2},
                .bottomRight = {range + std::max(0.0, offset.x) + 2, range + std::max(0.0, offset.y) + 2},
            };
        }

        void damageEntire() override {
            if (!g_enabled || !g_enabled->value())
                return;

            const auto window = m_window.lock();
            if (!validMapped(window))
                return;

            const auto workspace = window->m_workspace;
            const auto workspaceOffset = workspace && !(window->m_state & Desktop::View::WINDOW_STATE_PINNED) ? workspace->m_renderOffset->value() : Vector2D{};
            CBox shadowBox = {
                m_lastWindowPos.x - m_extents.topLeft.x,
                m_lastWindowPos.y - m_extents.topLeft.y,
                m_lastWindowSize.x + m_extents.topLeft.x + m_extents.bottomRight.x,
                m_lastWindowSize.y + m_extents.topLeft.y + m_extents.bottomRight.y,
            };
            shadowBox.translate(workspaceOffset + window->presentation().floatingOffset());

            CRegion shadowRegion(shadowBox);
            for (const auto& monitor : State::monitorState()->monitors()) {
                if (!g_pHyprRenderer->shouldRenderWindow(window, monitor))
                    shadowRegion.subtract(CRegion({monitor->m_position, monitor->m_size}));
            }
            g_pHyprRenderer->damageRegion(shadowRegion);
        }

        eDecorationLayer getDecorationLayer() override {
            return DECORATION_LAYER_BOTTOM;
        }

        uint64_t getDecorationFlags() override {
            return DECORATION_NON_SOLID;
        }

        std::string getDisplayName() override {
            return "Adaptive Soft Shadow";
        }

        void updateState() override {
            damageEntire();
            updateWindow(m_window.lock());
            damageEntire();
        }

        void onWindowMap() override {
            updateState();
        }

        void onWindowFocus() override {
            damageEntire();
        }

        void render(PHLMONITOR monitor, float alpha) {
            const auto data = getRenderData(monitor);
            if (!data.valid)
                return;

            const auto window = m_window.lock();
            const auto previousWindow = g_pHyprRenderer->m_renderData.currentWindow;
            const Hyprutils::Utils::CScopeGuard restoreWindow{[previousWindow] { g_pHyprRenderer->m_renderData.currentWindow = previousWindow; }};
            g_pHyprRenderer->m_renderData.currentWindow = m_window;
            g_pHyprRenderer->disableScissor();

            if (canUseAdvancedBlend())
                renderAdvancedBlend(data, window, alpha);
            else
                renderFallback(data, alpha);

            if (m_extents != m_reportedExtents)
                g_pDecorationPositioner->repositionDeco(this);
        }

      private:
        bool canRender() const {
            if (!g_enabled || !g_enabled->value() || strength() <= 0.F)
                return false;

            const auto window = m_window.lock();
            if (!validMapped(window))
                return false;

            const auto traits = window->backend().traits();
            if (traits.overrideRedirect || traits.suggestsNoBorder)
                return false;
            if (!window->m_ruleApplicator->decorate().valueOrDefault())
                return false;
            return !window->m_ruleApplicator->noShadow().valueOrDefault();
        }

        bool canUseAdvancedBlend() {
            if (!ensureAdvancedBlendShader())
                return false;

            const auto& renderData = g_pHyprRenderer->m_renderData;
            if (!renderData.currentFB || !renderData.pMonitor)
                return false;

            return !(renderData.pMonitor->needsUnmodifiedCopy() && renderData.currentFB->getMirrorTexture());
        }

        SAdaptiveShadowRenderData getRenderData(PHLMONITOR monitor) {
            if (!monitor || !canRender())
                return {};

            const auto window = m_window.lock();
            const auto borderSize = window->presentation().borderSize();
            const auto roundingBase = window->presentation().rounding();
            const auto roundingPower = window->presentation().roundingPower();
            const auto correctionOffset = borderSize * (std::sqrt(2.0) - 1.0) * std::max(2.0 - roundingPower, 0.0);
            const auto rounding = roundingBase > 0 ? roundingBase + borderSize - correctionOffset : 0.0;
            const auto workspace = window->m_workspace;
            const auto workspaceOffset = workspace && !(window->m_state & Desktop::View::WINDOW_STATE_PINNED) ? workspace->m_renderOffset->value() : Vector2D{};
            const auto range = shadowRange();

            CBox fullBox = m_lastWindowBoxWithDecos;
            fullBox.translate(-monitor->m_position + workspaceOffset);
            fullBox.expand(range);
            fullBox.translate(shadowOffset());

            updateWindow(window);
            m_lastWindowPos += workspaceOffset;
            m_extents = {
                .topLeft = {
                    m_lastWindowPos.x - fullBox.x - monitor->m_position.x + 2,
                    m_lastWindowPos.y - fullBox.y - monitor->m_position.y + 2,
                },
                .bottomRight = {
                    fullBox.x + fullBox.width + monitor->m_position.x - m_lastWindowPos.x - m_lastWindowSize.x + 2,
                    fullBox.y + fullBox.height + monitor->m_position.y - m_lastWindowPos.y - m_lastWindowSize.y + 2,
                },
            };

            fullBox.translate(window->presentation().floatingOffset());
            if (fullBox.width < 1 || fullBox.height < 1)
                return {};

            fullBox.scale(monitor->m_scale).round();
            return {
                .valid         = true,
                .fullBox       = fullBox,
                .rounding      = static_cast<float>(rounding * monitor->m_scale),
                .roundingPower = static_cast<float>(roundingPower),
                .range         = static_cast<int>(range * monitor->m_scale),
            };
        }

        void renderFallback(const SAdaptiveShadowRenderData& data, float alpha) {
            const auto& color = g_color->value();
            warnAboutTruncatedGradient(color);
            if (color.m_colors.size() <= MAXIMUM_GRADIENT_COLORS && std::isfinite(color.m_angle)) {
                g_pHyprRenderer->drawShadow(data.fullBox, data.rounding, data.roundingPower, data.range, color, strength() * alpha);
                return;
            }

            const auto colorCount = std::min(color.m_colors.size(), MAXIMUM_GRADIENT_COLORS);
            std::vector<CHyprColor> colors{color.m_colors.begin(), color.m_colors.begin() + colorCount};
            const Config::CGradientValueData boundedColor{std::move(colors), normalizedGradientAngle(color.m_angle)};
            g_pHyprRenderer->drawShadow(data.fullBox, data.rounding, data.roundingPower, data.range, boundedColor, strength() * alpha);
        }

        void renderAdvancedBlend(const SAdaptiveShadowRenderData& data, PHLWINDOW window, float alpha) {
            CBox box = data.fullBox;
            g_pHyprRenderer->m_renderData.renderModif.applyToBox(box);

            const auto matrix = g_pHyprRenderer->projectBoxToTarget(box);
            g_pHyprOpenGL->blend(true);
            const auto shader = g_pHyprOpenGL->useShader(g_advancedBlendShader);
            shader->setUniformMatrix3fv(SHADER_PROJ, 1, GL_TRUE, matrix.getMatrix());
            shader->setUniformFloat2(SHADER_TOP_LEFT, data.range + data.rounding, data.range + data.rounding);
            shader->setUniformFloat2(SHADER_BOTTOM_RIGHT, box.width - data.range - data.rounding, box.height - data.range - data.rounding);
            shader->setUniformFloat2(SHADER_FULL_SIZE, box.width, box.height);
            shader->setUniformFloat(SHADER_RADIUS, data.rounding);
            shader->setUniformFloat(SHADER_ROUNDING_POWER, data.roundingPower);
            shader->setUniformFloat(SHADER_RANGE, data.range);
            shader->setUniformFloat(SHADER_SHADOW_POWER, renderPower());
            shader->setUniformFloat(SHADER_ALPHA, strength() * alpha);
            const auto& color = g_color->value();
            warnAboutTruncatedGradient(color);
            const auto colorCount = gradientColorCount(color);
            shader->setUniform4fv(SHADER_GRADIENT, static_cast<int>(colorCount), color.m_colorsOkLabA);
            shader->setUniformInt(SHADER_GRADIENT_LENGTH, static_cast<int>(colorCount));
            shader->setUniformFloat(SHADER_ANGLE, normalizedGradientAngle(color.m_angle));
            shader->setUniformFloat2(SHADER_WINDOW_TOP_LEFT, -1.F, -1.F);
            shader->setUniformFloat2(SHADER_WINDOW_BOTTOM_RIGHT, -1.F, -1.F);
            shader->setUniformFloat(SHADER_THICK, 0.F);

            CRegion drawRegion;
            if (g_pHyprRenderer->m_renderData.clipBox.width != 0 && g_pHyprRenderer->m_renderData.clipBox.height != 0) {
                drawRegion = g_pHyprRenderer->m_renderData.clipBox;
                drawRegion.intersect(g_pHyprRenderer->m_renderData.damage);
            } else
                drawRegion = g_pHyprRenderer->m_renderData.damage;

            if (window) {
                if (const auto logicalWindowBox = window->surfaceLogicalBox(); logicalWindowBox.has_value()) {
                    CBox scaledWindowBox = *logicalWindowBox;
                    const auto workspace = window->m_workspace;
                    if (workspace && !(window->m_state & Desktop::View::WINDOW_STATE_PINNED))
                        scaledWindowBox.translate(workspace->m_renderOffset->value());
                    scaledWindowBox.translate(window->presentation().floatingOffset() - g_pHyprRenderer->m_renderData.pMonitor->m_position);
                    scaledWindowBox.scale(g_pHyprRenderer->m_renderData.pMonitor->m_scale).round();
                    g_pHyprRenderer->m_renderData.renderModif.applyToBox(scaledWindowBox);

                    const auto cutoutTopLeft = scaledWindowBox.pos() - box.pos();
                    const auto cutoutBottomRight = cutoutTopLeft + scaledWindowBox.size();
                    auto cutoutRadius = std::max(0.F, static_cast<float>(window->presentation().rounding() * g_pHyprRenderer->m_renderData.pMonitor->m_scale));
                    cutoutRadius = std::round(cutoutRadius * g_pHyprRenderer->m_renderData.renderModif.combinedScale());

                    shader->setUniformFloat2(SHADER_WINDOW_TOP_LEFT, cutoutTopLeft.x, cutoutTopLeft.y);
                    shader->setUniformFloat2(SHADER_WINDOW_BOTTOM_RIGHT, cutoutBottomRight.x, cutoutBottomRight.y);
                    shader->setUniformFloat(SHADER_THICK, cutoutRadius);
                    drawRegion.subtract(scaledWindowBox.copy().expand(-static_cast<int>(std::round(cutoutRadius))));
                }
            }

            const Hyprutils::Utils::CScopeGuard restoreGlState{[] {
                glBlendEquation(GL_FUNC_ADD);
                glBindVertexArray(0);
            }};
            glBindVertexArray(shader->getUniformLocation(SHADER_SHADER_VAO));
            glBlendEquation(blendEquation());
            drawRegion.forEachRect([](const auto& rect) {
                g_pHyprOpenGL->scissor(&rect, g_pHyprRenderer->m_renderData.transformDamage);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            });
        }

        PHLWINDOWREF m_window;
        SBoxExtents  m_extents;
        SBoxExtents  m_reportedExtents;
        Vector2D     m_lastWindowPos;
        Vector2D     m_lastWindowSize;
        CBox         m_lastWindowBoxWithDecos;
    };

    std::vector<UP<IPassElement>> CAdaptiveSoftShadowPassElement::draw() {
        const auto decoration = m_data.decoration.lock();
        if (decoration)
            decoration->render(g_pHyprRenderer->m_renderData.pMonitor.lock(), m_data.alpha);
        return {};
    }

    void attachDecoration(PHLWINDOW window) {
        if (!g_handle || !validMapped(window))
            return;
        if (std::ranges::any_of(window->presentation().decorations(), [](const auto& decoration) {
                return decoration && decoration->getDisplayName() == "Adaptive Soft Shadow";
            }))
            return;

        HyprlandAPI::addWindowDecoration(g_handle, window, makeShared<CAdaptiveSoftShadowDecoration>(window));
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("adaptive-soft-shadow: unsupported Hyprland commit");

    g_handle = handle;
    g_enabled = makeShared<Config::Values::CBoolValue>("plugin:adaptive_soft_shadow:enabled", "Draw backdrop-adaptive window shadows", true);
    g_range = makeShared<Config::Values::CIntValue>("plugin:adaptive_soft_shadow:range", "Shadow extent in logical pixels", DEFAULT_RANGE,
                                                    Config::Values::SIntValueOptions{.min = 1, .max = MAXIMUM_RANGE});
    g_renderPower = makeShared<Config::Values::CIntValue>("plugin:adaptive_soft_shadow:render_power", "Shadow falloff exponent", DEFAULT_RENDER_POWER,
                                                          Config::Values::SIntValueOptions{.min = 1, .max = 4});
    g_offset = makeShared<Config::Values::CVec2Value>("plugin:adaptive_soft_shadow:offset", "Shadow offset in logical pixels", Config::VEC2{1.F, 1.F});
    g_strength = makeShared<Config::Values::CFloatValue>("plugin:adaptive_soft_shadow:strength", "Advanced blend shadow strength", DEFAULT_STRENGTH,
                                                         Config::Values::SFloatValueOptions{.min = 0.F, .max = 1.F});
    g_color = makeShared<Config::Values::CGradientValue>("plugin:adaptive_soft_shadow:color", "Shadow color or gradient", CHyprColor{0.F, 0.F, 0.F, 1.F});
    g_blendMode = makeShared<Config::Values::CStringValue>("plugin:adaptive_soft_shadow:blend_mode", "Advanced shadow blend equation",
                                                           Config::STRING{DEFAULT_BLEND_MODE.name}, Config::Values::SStringValueOptions{.validator = validateBlendMode});

    if (!HyprlandAPI::addConfigValueV2(handle, g_enabled) || !HyprlandAPI::addConfigValueV2(handle, g_range) || !HyprlandAPI::addConfigValueV2(handle, g_renderPower) ||
        !HyprlandAPI::addConfigValueV2(handle, g_offset) || !HyprlandAPI::addConfigValueV2(handle, g_strength) || !HyprlandAPI::addConfigValueV2(handle, g_color) ||
        !HyprlandAPI::addConfigValueV2(handle, g_blendMode))
        throw std::runtime_error("adaptive-soft-shadow: failed to register configuration");

    g_windowOpenListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW window) { attachDecoration(window); });
    for (const auto& window : Desktop::windowState()->windows())
        attachDecoration(window);

    return {
        "adaptive-soft-shadow",
        "Draw backdrop-adaptive soft-light window shadows",
        "local",
        "0.2.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_windowOpenListener.reset();
    // Transformed windows can retain plugin elements in nested passes that removeAllOfType cannot reach.
    if (g_pHyprRenderer)
        g_pHyprRenderer->currentPass().clear();
    if (g_advancedBlendShader && g_pHyprOpenGL)
        g_pHyprOpenGL->makeEGLCurrent();
    g_advancedBlendShader.reset();
    g_handle = nullptr;
}
