#include "resize_delivery_timing.h"

#include <iostream>
#include <stdexcept>

using namespace std::chrono_literals;
using CustomLayoutResize::Clock;

void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

int main() {
  const auto zero = Clock::time_point{};
  require(CustomLayoutResize::pointerInterval(60) == 17,
          "60 Hz rounded interval");
  require(CustomLayoutResize::pointerInterval(144) == 7,
          "144 Hz rounded interval");
  require(CustomLayoutResize::pointerInterval(240) == 6,
          "240 Hz minimum interval");
  require(CustomLayoutResize::pointerInterval(30) == 17,
          "30 Hz maximum interval");
  require(CustomLayoutResize::pointerInterval(0) == 17,
          "missing refresh defaults to 60 Hz");
  require(CustomLayoutResize::deliveryDelay(zero, zero, 17) == 34ms,
          "60 Hz deadline");
  require(CustomLayoutResize::deliveryDelay(zero, zero, 7) == 14ms,
          "144 Hz deadline");
  require(CustomLayoutResize::deliveryDelay(zero, zero, 6) == 12ms,
          "240 Hz deadline");
  require(CustomLayoutResize::deliveryDelay(zero + 20ms, zero, 17) == 14ms,
          "new motion must not postpone the batch origin");
  require(CustomLayoutResize::deliveryDelay(zero + 33ms, zero, 17) == 1ms,
          "one millisecond remains before deadline");
  require(CustomLayoutResize::deliveryDelay(zero + 50ms, zero, 17) == 1ms,
          "expired deadline schedules promptly");
  require(CustomLayoutResize::deliveryDelay(zero + 50ms, zero + 40ms, 17) ==
              24ms,
          "a completed emission starts the next deadline");
  std::cout << "12 resize-delivery timing checks passed\n";
}
