#pragma once
#include <cmath>
#include <cstddef>
#include <vector>

namespace PositionConfig {
    inline bool denseKeys(size_t count, const std::vector<double>& keys) {
        if (keys.size() != count) return false;
        std::vector<bool> seen(count);
        for (double key : keys) {
            if (!std::isfinite(key) || key < 1 || key > count || std::floor(key) != key) return false;
            const auto index = static_cast<size_t>(key) - 1;
            if (seen[index]) return false;
            seen[index] = true;
        }
        return true;
    }
}
