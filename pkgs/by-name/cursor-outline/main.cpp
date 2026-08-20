#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <utility>
#include <vector>

using namespace Render;
using namespace Render::GL;

namespace {

    constexpr auto                  EXPECTED_HYPRLAND_COMMIT       = "5751911091d2bbcd580597d489a1ec0b9dd542bd";
    constexpr int                   DEFAULT_OUTLINE_LOGICAL_PIXELS = 3;
    constexpr int                   MAXIMUM_OUTLINE_LOGICAL_PIXELS = 4;
    constexpr int                   MAXIMUM_OUTLINE_PIXELS         = 8;
    constexpr Config::INTEGER       DEFAULT_OUTLINE_COLOR          = 0xF56099C0;

    constexpr const char*           OUTLINE_FRAGMENT_SHADER = R"GLSL(
#version 300 es

precision highp float;

in vec2 v_texcoord;

uniform sampler2D tex;
uniform vec4 color;
uniform vec2 fullSize;
uniform float radius;

layout(location = 0) out vec4 fragColor;

const int maximumRadius = 8;

float sourceAlpha(vec2 uv) {
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0))))
        return 0.0;

    return texture(tex, uv).a;
}

void main() {
    vec2 paddedSize = fullSize + vec2(radius * 2.0);
    vec2 sourcePixel = v_texcoord * paddedSize - vec2(radius);
    vec2 centerUv = sourcePixel / fullSize;
    float center = sourceAlpha(centerUv);
    float dilated = 0.0;

    for (int y = -maximumRadius; y <= maximumRadius; ++y) {
        for (int x = -maximumRadius; x <= maximumRadius; ++x) {
            vec2 offset = vec2(float(x), float(y));
            if (dot(offset, offset) > radius * radius)
                continue;

            dilated = max(dilated, sourceAlpha(centerUv + offset / fullSize));
        }
    }

    float outline = dilated * (1.0 - center);
    if (outline <= 0.01)
        discard;

    float alpha = outline * color.a;
    fragColor = vec4(color.rgb * alpha, alpha);
}
)GLSL";

    SP<CShader>                     g_shader;
    SP<Config::Values::CIntValue>   g_outlineThickness;
    SP<Config::Values::CColorValue> g_outlineColor;
    bool                            g_shaderFailed   = false;
    bool                            g_outlineEnabled = false;
    CHyprSignalListener             g_renderStageListener;
    CHyprSignalListener             g_monitorAddedListener;
    CHyprSignalListener             g_configReloadedListener;
    std::vector<PHLMONITORREF>      g_lockedMonitors;

    int                             outlineLogicalPixels() {
        return std::clamp(static_cast<int>(g_outlineThickness->value()), 1, MAXIMUM_OUTLINE_LOGICAL_PIXELS);
    }

    CHyprColor outlineColor() {
        return CHyprColor{static_cast<uint64_t>(g_outlineColor->value())};
    }

    bool ensureShader() {
        if (g_shader)
            return true;

        if (g_shaderFailed || !g_pHyprOpenGL || !g_pHyprOpenGL->m_shadersInitialized || !g_pHyprOpenGL->m_shaders)
            return false;

        auto shader = makeShared<CShader>();
        if (!shader->createProgram(g_pHyprOpenGL->m_shaders->TEXVERTSRC, OUTLINE_FRAGMENT_SHADER, true, true)) {
            g_shaderFailed = true;
            return false;
        }

        g_shader = std::move(shader);
        return true;
    }

    class CCursorOutlinePassElement final : public IPassElement {
      public:
        CCursorOutlinePassElement(SP<ITexture> texture, CBox cursorBoxPixels, int radiusPixels, float monitorScale) :
            m_texture(std::move(texture)), m_cursorBoxPixels(cursorBoxPixels), m_radiusPixels(radiusPixels), m_monitorScale(monitorScale),
            m_drawBoxPixels(cursorBoxPixels.copy().expand(radiusPixels)) {}

        bool needsLiveBlur() override {
            return false;
        }

        bool needsPrecomputeBlur() override {
            return false;
        }

        const char* passName() override {
            return "CCursorOutlinePassElement";
        }

        ePassElementType type() override {
            return EK_CUSTOM;
        }

        std::optional<CBox> boundingBox() override {
            return m_drawBoxPixels.copy().scale(1.F / m_monitorScale).round();
        }

        CRegion opaqueRegion() override {
            return {};
        }

        std::vector<UP<IPassElement>> draw() override {
            if (!m_texture || m_texture->m_type != TEXTURE_RGBA || m_cursorBoxPixels.empty() || !ensureShader())
                return {};

            auto&   renderData = g_pHyprRenderer->m_renderData;
            CRegion outputRegion{m_drawBoxPixels};
            renderData.renderModif.applyToRegion(outputRegion);

            const CRegion damage = renderData.damage.copy().intersect(outputRegion);
            if (damage.empty())
                return {};

            CBox projectedBox = m_drawBoxPixels;
            renderData.renderModif.applyToBox(projectedBox);
            const auto matrix = g_pHyprRenderer->projectBoxToTarget(projectedBox, Math::invertTransform(m_texture->m_transform));

            g_pHyprOpenGL->setActiveTexture(GL_TEXTURE0);
            m_texture->bind();
            m_texture->setTexParameter(GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            m_texture->setTexParameter(GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            const auto filter = renderData.useNearestNeighbor ? GL_NEAREST : GL_LINEAR;
            m_texture->setTexParameter(GL_TEXTURE_MAG_FILTER, filter);
            m_texture->setTexParameter(GL_TEXTURE_MIN_FILTER, filter);
            g_pHyprOpenGL->blend(true);

            const auto shader = g_pHyprOpenGL->useShader(g_shader);
            shader->setUniformMatrix3fv(SHADER_PROJ, 1, GL_TRUE, matrix.getMatrix());
            shader->setUniformInt(SHADER_TEX, 0);
            shader->setUniformFloat2(SHADER_FULL_SIZE, m_cursorBoxPixels.width, m_cursorBoxPixels.height);
            shader->setUniformFloat(SHADER_RADIUS, m_radiusPixels);

            const auto color = g_pHyprRenderer->getConvertedColor(outlineColor());
            shader->setUniformFloat4(SHADER_COLOR, color.r, color.g, color.b, color.a);

            glBindVertexArray(static_cast<GLuint>(shader->getUniformLocation(SHADER_SHADER_VAO)));
            damage.forEachRect([](const auto& rect) {
                g_pHyprOpenGL->scissor(&rect, g_pHyprRenderer->m_renderData.transformDamage);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            });

            glBindVertexArray(0);
            g_pHyprOpenGL->bindArrayBuffer(0);
            g_pHyprOpenGL->scissor(nullptr);
            m_texture->unbind();
            g_pHyprOpenGL->setActiveTexture(GL_TEXTURE0);
            return {};
        }

      private:
        SP<ITexture> m_texture;
        CBox         m_cursorBoxPixels;
        int          m_radiusPixels;
        float        m_monitorScale;
        CBox         m_drawBoxPixels;
    };

    bool monitorAlreadyLocked(PHLMONITOR monitor) {
        return std::ranges::any_of(g_lockedMonitors, [monitor](const auto& weakMonitor) { return weakMonitor.lock() == monitor; });
    }

    void lockSoftwareCursor(PHLMONITOR monitor) {
        if (!monitor || monitorAlreadyLocked(monitor))
            return;

        Pointer::mgr()->lockSoftwareForMonitor(monitor);
        g_lockedMonitors.emplace_back(monitor);
    }

    void unlockSoftwareCursors() {
        for (const auto& weakMonitor : g_lockedMonitors) {
            if (const auto monitor = weakMonitor.lock())
                Pointer::mgr()->unlockSoftwareForMonitor(monitor);
        }
        g_lockedMonitors.clear();
    }

    void damageCurrentOutline() {
        if (!g_pHyprRenderer || !Pointer::mgr())
            return;

        g_pHyprRenderer->damageBox(Pointer::mgr()->getCursorBoxGlobal().expand(MAXIMUM_OUTLINE_LOGICAL_PIXELS));
    }

    void queueOutlineForMonitor(PHLMONITOR monitor) {
        if (!g_outlineEnabled || !monitor || monitor->isMirror() || !monitor->m_enabled || !monitor->m_dpmsStatus || !g_pHyprRenderer->shouldRenderCursor() ||
            !Pointer::mgr()->softwareLockedFor(monitor))
            return;

        auto texture = Pointer::mgr()->getCurrentCursorTexture();
        if (!texture || texture->m_type != TEXTURE_RGBA)
            return;

        CBox logicalBox = Pointer::mgr()->getCursorBoxGlobal().translate(-monitor->m_position);
        if (logicalBox.copy().intersection(CBox{{}, monitor->m_size}).empty())
            return;

        CBox pixelBox = logicalBox.copy().scale(monitor->m_scale);
        pixelBox.x    = std::round(pixelBox.x);
        pixelBox.y    = std::round(pixelBox.y);
        pixelBox.round();

        const int radiusPixels = std::clamp(static_cast<int>(std::ceil(outlineLogicalPixels() * monitor->m_scale)), 1, MAXIMUM_OUTLINE_PIXELS);
        g_pHyprRenderer->addPassElement(makeUnique<CCursorOutlinePassElement>(std::move(texture), pixelBox, radiusPixels, monitor->m_scale));
    }

    void setOutlineEnabled(bool enabled) {
        if (g_outlineEnabled == enabled)
            return;

        damageCurrentOutline();
        g_outlineEnabled = enabled;

        if (enabled) {
            for (const auto& monitor : State::monitorState()->monitors())
                lockSoftwareCursor(monitor);
        } else
            unlockSoftwareCursors();

        damageCurrentOutline();
    }

    int toggleOutline(lua_State*) {
        setOutlineEnabled(!g_outlineEnabled);
        return 0;
    }

    int enableOutline(lua_State*) {
        setOutlineEnabled(true);
        return 0;
    }

    int disableOutline(lua_State*) {
        setOutlineEnabled(false);
        return 0;
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != EXPECTED_HYPRLAND_COMMIT)
        throw std::runtime_error("cursor-outline: unsupported Hyprland commit");
    if (!g_pHyprRenderer || g_pHyprRenderer->type() != IHyprRenderer::RT_GL)
        throw std::runtime_error("cursor-outline: OpenGL renderer required");

    g_outlineThickness =
        makeShared<Config::Values::CIntValue>("plugin:cursor_outline:thickness", "Cursor silhouette outline thickness in logical pixels", DEFAULT_OUTLINE_LOGICAL_PIXELS,
                                              Config::Values::SIntValueOptions{
                                                  .min = 1,
                                                  .max = MAXIMUM_OUTLINE_LOGICAL_PIXELS,
                                              });
    g_outlineColor = makeShared<Config::Values::CColorValue>("plugin:cursor_outline:color", "Cursor silhouette outline color", DEFAULT_OUTLINE_COLOR);
    if (!HyprlandAPI::addConfigValueV2(handle, g_outlineThickness) || !HyprlandAPI::addConfigValueV2(handle, g_outlineColor))
        throw std::runtime_error("cursor-outline: failed to register style settings");

    if (!HyprlandAPI::addLuaFunction(handle, "cursor_outline", "toggle", toggleOutline))
        throw std::runtime_error("cursor-outline: failed to register toggle");
    if (!HyprlandAPI::addLuaFunction(handle, "cursor_outline", "on", enableOutline))
        throw std::runtime_error("cursor-outline: failed to register enable action");
    if (!HyprlandAPI::addLuaFunction(handle, "cursor_outline", "off", disableOutline))
        throw std::runtime_error("cursor-outline: failed to register disable action");

    g_renderStageListener    = Event::bus()->m_events.render.stage.listen([](eRenderStage stage) {
        if (stage == RENDER_LAST_MOMENT)
            queueOutlineForMonitor(g_pHyprRenderer->m_renderData.pMonitor.lock());
    });
    g_monitorAddedListener   = Event::bus()->m_events.monitor.added.listen([](PHLMONITOR monitor) {
        if (g_outlineEnabled)
            lockSoftwareCursor(monitor);
    });
    g_configReloadedListener = Event::bus()->m_events.config.reloaded.listen([] {
        if (g_outlineEnabled)
            damageCurrentOutline();
    });
    HyprlandAPI::reloadConfig();

    return {
        "cursor-outline",
        "Toggle an accent outline around the cursor silhouette",
        "local",
        "0.1.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_renderStageListener.reset();
    g_monitorAddedListener.reset();
    g_configReloadedListener.reset();
    setOutlineEnabled(false);

    if (g_shader) {
        g_pHyprOpenGL->makeEGLCurrent();
        if (g_pHyprOpenGL->m_shadersInitialized)
            g_pHyprOpenGL->useShader(g_pHyprOpenGL->getShaderVariant(SH_FRAG_PASSTHRURGBA));
    }
    g_shader.reset();
    g_outlineThickness.reset();
    g_outlineColor.reset();
    g_shaderFailed = false;
}
