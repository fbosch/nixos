#include "position_store.hpp"
#include "position_config.hpp"
#include <cstdlib>
#include <cstdio>
#include <limits>
using namespace PositionStore;
static void require(bool condition) { if (!condition) { std::fputs("position store test failed\n", stderr); std::exit(1); } }
int main() {
    Records records{{{"nemo", "DP-1"}, {Point{40.25, 200}, Point{800, 600}, true}},
                    {{"nemo", ""}, {Point{-3, 20}, std::nullopt, std::nullopt}}};
    require(parse(serialize(records)) == records);
    const auto v1 = parse("persistent-position-v1\n6e656d6f\t\t1\t2\n");
    require(v1 && v1->at({"nemo", ""}).position == Point{1, 2});
    require(!v1->at({"nemo", ""}).size);
    Records incoming{{{"nemo", ""}, {Point{999, 999}, Point{640, 480}, false}}};
    auto merged = *v1;
    require(mergeMissing(merged, incoming) == 2);
    require(merged.at({"nemo", ""}).position == Point{1, 2});
    require(merged.at({"nemo", ""}).size == Point{640, 480});
    require(merged.at({"nemo", ""}).windowed == false);
    require(mergeMissing(merged, incoming) == 0);
    for (const char* corner : {"top-left", "top-right", "bottom-left", "bottom-right"}) {
        Records pip{{{"pip", ""}, {std::nullopt, Point{400, 225}, std::nullopt, Placement{"DP-2", corner}}}};
        require(parse(serialize(pip)) == pip);
        pip.at({"pip", ""}) = Record{Point{42, 73}, std::nullopt, std::nullopt, Placement{"HDMI-A-2", ""}};
        require(parse(serialize(pip)) == pip);
    }
    require(!parse("persistent-position-v2\n706970\t\t-\t-\t-\t-\t-\t44502d32\tfree\n"));
    require(!parse("persistent-position-v2\n706970\t\t-\t-\t-\t-\t-\t44502d32\tnowhere\n"));
    require(!parse("persistent-position-v2\n706970\t\t1\t2\t0\t100\t-\t-\t-\n"));
    require(PositionConfig::denseKeys(2, {1, 2}));
    require(!PositionConfig::denseKeys(2, {1, 3}));
    require(!parse("persistent-position-v3\n"));
    require(!parse("persistent-position-v2\n6e656d6f\t\t1\t2\t0\t4\t1\n"));
    require(!parse("persistent-position-v2\n6e656d6f\t\t1\t2\t-\t4\t1\n"));
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
