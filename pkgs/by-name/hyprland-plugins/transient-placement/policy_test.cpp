#include "transient_placement_policy.hpp"

#include <array>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <utility>

using namespace TransientPlacement;

namespace {

void check(bool condition, const char* message) {
    if (!condition)
        throw std::runtime_error(message);
}

Rule rule(std::string parentClass, std::string childClass, bool infer = false) {
    return Rule{
        .parentClass = std::move(parentClass),
        .childClass = std::move(childClass),
        .inferFocusedParent = infer,
    };
}

void matchingUsesExactClassesAndInitialTitlePrefixes() {
    auto rules = std::vector{
        rule("owner", "child"),
        Rule{
            .parentClass = "owner",
            .childClass = "child",
            .childTitlePrefixes = {"General: ", "Advanced: "},
        },
    };
    const ParentCandidate owner{.declared = true, .className = "owner", .mapped = true};
    const ParentCandidate noFocus{};

    const auto match = selectRule(rules, "child", "General: preferences", owner, noFocus);
    check(match && match->rule == &rules[0], "first matching rule should retain array order");
    check(!selectRule(std::span{rules}.subspan(1), "child", "Other title", owner, noFocus), "title prefixes should filter initial titles");
    check(!selectRule(rules, "Child", "General: preferences", owner, noFocus), "class matching must be exact and case-sensitive");
}

void declaredParentIsAuthoritative() {
    const auto inferredRule = rule("expected", "child", true);
    const auto rules = std::array{inferredRule};
    const ParentCandidate declared{.declared = true, .className = "different", .mapped = true};
    const ParentCandidate focused{.className = "expected", .mapped = true};
    check(!selectRule(rules, "child", "title", declared, focused), "a mismatching declared parent must not fall back to focus inference");

    const auto secondRule = rule("different", "child", true);
    const auto orderedRules = std::array{inferredRule, secondRule};
    const auto match = selectRule(orderedRules, "child", "title", declared, focused);
    check(match && match->rule == &orderedRules[1] && match->source == ParentSource::DECLARED,
        "a later rule for the actual declared parent may match");
}

void focusedInferenceIsOptInAndRequiresVisibleMappedParent() {
    const auto optIn = rule("owner", "child", true);
    const auto noOptIn = rule("owner", "child");
    const auto rules = std::array{noOptIn, optIn};
    const ParentCandidate noDeclaredParent{};
    const ParentCandidate focused{.className = "owner", .mapped = true};

    const auto match = selectRule(rules, "child", "title", noDeclaredParent, focused);
    check(match && match->rule == &rules[1] && match->source == ParentSource::FOCUSED, "inference should select the first opted-in rule");
    check(!selectRule(std::span{rules}.first(1), "child", "title", noDeclaredParent, focused), "focus inference must be opt-in");

    const ParentCandidate hidden{.className = "owner", .mapped = true, .hidden = true};
    const ParentCandidate unmapped{.className = "owner", .mapped = false};
    const ParentCandidate self{.className = "owner", .mapped = true, .isChild = true};
    check(!selectRule(std::span{rules}.subspan(1), "child", "title", noDeclaredParent, hidden), "hidden focused windows cannot be inferred");
    check(!selectRule(std::span{rules}.subspan(1), "child", "title", noDeclaredParent, unmapped), "unmapped focused windows cannot be inferred");
    check(!selectRule(std::span{rules}.subspan(1), "child", "title", noDeclaredParent, self), "the child cannot infer itself as its parent");
}

void unusableDeclaredParentDoesNotInfer() {
    const auto configured = rule("owner", "child", true);
    const auto rules = std::array{configured};
    const ParentCandidate unavailable{.declared = true};
    const ParentCandidate focused{.className = "owner", .mapped = true};
    check(!selectRule(rules, "child", "title", unavailable, focused), "an unavailable declared parent must not trigger inference");
}

void invalidGeometryIsRejectedAndExpressionUsesFinalChildSize() {
    const Rect parent{100, 80, 500, 300};
    const Point monitor{50, 30};
    check(validGeometry(parent), "valid parent box rejected");
    check(!validGeometry(Rect{0, 0, 0, 1}), "zero-width parent accepted");
    check(!validGeometry(Rect{0, 0, std::numeric_limits<double>::infinity(), 1}), "infinite parent accepted");
    check(!validGeometry(Rect{std::numeric_limits<double>::quiet_NaN(), 0, 10, 10}), "NaN parent accepted");
    check(!makePositionExpression(parent, Point{std::numeric_limits<double>::infinity(), 0}), "invalid monitor geometry accepted");

    const auto expression = makePositionExpression(parent, monitor);
    check(expression.has_value(), "valid center expression was not generated");
    check(expression->x == "(50+500/2-window_w/2)", "horizontal expression must use final window_w");
    check(expression->y == "(50+300/2-window_h/2)", "vertical expression must use final window_h");

    const auto x = centeredCoordinate(parent.x, parent.width, monitor.x, 200);
    const auto y = centeredCoordinate(parent.y, parent.height, monitor.y, 100);
    check(x && std::abs(*x - 200) < 1e-9, "final child width was not centered against parent");
    check(y && std::abs(*y - 150) < 1e-9, "final child height was not centered against parent");
    const auto resizedX = centeredCoordinate(parent.x, parent.width, monitor.x, 300);
    check(resizedX && std::abs(*resizedX - 150) < 1e-9 && *resizedX != *x, "center position did not adapt to final child size");
    check(!centeredCoordinate(0, 10, 0, 0), "nonpositive child size accepted");
}

void replacementAndEmptyConfigurationAreAtomic() {
    RuleSet config;
    check(config.replace({rule("first", "child")}), "initial configuration rejected");
    check(config.replace({rule("second", "other")}), "replacement configuration rejected");
    check(config.rules().size() == 1 && config.rules()[0].parentClass == "second", "replacement retained stale rules");
    check(!config.replace({rule("", "invalid")}), "invalid replacement accepted");
    check(config.rules().size() == 1 && config.rules()[0].parentClass == "second", "invalid replacement changed active rules");
    check(config.replace({}), "empty configuration should disable placement");
    check(config.rules().empty(), "empty configuration did not clear active rules");
}

} // namespace

int main() {
    try {
        matchingUsesExactClassesAndInitialTitlePrefixes();
        declaredParentIsAuthoritative();
        focusedInferenceIsOptInAndRequiresVisibleMappedParent();
        unusableDeclaredParentDoesNotInfer();
        invalidGeometryIsRejectedAndExpressionUsesFinalChildSize();
        replacementAndEmptyConfigurationAreAtomic();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    return 0;
}
