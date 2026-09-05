#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <numbers>

using std::clamp;
using std::sin;

#include "gradient.glsl"

// This exercises the production scalar shader source as CPU arithmetic; it is not GPU validation.
namespace {

struct Coordinate {
    float x;
    float y;
};

bool check(bool condition, const char* message, int length, float angle, Coordinate coordinate) {
    if (condition)
        return true;

    std::cerr << message << ": length=" << length << ", angle=" << angle << ", coordinate=(" << coordinate.x << ", " << coordinate.y << ")\n";
    return false;
}

} // namespace

int main() {
    constexpr std::array coordinates{
        Coordinate{0.0F, 0.0F},
        Coordinate{1.0F, 0.0F},
        Coordinate{0.0F, 1.0F},
        Coordinate{1.0F, 1.0F},
        Coordinate{0.5F, 0.0F},
        Coordinate{0.0F, 0.5F},
        Coordinate{1.0F, 0.5F},
        Coordinate{0.5F, 1.0F},
        Coordinate{0.5F, 0.5F},
    };
    // Match CPU angle normalization independently of the shader's constants.
    constexpr float fullTurn = 2.0F * std::numbers::pi_v<float>;
    const std::array angles{
        0.0F,
        fullTurn * 0.25F - 1.0e-6F,
        fullTurn * 0.25F,
        fullTurn * 0.25F + 1.0e-6F,
        fullTurn * 0.5F - 1.0e-6F,
        fullTurn * 0.5F,
        fullTurn * 0.5F + 1.0e-6F,
        fullTurn * 0.75F - 1.0e-6F,
        fullTurn * 0.75F,
        fullTurn * 0.75F + 1.0e-6F,
        fullTurn - 1.0e-6F,
        fullTurn,
    };

    bool passed = true;
    for (int length = 2; length <= 10; ++length) {
        for (const auto angle : angles) {
            for (const auto coordinate : coordinates) {
                const float progress = gradientProgress(coordinate.x, coordinate.y, angle, length);
                if (!check(std::isfinite(progress), "progress is not finite", length, angle, coordinate)) {
                    passed = false;
                    continue;
                }
                passed &= check(progress >= 0.0F && progress <= static_cast<float>(length - 1), "progress is out of bounds", length, angle, coordinate);

                const int lower = static_cast<int>(std::floor(progress));
                const int upper = std::min(lower + 1, length - 1);
                passed &= check(lower >= 0 && lower < length, "lower index is out of bounds", length, angle, coordinate);
                passed &= check(upper >= 0 && upper < length, "upper index is out of bounds", length, angle, coordinate);
            }
        }
        for (const auto coordinate : coordinates) {
            const std::array expectedFractions{coordinate.x, coordinate.y, 1.0F - coordinate.x, 1.0F - coordinate.y, coordinate.x};
            for (std::size_t quadrant = 0; quadrant < expectedFractions.size(); ++quadrant) {
                const float angle = fullTurn * static_cast<float>(quadrant) / 4.0F;
                const float progress = gradientProgress(coordinate.x, coordinate.y, angle, length);
                const float expected = expectedFractions[quadrant] * static_cast<float>(length - 1);
                passed &= check(std::abs(progress - expected) < 1.0e-5F, "gradient direction changed", length, angle, coordinate);
            }
        }
    }

    return passed ? 0 : 1;
}
