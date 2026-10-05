#include "position_writer.hpp"
#include "position_config.hpp"

#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/rule/matchEngine/RegexMatchEngine.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <re2/re2.h>

#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstdio>
#include <format>
#include <stdexcept>
#include <iterator>
#include <initializer_list>
#include <memory>
#include <optional>
#include <ranges>
#include <set>
#include <string>
#include <utility>
#include <vector>

extern "C" {
#include <lua.h>
}

namespace {
    namespace fs = std::filesystem;
    using namespace PositionStore;

    enum class Field { CLASS, TITLE, INITIAL_CLASS, INITIAL_TITLE };
    struct Matcher {
        Field field;
        std::string pattern;
        std::unique_ptr<Desktop::Rule::CRegexMatchEngine> engine;
        bool matches(PHLWINDOW window) const {
            const auto& metadata = window->metadata();
            switch (field) {
                case Field::CLASS: return engine->match(metadata.appID());
                case Field::TITLE: return engine->match(metadata.title());
                case Field::INITIAL_CLASS: return engine->match(metadata.initialAppID());
                case Field::INITIAL_TITLE: return engine->match(metadata.initialTitle());
            }
            return false;
        }
    };
    struct Selector {
        std::string id;
        Matcher match;
        std::vector<Matcher> exclude;
        bool global = false;
    };

    std::string g_path;
    Records g_records;
    bool g_dirty = false;
    std::vector<Selector> g_selectors;
    CHyprSignalListener g_openListener, g_closeListener, g_moveListener, g_buttonListener, g_keyListener;
    PHLWINDOWREF g_drag, g_suppressedDrag;
    PHLMONITORREF g_dragReleaseMonitor;
    bool g_dragMotion = false;
    bool g_dragQualified = false;
    uint64_t g_syncSequence = 0;
    uint64_t g_explicitSequence = 0;
    struct SExplicitCapture {
        PHLWINDOWREF window;
        PHLMONITORREF monitor;
    };
    std::vector<SExplicitCapture> g_explicitWindows;

    void warning(const char* reason) { std::fprintf(stderr, "persistent-position: %s\n", reason); }

    PositionStorage::Writer g_writer;

    void queueSave() {
        if (g_dirty && !g_path.empty()) g_writer.enqueue(g_path, g_records);
    }

    const Selector* matching(PHLWINDOW window) {
        for (const auto& selector : g_selectors) {
            if (!selector.match.matches(window)) continue;
            bool excluded = false;
            for (const auto& exclusion : selector.exclude)
                if (exclusion.matches(window)) { excluded = true; break; }
            if (!excluded) return &selector;
        }
        return nullptr;
    }

    bool eligible(PHLWINDOW window) {
        return Desktop::View::validMapped(window) && window->isFloating() &&
            !Fullscreen::controller()->isFullscreen(window) && window->m_monitor.lock();
    }

    void capture(PHLWINDOW window) {
        if (!eligible(window) || g_path.empty()) return;
        const auto selector = matching(window);
        if (!selector) return;
        const auto monitor = window->m_monitor.lock();
        const auto box = window->layoutBox();
        const Point position{box.x - monitor->m_position.x, box.y - monitor->m_position.y};
        if (!validPoint(position) || !std::isfinite(box.width) || !std::isfinite(box.height) || box.width <= 0 || box.height <= 0) return;
        Key key{selector->id, selector->global ? "" : monitor->m_name};
        if (!validKey(key.monitor, selector->global) || (g_records.size() >= 4096 && !g_records.contains(key))) return;
        if (const auto it = g_records.find(key); it != g_records.end() && it->second == position) return;
        g_records[std::move(key)] = position;
        g_dirty = true;
        queueSave();
    }

    void onOpen(PHLWINDOW window) {
        if (!window || !window->m_ruleApplicator || g_path.empty() || g_selectors.empty()) return;
        const auto& rules = window->m_ruleApplicator->static_;
        if (rules.position || rules.center.value_or(false) || rules.fullscreen.value_or(false) || rules.maximize.value_or(false) ||
            !window->m_monitor.lock() || !window->layoutTarget()->floating()) return;
        const auto selector = matching(window);
        if (!selector) return;
        const auto monitor = window->m_monitor.lock();
        const auto it = g_records.find({selector->id, selector->global ? "" : monitor->m_name});
        if (it == g_records.end()) return;
        const auto area = monitor->logicalBoxMinusReserved();
        if (!validPoint(it->second) || area.w <= 0 || area.h <= 0) return;
        // The floating layout evaluates window_w/h after applying the first-map size rule.
        // muParser's min/max clamp without changing that size or moving the selected monitor.
        auto axis = [](double saved, double start, double extent, const char* size) {
            return std::format("max({0},min({1},max({0},({0}+{2}-{3}))))", start, saved, extent, size);
        };
        window->m_ruleApplicator->static_.position = Math::SExpressionVec2{
            axis(it->second.x, area.x - monitor->m_position.x, area.w, "window_w"),
            axis(it->second.y, area.y - monitor->m_position.y, area.h, "window_h"),
        };
    }

    bool activeDrag() {
        if (!g_layoutManager || !g_layoutManager->dragController()) return false;
        const auto& controller = g_layoutManager->dragController();
        const auto mode = controller->mode();
        if (mode != MBIND_MOVE && mode != MBIND_RESIZE && mode != MBIND_RESIZE_FORCE_RATIO && mode != MBIND_RESIZE_BLOCK_RATIO) return false;
        static auto PDRAGTHRESHOLD = CConfigValue<Config::INTEGER>("binds:drag_threshold");
        if (*PDRAGTHRESHOLD > 0 && !controller->dragThresholdReached()) return false;
        const auto target = controller->target();
        if (!target || target->window() == g_suppressedDrag.lock() || !eligible(target->window())) return false;
        if (g_drag.lock() != target->window()) {
            g_drag = target->window();
            g_dragReleaseMonitor.reset();
            g_dragMotion = false;
            g_dragQualified = false;
        }
        g_dragQualified = true;
        return true;
    }
    void syncDrag() {
        g_syncSequence = 0;
        if (g_suppressedDrag.lock() && g_layoutManager && g_layoutManager->dragController() &&
            !g_layoutManager->dragController()->target()) g_suppressedDrag.reset();
        if (activeDrag()) return;
        if (g_dragMotion && g_dragQualified && g_dragReleaseMonitor.lock())
            if (const auto window = g_drag.lock(); window && window->m_monitor.lock() == g_dragReleaseMonitor.lock()) capture(window);
        g_drag.reset();
        g_dragReleaseMonitor.reset();
        g_dragMotion = g_dragQualified = false;
    }
    void scheduleSync(bool beforeRelease) {
        // Input release is delivered before dragEnd; preserve the target first.
        if (beforeRelease && activeDrag())
            if (const auto window = g_drag.lock()) g_dragReleaseMonitor = window->m_monitor;
        if (!g_syncSequence && g_pEventLoopManager)
            g_syncSequence = g_pEventLoopManager->doLater([] { syncDrag(); });
    }
    int fail(lua_State* state, const std::string& message) {
        lua_pushnil(state);
        lua_pushlstring(state, message.data(), message.size());
        return 2;
    }
    std::optional<std::string> textField(lua_State* state, int index, const char* field) {
        lua_getfield(state, index, field);
        std::optional<std::string> value;
        if (lua_type(state, -1) == LUA_TSTRING) {
            size_t length = 0;
            const auto chars = lua_tolstring(state, -1, &length);
            value = std::string(chars, length);
        }
        lua_pop(state, 1);
        return value;
    }
    bool knownFields(lua_State* state, int index, std::initializer_list<std::string_view> fields) {
        lua_pushnil(state);
        while (lua_next(state, index) != 0) {
            size_t length = 0;
            const char* key = lua_type(state, -2) == LUA_TSTRING ? lua_tolstring(state, -2, &length) : nullptr;
            const bool known = key && std::ranges::find(fields, std::string_view(key, length)) != fields.end();
            lua_pop(state, 1);
            if (!known) { lua_pop(state, 1); return false; }
        }
        return true;
    }
    bool denseArray(lua_State* state, int index, size_t count) {
        std::vector<double> keys;
        lua_pushnil(state);
        while (lua_next(state, index) != 0) {
            if (keys.size() >= count) { lua_pop(state, 2); return false; }
            keys.push_back(lua_type(state, -2) == LUA_TNUMBER ? lua_tonumber(state, -2) : 0);
            lua_pop(state, 1);
        }
        return PositionConfig::denseKeys(count, keys);
    }
    std::optional<Field> fieldFrom(std::string_view value) {
        if (value == "match:class") return Field::CLASS;
        if (value == "match:title") return Field::TITLE;
        if (value == "match:initial_class" || value == "match:initialClass") return Field::INITIAL_CLASS;
        if (value == "match:initial_title" || value == "match:initialTitle") return Field::INITIAL_TITLE;
        return std::nullopt;
    }
    std::optional<Matcher> parseMatcher(lua_State* state, int index, std::string& error) {
        auto name = textField(state, index, "matcher"), pattern = textField(state, index, "pattern");
        if (!name || !pattern || !fieldFrom(*name) || pattern->empty() || pattern->size() > 512) {
            error = "matcher requires a supported matcher name and nonempty bounded pattern"; return std::nullopt;
        }
        const std::string_view source = pattern->starts_with("negative:") ? std::string_view(*pattern).substr(9) : std::string_view(*pattern);
        re2::RE2 probe{std::string(source)};
        if (source.empty() || !probe.ok()) { error = "invalid RE2 selector pattern"; return std::nullopt; }
        return Matcher{*fieldFrom(*name), *pattern, std::make_unique<Desktop::Rule::CRegexMatchEngine>(*pattern)};
    }
    int configure(lua_State* state) {
        if (lua_type(state, 1) != LUA_TSTRING || lua_type(state, 2) != LUA_TTABLE)
            return fail(state, "expected absolute state path and ordered selector array");
        size_t length = 0;
        const auto bytes = lua_tolstring(state, 1, &length);
        std::string path(bytes, length);
        const fs::path statePath(path);
        if (path.find('\0') != std::string::npos) return fail(state, "invalid state path");
        const char* xdgState = std::getenv("XDG_STATE_HOME");
        const char* home = std::getenv("HOME");
        if ((!xdgState || !*xdgState) && (!home || !*home))
            return fail(state, "XDG_STATE_HOME or HOME is required for state storage");
        const fs::path stateRoot = xdgState && *xdgState ? fs::path(xdgState) : fs::path(home) / ".local/state";
        if (!PositionStorage::validatePath(statePath, stateRoot))
            return fail(state, "state file must be inside XDG_STATE_HOME (or HOME/.local/state)");
        std::vector<Selector> selectors;
        std::set<std::string> ids;
        const size_t count = lua_rawlen(state, 2);
        if (count > 256 || !denseArray(state, 2, count)) return fail(state, "selectors must be a bounded dense array");
        std::string error;
        for (size_t i = 1; i <= count; ++i) {
            lua_rawgeti(state, 2, i);
            if (lua_type(state, -1) != LUA_TTABLE) { lua_pop(state, 1); return fail(state, "selector must be a table"); }
            const int index = lua_gettop(state);
            if (!knownFields(state, index, {"id", "matcher", "pattern", "per_monitor", "exclude"})) {
                lua_pop(state, 1); return fail(state, "unknown selector field");
            }
            auto id = textField(state, index, "id");
            auto match = parseMatcher(state, index, error);
            if (!id || !validKey(*id) || !ids.insert(*id).second || !match) {
                lua_pop(state, 1); return fail(state, error.empty() ? "selector id must be unique and valid" : error);
            }
            Selector selector{*id, std::move(*match), {}};
            lua_getfield(state, index, "per_monitor");
            if (lua_type(state, -1) != LUA_TNIL && lua_type(state, -1) != LUA_TBOOLEAN) { lua_pop(state, 2); return fail(state, "per_monitor must be boolean"); }
            selector.global = lua_type(state, -1) == LUA_TBOOLEAN && !lua_toboolean(state, -1);
            lua_pop(state, 1);
            lua_getfield(state, index, "exclude");
            if (lua_type(state, -1) != LUA_TNIL) {
                if (lua_type(state, -1) != LUA_TTABLE) { lua_pop(state, 2); return fail(state, "exclude must be a table"); }
                if (!knownFields(state, lua_gettop(state), {"matcher", "patterns"})) {
                    lua_pop(state, 2); return fail(state, "unknown exclusion field");
                }
                auto excludeName = textField(state, -1, "matcher");
                lua_getfield(state, -1, "patterns");
                const size_t patternCount = lua_type(state, -1) == LUA_TTABLE ? lua_rawlen(state, -1) : 0;
                if (!excludeName || !fieldFrom(*excludeName) || lua_type(state, -1) != LUA_TTABLE ||
                    patternCount == 0 || patternCount > 64 || !denseArray(state, lua_gettop(state), patternCount)) {
                    lua_pop(state, 3); return fail(state, "exclude requires matcher and bounded patterns array");
                }
                for (size_t j = 1; j <= patternCount; ++j) {
                    lua_rawgeti(state, -1, j);
                    if (lua_type(state, -1) != LUA_TSTRING) { lua_pop(state, 4); return fail(state, "exclude pattern must be string"); }
                    size_t n = 0;
                    const auto text = lua_tolstring(state, -1, &n);
                    std::string pattern(text, n);
                    lua_pop(state, 1);
                    lua_newtable(state);
                    lua_pushlstring(state, excludeName->data(), excludeName->size()); lua_setfield(state, -2, "matcher");
                    lua_pushlstring(state, pattern.data(), pattern.size()); lua_setfield(state, -2, "pattern");
                    auto exclusion = parseMatcher(state, -1, error);
                    lua_pop(state, 1);
                    if (!exclusion) { lua_pop(state, 3); return fail(state, error); }
                    selector.exclude.push_back(std::move(*exclusion));
                }
                lua_pop(state, 1); // patterns
            }
            lua_pop(state, 2); // exclude and selector
            selectors.push_back(std::move(selector));
        }
        // Cancel old-generation capture callbacks before draining their immutable writer snapshots.
        if (g_syncSequence && g_pEventLoopManager) g_pEventLoopManager->removeDoLater(g_syncSequence);
        if (g_explicitSequence && g_pEventLoopManager) g_pEventLoopManager->removeDoLater(g_explicitSequence);
        g_syncSequence = g_explicitSequence = 0;
        g_explicitWindows.clear();
        g_suppressedDrag.reset();
        if (g_layoutManager && g_layoutManager->dragController()) {
            if (const auto target = g_layoutManager->dragController()->target()) g_suppressedDrag = target->window();
        }
        g_drag.reset();
        g_dragReleaseMonitor.reset();
        g_dragMotion = g_dragQualified = false;
        if (g_dirty) queueSave();
        if (!g_writer.drain(error)) {
            warning(error.c_str()); return fail(state, "pending state write failed: " + error);
        }
        Records records;
        if (!PositionStorage::load(statePath, records, error, true)) {
            warning(error.c_str()); return fail(state, error);
        }
        g_records = std::move(records);
        g_dirty = false;
        g_path = std::move(path);
        g_selectors = std::move(selectors);
        lua_pushboolean(state, true);
        return 1;
    }
    int captureFocused(lua_State* state) {
        const auto window = Desktop::focusState()->window();
        if (!eligible(window) || !matching(window) || !g_pEventLoopManager) { lua_pushboolean(state, false); return 1; }
        if (std::ranges::none_of(g_explicitWindows, [&window](const auto& queued) { return queued.window.lock() == window; }))
            g_explicitWindows.push_back({window, window->m_monitor});
        if (!g_explicitSequence)
            g_explicitSequence = g_pEventLoopManager->doLater([] {
                g_explicitSequence = 0;
                auto queued = std::move(g_explicitWindows);
                g_explicitWindows.clear();
                for (const auto& pending : queued)
                    if (const auto window = pending.window.lock(); window && window->m_monitor.lock() == pending.monitor.lock()) capture(window);
            });
        lua_pushboolean(state, true);
        return 1;
    }
    void cleanup() {
        if (g_syncSequence && g_pEventLoopManager) g_pEventLoopManager->removeDoLater(g_syncSequence);
        if (g_explicitSequence && g_pEventLoopManager) g_pEventLoopManager->removeDoLater(g_explicitSequence);
        g_syncSequence = g_explicitSequence = 0;
        g_openListener.reset(); g_closeListener.reset(); g_moveListener.reset(); g_buttonListener.reset(); g_keyListener.reset();
        g_drag.reset(); g_suppressedDrag.reset(); g_dragReleaseMonitor.reset(); g_explicitWindows.clear();
        g_dragMotion = g_dragQualified = false;
        if (g_dirty) queueSave();
        std::string error;
        if (!g_writer.drain(error)) warning(error.c_str());
        g_writer.stop();
        g_selectors.clear(); g_records.clear(); g_path.clear();
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (!HyprlandAPI::addLuaFunction(handle, "persistent_position", "configure", configure) ||
        !HyprlandAPI::addLuaFunction(handle, "persistent_position", "capture_focused", captureFocused)) {
        cleanup();
        throw std::runtime_error("persistent-position: Lua registration failed");
    }
    g_writer.start();
    g_openListener = Event::bus()->m_events.window.openEarly.listen([](PHLWINDOW window) { onOpen(window); });
    g_closeListener = Event::bus()->m_events.window.close.listen([](PHLWINDOW window) {
        if (g_drag.lock() == window) {
            if (g_dragMotion && g_dragQualified && window->m_monitor.lock() == g_dragReleaseMonitor.lock()) capture(window);
            g_drag.reset();
            g_dragReleaseMonitor.reset();
            g_dragMotion = g_dragQualified = false;
        }
        const auto it = std::ranges::find_if(g_explicitWindows, [&window](const auto& queued) { return queued.window.lock() == window; });
        if (it != g_explicitWindows.end()) {
            if (window->m_monitor.lock() == it->monitor.lock()) capture(window);
            g_explicitWindows.erase(it);
        }
        if (g_dirty) queueSave();
    });
    g_moveListener = Event::bus()->m_events.input.mouse.move.listen([](const auto&, auto&) {
        if (g_layoutManager && g_layoutManager->dragController()) {
            const auto target = g_layoutManager->dragController()->target();
            if (target && target->window() && target->window() != g_suppressedDrag.lock()) {
                if (g_drag.lock() != target->window()) {
                    g_drag = target->window();
                    g_dragReleaseMonitor.reset();
                    g_dragMotion = g_dragQualified = false;
                }
                g_dragMotion = true;
            }
        }
        scheduleSync(false);
    });
    g_buttonListener = Event::bus()->m_events.input.mouse.button.listen([](const auto&, auto&) { scheduleSync(true); });
    g_keyListener = Event::bus()->m_events.input.keyboard.key.listen([](const auto&, auto&) { scheduleSync(true); });
    return {"persistent-position", "Opt-in durable pre-layout floating position restore", "local", "0.1.0"};
}
APICALL EXPORT void PLUGIN_EXIT() { cleanup(); }
