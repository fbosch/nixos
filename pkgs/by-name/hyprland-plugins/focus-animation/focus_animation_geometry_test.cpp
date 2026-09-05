#include "focus_animation_geometry.h"

#include <iostream>

namespace {

    struct FakeAnimatedVariable {
        float value_;
        float goal_;
        bool  animated;

        bool isBeingAnimated() const noexcept {
            return animated;
        }

        float& value() noexcept {
            return value_;
        }

        float goal() const noexcept {
            return goal_;
        }
    };

    bool check(bool condition, const char* message) {
        if (condition)
            return true;

        std::cerr << message << '\n';
        return false;
    }

} // namespace

int main() {
    bool passed = true;

    {
        FakeAnimatedVariable position{12.F, 20.F, true};
        FakeAnimatedVariable size{96.F, 100.F, false};
        const auto geometry = focus_animation::inspectGeometry(&position, &size);
        geometry.restoreInactive();
        passed &= check(geometry.hasNativeAnimation(), "position takeover was not detected");
        passed &= check(position.value_ == 12.F, "active position was overwritten");
        passed &= check(size.value_ == 100.F, "inactive size was not restored");
    }

    {
        FakeAnimatedVariable position{18.F, 20.F, false};
        FakeAnimatedVariable size{94.F, 100.F, true};
        const auto geometry = focus_animation::inspectGeometry(&position, &size);
        geometry.restoreInactive();
        passed &= check(geometry.hasNativeAnimation(), "size takeover was not detected");
        passed &= check(position.value_ == 20.F, "inactive position was not restored");
        passed &= check(size.value_ == 94.F, "active size was overwritten");
    }

    {
        FakeAnimatedVariable position{12.F, 20.F, true};
        FakeAnimatedVariable size{94.F, 100.F, true};
        const auto geometry = focus_animation::inspectGeometry(&position, &size);
        geometry.restoreInactive();
        passed &= check(geometry.hasNativeAnimation(), "combined takeover was not detected");
        passed &= check(position.value_ == 12.F, "active position was overwritten");
        passed &= check(size.value_ == 94.F, "active size was overwritten");
    }

    {
        FakeAnimatedVariable position{18.F, 20.F, false};
        FakeAnimatedVariable size{96.F, 100.F, false};
        const auto geometry = focus_animation::inspectGeometry(&position, &size);
        geometry.restoreInactive();
        passed &= check(!geometry.hasNativeAnimation(), "normal restoration was treated as takeover");
        passed &= check(position.value_ == 20.F, "position was not restored normally");
        passed &= check(size.value_ == 100.F, "size was not restored normally");
    }

    return passed ? 0 : 1;
}
