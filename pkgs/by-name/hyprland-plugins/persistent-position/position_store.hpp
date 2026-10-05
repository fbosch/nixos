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
    using Records = std::map<Key, Point>;

    inline bool validKey(std::string_view value, bool allowEmpty = false) {
        if (value.empty()) return allowEmpty;
        if (value.size() > 256) return false;
        return std::all_of(value.begin(), value.end(), [](unsigned char c) { return c >= 32 && c != 127; });
    }
    inline bool validPoint(Point p) {
        return std::isfinite(p.x) && std::isfinite(p.y) && std::abs(p.x) <= 1000000 && std::abs(p.y) <= 1000000;
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
        out << "persistent-position-v1\n";
        for (const auto& [key, point] : records)
            out << hex(key.selector) << '\t' << hex(key.monitor) << '\t' << point.x << '\t' << point.y << '\n';
        return out.str();
    }
    inline std::optional<Records> parse(std::string_view input) {
        if (input.size() > 1024 * 1024 || !input.starts_with("persistent-position-v1\n") || input.back() != '\n') return std::nullopt;
        input.remove_prefix(sizeof("persistent-position-v1\n") - 1);
        Records records;
        while (!input.empty()) {
            if (records.size() >= 4096) return std::nullopt;
            const auto end = input.find('\n');
            if (end == std::string_view::npos) return std::nullopt;
            const auto line = input.substr(0, end);
            const auto a = line.find('\t');
            const auto b = a == std::string_view::npos ? a : line.find('\t', a + 1);
            const auto c = b == std::string_view::npos ? b : line.find('\t', b + 1);
            if (a == std::string_view::npos || b == std::string_view::npos || c == std::string_view::npos ||
                a == 0 || c == b + 1 || c + 1 == line.size() ||
                line.find('\t', c + 1) != std::string_view::npos) return std::nullopt;
            if (a > 512 || b - a > 513 || line.size() > 1100) return std::nullopt;
            auto id = unhex(line.substr(0, a)), monitor = unhex(line.substr(a + 1, b - a - 1));
            if (!id || !monitor || !validKey(*id) || !validKey(*monitor, true)) return std::nullopt;
            Point point{};
            std::istringstream values(std::string(line.substr(b + 1, c - b - 1)) + " " + std::string(line.substr(c + 1)));
            values.imbue(std::locale::classic());
            if (!(values >> point.x >> point.y) || (values >> std::ws, !values.eof()) || !validPoint(point)) return std::nullopt;
            if (!records.emplace(Key{*id, *monitor}, point).second) return std::nullopt;
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
