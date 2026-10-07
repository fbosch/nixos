#pragma once

#include <algorithm>
#include <cmath>
#include <format>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace TransientPlacement {

struct Rule {
    std::string parentClass;
    std::string childClass;
    std::vector<std::string> childTitlePrefixes;
    bool inferFocusedParent = false;
    bool noAnim = false;
};

struct ParentCandidate {
    bool declared = false;
    std::optional<std::string_view> className;
    bool mapped = false;
    bool hidden = false;
    bool isChild = false;
};

enum class ParentSource { DECLARED, FOCUSED };

struct Selection {
    const Rule* rule;
    ParentSource source;
};

struct Rect {
    double x;
    double y;
    double width;
    double height;
};

struct Point {
    double x;
    double y;
};

struct PositionExpression {
    std::string x;
    std::string y;
};

inline bool validRule(const Rule& rule) {
    const auto validText = [](std::string_view value) {
        return !value.empty() && value.find('\0') == std::string_view::npos;
    };
    return validText(rule.parentClass) && validText(rule.childClass) &&
        std::ranges::all_of(rule.childTitlePrefixes, validText);
}

inline bool validRules(std::span<const Rule> rules) {
    return std::ranges::all_of(rules, validRule);
}

class RuleSet {
  public:
    bool replace(std::vector<Rule> next) {
        if (!validRules(next))
            return false;
        rules_ = std::move(next);
        return true;
    }

    const std::vector<Rule>& rules() const { return rules_; }

  private:
    std::vector<Rule> rules_;
};

inline std::optional<Selection> selectRule(
    std::span<const Rule> rules,
    std::string_view childClass,
    std::string_view initialTitle,
    const ParentCandidate& declaredParent,
    const ParentCandidate& focusedWindow) {
    for (const auto& rule : rules) {
        if (rule.childClass != childClass)
            continue;
        if (!rule.childTitlePrefixes.empty() &&
            std::ranges::none_of(rule.childTitlePrefixes, [initialTitle](const auto& prefix) { return initialTitle.starts_with(prefix); }))
            continue;

        if (declaredParent.declared) {
            if (declaredParent.mapped && !declaredParent.isChild && declaredParent.className &&
                *declaredParent.className == rule.parentClass)
                return Selection{&rule, ParentSource::DECLARED};
            continue;
        }

        if (rule.inferFocusedParent && focusedWindow.mapped && !focusedWindow.hidden && !focusedWindow.isChild &&
            focusedWindow.className && *focusedWindow.className == rule.parentClass)
            return Selection{&rule, ParentSource::FOCUSED};
    }
    return std::nullopt;
}

inline bool validGeometry(const Rect& rect) {
    return std::isfinite(rect.x) && std::isfinite(rect.y) && std::isfinite(rect.width) && std::isfinite(rect.height) &&
        rect.width > 0 && rect.height > 0 && std::isfinite(rect.x + rect.width) && std::isfinite(rect.y + rect.height);
}

inline std::optional<double> centeredCoordinate(double parentOrigin, double parentExtent, double monitorOrigin, double childExtent) {
    if (!std::isfinite(parentOrigin) || !std::isfinite(parentExtent) || parentExtent <= 0 || !std::isfinite(monitorOrigin) ||
        !std::isfinite(childExtent) || childExtent <= 0)
        return std::nullopt;
    const double result = parentOrigin + (parentExtent - childExtent) / 2 - monitorOrigin;
    if (!std::isfinite(result))
        return std::nullopt;
    return result;
}

inline std::optional<PositionExpression> makePositionExpression(const Rect& parent, const Point& monitorOrigin) {
    if (!validGeometry(parent) || !std::isfinite(monitorOrigin.x) || !std::isfinite(monitorOrigin.y))
        return std::nullopt;
    const double relativeX = parent.x - monitorOrigin.x;
    const double relativeY = parent.y - monitorOrigin.y;
    if (!std::isfinite(relativeX) || !std::isfinite(relativeY))
        return std::nullopt;
    return PositionExpression{
        std::format("({:.17g}+{:.17g}/2-window_w/2)", relativeX, parent.width),
        std::format("({:.17g}+{:.17g}/2-window_h/2)", relativeY, parent.height),
    };
}

} // namespace TransientPlacement
