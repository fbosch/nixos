#pragma once

#include <algorithm>
#include <compare>
#include <locale>
#include <limits>
#include <cmath>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace PositionStore {
    struct Key {
        std::string selector;
        std::string monitor; // Empty for a global selector.
        auto operator<=>(const Key&) const = default;
    };
    struct Point {
        double x;
        double y;
        bool operator==(const Point&) const = default;
    };
    struct Placement {
        std::string monitor;
        std::string corner; // Empty means free placement using Record::position.
        bool operator==(const Placement&) const = default;
    };
    inline bool validCorner(std::string_view corner) {
        return corner == "top-left" || corner == "top-right" || corner == "bottom-left" || corner == "bottom-right";
    }
    struct Record {
        std::optional<Point> position;
        std::optional<Point> size;
        std::optional<bool> windowed;
        std::optional<Placement> placement;
        bool operator==(const Record&) const = default;
    };
    using Records = std::map<Key, Record>;
    inline size_t mergeMissing(Records& current, const Records& legacy) {
        size_t added = 0;
        for (const auto& [key, incoming] : legacy) {
            auto& record = current[key];
            if (incoming.position && !record.position) { record.position = incoming.position; ++added; }
            if (incoming.size && !record.size) { record.size = incoming.size; ++added; }
            if (incoming.windowed && !record.windowed) { record.windowed = incoming.windowed; ++added; }
            if (incoming.placement && !record.placement) { record.placement = incoming.placement; ++added; }
        }
        return added;
    }

    inline bool validKey(std::string_view value, bool allowEmpty = false) {
        if (value.empty()) return allowEmpty;
        if (value.size() > 256) return false;
        return std::all_of(value.begin(), value.end(), [](unsigned char c) { return c >= 32 && c != 127; });
    }
    inline bool validPoint(Point p) {
        return std::isfinite(p.x) && std::isfinite(p.y) && std::abs(p.x) <= 1000000 && std::abs(p.y) <= 1000000;
    }
    inline bool validSize(Point size) {
        return validPoint(size) && size.x > 0 && size.y > 0;
    }
    inline std::string hex(std::string_view value) {
        constexpr char digits[] = "0123456789abcdef";
        std::string result;
        for (unsigned char c : value) {
            result += digits[c >> 4];
            result += digits[c & 15];
        }
        return result;
    }
    inline std::optional<std::string> unhex(std::string_view value) {
        if (value.size() % 2) return std::nullopt;
        std::string result;
        for (size_t i = 0; i < value.size(); i += 2) {
            auto digit = [](char c) -> int {
                if (c >= '0' && c <= '9') return c - '0';
                if (c >= 'a' && c <= 'f') return c - 'a' + 10;
                return -1;
            };
            const int a = digit(value[i]), b = digit(value[i + 1]);
            if (a < 0 || b < 0) return std::nullopt;
            result += static_cast<char>(a * 16 + b);
        }
        return result;
    }
    inline std::string serialize(const Records& records) {
        std::ostringstream out;
        out.imbue(std::locale::classic());
        out.precision(17);
        out << "persistent-position-v2\n";
        for (const auto& [key, record] : records) {
            out << hex(key.selector) << '\t' << hex(key.monitor);
            auto pair = [&out](const std::optional<Point>& value) {
                if (value) out << '\t' << value->x << '\t' << value->y;
                else out << "\t-\t-";
            };
            pair(record.position);
            pair(record.size);
            out << '\t' << (record.windowed ? (*record.windowed ? "1" : "0") : "-");
            out << '\t' << (record.placement ? hex(record.placement->monitor) : "-");
            out << '\t' << (record.placement ? (record.placement->corner.empty() ? "free" : record.placement->corner) : "-") << '\n';
        }
        return out.str();
    }
    inline std::optional<Records> parse(std::string_view input) {
        if (input.size() > 1024 * 1024 || input.empty() || input.back() != '\n') return std::nullopt;
        const bool v1 = input.starts_with("persistent-position-v1\n");
        if (!v1 && !input.starts_with("persistent-position-v2\n")) return std::nullopt;
        input.remove_prefix(sizeof("persistent-position-v2\n") - 1);
        Records records;
        while (!input.empty()) {
            if (records.size() >= 4096) return std::nullopt;
            const auto end = input.find('\n');
            if (end == std::string_view::npos) return std::nullopt;
            const auto line = input.substr(0, end);
            std::vector<std::string_view> fields;
            size_t start = 0;
            while (true) {
                const auto tab = line.find('\t', start);
                fields.push_back(line.substr(start, tab == std::string_view::npos ? tab : tab - start));
                if (tab == std::string_view::npos) break;
                start = tab + 1;
            }
            if (fields.size() != (v1 ? 4 : 9) || fields[0].empty() || fields[0].size() > 512 || fields[1].size() > 512 || line.size() > 1800) return std::nullopt;
            auto id = unhex(fields[0]), monitor = unhex(fields[1]);
            if (!id || !monitor || !validKey(*id) || !validKey(*monitor, true)) return std::nullopt;
            auto pair = [](std::string_view x, std::string_view y, bool size) -> std::optional<std::optional<Point>> {
                if (x == "-" && y == "-") return std::optional<Point>{};
                Point result{};
                std::istringstream values(std::string(x) + " " + std::string(y));
                values.imbue(std::locale::classic());
                if (!(values >> result.x >> result.y) || (values >> std::ws, !values.eof()) || !(size ? validSize(result) : validPoint(result))) return std::nullopt;
                return result;
            };
            auto position = pair(fields[2], fields[3], false);
            if (!position || (v1 && !*position)) return std::nullopt;
            Record record{*position, std::nullopt, std::nullopt};
            if (!v1) {
                auto size = pair(fields[4], fields[5], true);
                if (!size || (fields[6] != "-" && fields[6] != "0" && fields[6] != "1")) return std::nullopt;
                record.size = *size;
                if (fields[6] != "-") record.windowed = fields[6] == "1";
                if (fields[7] != "-" || fields[8] != "-") {
                    auto target = unhex(fields[7]);
                    if (!target || !validKey(*target) || (fields[8] != "free" && !validCorner(fields[8]))) return std::nullopt;
                    if (fields[8] == "free" && !record.position) return std::nullopt;
                    record.placement = Placement{*target, fields[8] == "free" ? "" : std::string(fields[8])};
                }
                if (!record.position && !record.size && !record.windowed && !record.placement) return std::nullopt;
            }
            if (!records.emplace(Key{*id, *monitor}, record).second) return std::nullopt;
            input.remove_prefix(end + 1);
        }
        return records;
    }
    inline Point clamp(Point saved, Point origin, Point extent, Point size) {
        return {
            std::clamp(saved.x, origin.x, std::max(origin.x, origin.x + extent.x - size.x)),
            std::clamp(saved.y, origin.y, std::max(origin.y, origin.y + extent.y - size.y)),
        };
    }
}
