#include "transient_placement_policy.hpp"

#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include <algorithm>
#include <initializer_list>
#include <optional>
#include <ranges>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

extern "C" {
#include <lua.h>
}

namespace {

using namespace TransientPlacement;

RuleSet g_rules;
CHyprSignalListener g_openEarlyListener;
HANDLE g_pluginHandle = nullptr;
bool g_luaFunctionRegistered = false;

int fail(lua_State* state, std::string_view message) {
    lua_pushnil(state);
    lua_pushlstring(state, message.data(), message.size());
    return 2;
}

std::optional<size_t> denseArrayLength(lua_State* state, int index) {
    index = lua_absindex(state, index);
    if (lua_type(state, index) != LUA_TTABLE)
        return std::nullopt;

    const size_t length = lua_rawlen(state, index);
    size_t keyCount = 0;
    lua_pushnil(state);
    while (lua_next(state, index) != 0) {
        const bool validKey = lua_isinteger(state, -2) && lua_tointeger(state, -2) >= 1 &&
            static_cast<size_t>(lua_tointeger(state, -2)) <= length;
        lua_pop(state, 1);
        if (!validKey) {
            lua_pop(state, 1);
            return std::nullopt;
        }
        ++keyCount;
    }
    if (keyCount != length)
        return std::nullopt;

    for (size_t i = 1; i <= length; ++i) {
        lua_rawgeti(state, index, static_cast<lua_Integer>(i));
        const bool present = !lua_isnil(state, -1);
        lua_pop(state, 1);
        if (!present)
            return std::nullopt;
    }
    return length;
}

bool knownFields(lua_State* state, int index, std::initializer_list<std::string_view> fields) {
    index = lua_absindex(state, index);
    lua_pushnil(state);
    while (lua_next(state, index) != 0) {
        size_t length = 0;
        const char* key = lua_type(state, -2) == LUA_TSTRING ? lua_tolstring(state, -2, &length) : nullptr;
        const bool known = key && std::ranges::find(fields, std::string_view(key, length)) != fields.end();
        lua_pop(state, 1);
        if (!known) {
            lua_pop(state, 1);
            return false;
        }
    }
    return true;
}

bool stringField(lua_State* state, int index, const char* name, bool required, std::string& output) {
    index = lua_absindex(state, index);
    lua_pushstring(state, name);
    lua_rawget(state, index);
    if (lua_isnil(state, -1)) {
        lua_pop(state, 1);
        return !required;
    }
    if (lua_type(state, -1) != LUA_TSTRING) {
        lua_pop(state, 1);
        return false;
    }
    size_t length = 0;
    const char* value = lua_tolstring(state, -1, &length);
    output.assign(value, length);
    lua_pop(state, 1);
    return !output.empty() && output.find('\0') == std::string::npos;
}

bool booleanField(lua_State* state, int index, const char* name, bool& output) {
    index = lua_absindex(state, index);
    lua_pushstring(state, name);
    lua_rawget(state, index);
    if (lua_isnil(state, -1)) {
        lua_pop(state, 1);
        return true;
    }
    if (lua_type(state, -1) != LUA_TBOOLEAN) {
        lua_pop(state, 1);
        return false;
    }
    output = lua_toboolean(state, -1);
    lua_pop(state, 1);
    return true;
}

bool titlePrefixesField(lua_State* state, int index, std::vector<std::string>& output) {
    index = lua_absindex(state, index);
    lua_pushliteral(state, "child_title_prefixes");
    lua_rawget(state, index);
    if (lua_isnil(state, -1)) {
        lua_pop(state, 1);
        return true;
    }
    const auto length = denseArrayLength(state, -1);
    if (!length) {
        lua_pop(state, 1);
        return false;
    }
    const int arrayIndex = lua_absindex(state, -1);
    output.reserve(*length);
    for (size_t i = 1; i <= *length; ++i) {
        lua_rawgeti(state, arrayIndex, static_cast<lua_Integer>(i));
        if (lua_type(state, -1) != LUA_TSTRING) {
            lua_pop(state, 2);
            return false;
        }
        size_t valueLength = 0;
        const char* value = lua_tolstring(state, -1, &valueLength);
        std::string prefix(value, valueLength);
        lua_pop(state, 1);
        if (prefix.empty() || prefix.find('\0') != std::string::npos) {
            lua_pop(state, 1);
            return false;
        }
        output.push_back(std::move(prefix));
    }
    lua_pop(state, 1);
    return true;
}

bool parseConfiguration(lua_State* state, int index, std::vector<Rule>& output) {
    const auto length = denseArrayLength(state, index);
    if (!length)
        return false;

    index = lua_absindex(state, index);
    output.reserve(*length);
    for (size_t i = 1; i <= *length; ++i) {
        lua_rawgeti(state, index, static_cast<lua_Integer>(i));
        if (lua_type(state, -1) != LUA_TTABLE) {
            lua_pop(state, 1);
            return false;
        }
        const int ruleIndex = lua_absindex(state, -1);
        if (!knownFields(state, ruleIndex, {"parent_class", "child_class", "child_title_prefixes", "infer_focused_parent", "no_anim"})) {
            lua_pop(state, 1);
            return false;
        }

        Rule rule;
        if (!stringField(state, ruleIndex, "parent_class", true, rule.parentClass) ||
            !stringField(state, ruleIndex, "child_class", true, rule.childClass) ||
            !titlePrefixesField(state, ruleIndex, rule.childTitlePrefixes) ||
            !booleanField(state, ruleIndex, "infer_focused_parent", rule.inferFocusedParent) ||
            !booleanField(state, ruleIndex, "no_anim", rule.noAnim)) {
            lua_pop(state, 1);
            return false;
        }
        lua_pop(state, 1);
        output.push_back(std::move(rule));
    }
    return validRules(output);
}

bool hasExplicitPlacementPolicy(PHLWINDOW window) {
    const auto& staticRules = window->m_ruleApplicator->static_;
    const auto& traits = window->backend().traits();
    return staticRules.position.has_value() || staticRules.center.value_or(false) || staticRules.fullscreen.value_or(false) ||
        staticRules.maximize.value_or(false) || staticRules.fullscreenStateClient.value_or(0) != 0 ||
        staticRules.fullscreenStateInternal.value_or(0) != 0 || traits.fullscreen;
}

void onOpenEarly(PHLWINDOW child) {
    if (!child || !child->m_ruleApplicator || !child->layoutTarget() || !child->layoutTarget()->floating() ||
        !(child->m_state & Desktop::View::WINDOW_STATE_FIRST_MAP))
        return;

    const auto& rules = g_rules.rules();
    if (rules.empty())
        return;
    const std::string_view childClass = child->metadata().initialAppID();
    const std::string_view initialTitle = child->metadata().initialTitle();
    // Filter first: XWayland parent resolution can scan all windows.
    const bool hasPotentialRule = std::ranges::any_of(rules, [childClass, initialTitle](const Rule& rule) {
        return rule.childClass == childClass &&
            (rule.childTitlePrefixes.empty() || std::ranges::any_of(rule.childTitlePrefixes,
                [initialTitle](const std::string& prefix) { return initialTitle.starts_with(prefix); }));
    });
    if (!hasPotentialRule)
        return;

    const auto declaredParentWindow = child->backend().parent();
    const bool hasDeclaredParent = declaredParentWindow || child->backend().traits().transient;
    ParentCandidate declaredParent{
        .declared = hasDeclaredParent,
        .className = declaredParentWindow ? std::optional<std::string_view>(declaredParentWindow->metadata().initialAppID()) : std::nullopt,
        .mapped = declaredParentWindow && Desktop::View::validMapped(declaredParentWindow),
        .hidden = declaredParentWindow && declaredParentWindow->isHidden(),
        .isChild = declaredParentWindow == child,
    };

    PHLWINDOW focusedWindow;
    ParentCandidate focusedParent{};
    // An unavailable declared parent also prevents focus inference.
    if (!hasDeclaredParent) {
        focusedWindow = Desktop::focusState()->window();
        const bool focusedMapped = focusedWindow && focusedWindow != child && Desktop::View::validMapped(focusedWindow) && !focusedWindow->isHidden();
        focusedParent = ParentCandidate{
            .className = focusedWindow ? std::optional<std::string_view>(focusedWindow->metadata().initialAppID()) : std::nullopt,
            .mapped = focusedMapped,
            .hidden = focusedWindow && focusedWindow->isHidden(),
            .isChild = focusedWindow == child,
        };
    }

    const auto selected = selectRule(rules, childClass, initialTitle, declaredParent, focusedParent);
    if (!selected)
        return;
    if (selected->rule->noAnim)
        child->m_ruleApplicator->noAnim().set(true, Desktop::Types::PRIORITY_SET_PROP);
    if (hasExplicitPlacementPolicy(child))
        return;

    const auto parentWindow = selected->source == ParentSource::DECLARED ? declaredParentWindow : focusedWindow;
    if (!parentWindow || !Desktop::View::validMapped(parentWindow))
        return;
    const auto monitor = child->m_monitor.lock();
    if (!monitor)
        return;

    const auto box = parentWindow->layoutBox();
    auto expression = makePositionExpression(
        Rect{box.x, box.y, box.w, box.h}, Point{monitor->m_position.x, monitor->m_position.y});
    if (!expression)
        return;

    child->m_ruleApplicator->static_.position = Math::SExpressionVec2{std::move(expression->x), std::move(expression->y)};
}

int configure(lua_State* state) {
    if (lua_gettop(state) != 1 || lua_type(state, 1) != LUA_TTABLE)
        return fail(state, "expected one dense array of placement rules");

    std::vector<Rule> parsed;
    if (!parseConfiguration(state, 1, parsed))
        return fail(state, "invalid placement rules; expected dense exact-class rules with known fields only");
    if (!g_rules.replace(std::move(parsed)))
        return fail(state, "invalid placement rules");

    lua_pushboolean(state, true);
    return 1;
}

void cleanup() {
    g_openEarlyListener.reset();
    g_rules.replace({});
    if (g_luaFunctionRegistered && g_pluginHandle)
        HyprlandAPI::removeLuaFunction(g_pluginHandle, "transient_placement", "configure");
    g_luaFunctionRegistered = false;
    g_pluginHandle = nullptr;
}

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const char* runtimeHash = __hyprland_api_get_hash();
    const char* buildHash = __hyprland_api_get_client_hash();
    if (!runtimeHash || !buildHash || std::string_view(runtimeHash) != std::string_view(buildHash))
        throw std::runtime_error("transient-placement: Hyprland build/runtime API hash mismatch; rebuild the plugin");
    g_pluginHandle = handle;
    if (!HyprlandAPI::addLuaFunction(handle, "transient_placement", "configure", configure)) {
        g_pluginHandle = nullptr;
        throw std::runtime_error("transient-placement: Lua API registration failed");
    }
    g_luaFunctionRegistered = true;
    g_openEarlyListener = Event::bus()->m_events.window.openEarly.listen(onOpenEarly);
    return {"transient-placement", "Configure pre-layout transient window centering", "local", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() { cleanup(); }
