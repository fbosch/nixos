#include "position_store.hpp"
#include "position_config.hpp"
#include <cstdlib>
#include <cstdio>
#include <limits>
using namespace PositionStore;
static void require(bool condition) { if (!condition) { std::fputs("position store test failed\n", stderr); std::exit(1); } }
int main() {
    Records records{{{"nemo", "DP-1"}, {40.25, 200}}, {{"nemo", ""}, {-3, 20}}};
    require(parse(serialize(records)) == records);
    require(PositionConfig::denseKeys(2, {1, 2}));
    require(!PositionConfig::denseKeys(2, {1, 3}));
    require(!PositionConfig::denseKeys(2, {1}));
    require(!PositionConfig::denseKeys(2, {1, 1}));
    require(!PositionConfig::denseKeys(0, {3}));
    require(!PositionConfig::denseKeys(1, {1.5}));
    require(!parse("persistent-position-v2\n"));
    require(!parse("persistent-position-v1\n6e656d6f\t\tnan\t1\n"));
    require(!parse("persistent-position-v1\n6e656d6f\t\t1\t2\n6e656d6f\t\t3\t4\n"));
    require(!parse("persistent-position-v1\n6e656d6f\t\t1\t2\ntruncated"));
    require(!parse("persistent-position-v1\n6e656d6f\t\t1\n"));
    require(!parse("persistent-position-v1\n6e656d6f\t\t1\t\n"));
    require(!parse("persistent-position-v1\n6e656d6f\t\t\t2\n"));
    require(!parse("persistent-position-v1\n6e656d6f\t\t1\t2\t3\n"));
    require(!parse(std::string("persistent-position-v1\n") + std::string(1024 * 1024, 'x') + "\n"));
    require(!validPoint({std::numeric_limits<double>::infinity(), 2}));
    require((clamp({100, -20}, {10, 10}, {80, 90}, {30, 20}) == Point{60, 10}));
    require((clamp({200, 200}, {10, 10}, {80, 90}, {120, 120}) == Point{10, 10}));
}
