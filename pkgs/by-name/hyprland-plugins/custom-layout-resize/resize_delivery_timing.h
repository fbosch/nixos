#pragma once

#include <algorithm>
#include <chrono>
#include <cmath>

namespace CustomLayoutResize {
using Clock = std::chrono::steady_clock;

inline int pointerInterval(double refresh) {
  return std::clamp(
      static_cast<int>(std::lround(1000.0 / (refresh > 0 ? refresh : 60.0))), 6,
      17);
}

inline Clock::duration deliveryDelay(Clock::time_point now,
                                     Clock::time_point origin, int intervalMs) {
  return std::max(origin + std::chrono::milliseconds(2 * intervalMs) - now,
                  Clock::duration(std::chrono::milliseconds(1)));
}
} // namespace CustomLayoutResize
