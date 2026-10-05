#include "position_writer.hpp"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using namespace PositionStore;
using namespace PositionStorage;

static void require(bool condition) {
    if (!condition) { std::fputs("position storage test failed\n", stderr); std::exit(1); }
}
int main() {
    std::string templatePath = (fs::temp_directory_path() / "persistent-position-test.XXXXXX").string();
    std::vector<char> name(templatePath.begin(), templatePath.end());
    name.push_back('\0');
    const char* made = ::mkdtemp(name.data());
    require(made != nullptr);
    const fs::path base(made), root = base / "state", outside = base / "outside";
    fs::create_directories(root);
    fs::create_directories(outside);
    const fs::path file = root / "nested" / "positions";
    const fs::path escaped = root / "escape" / "positions";
    std::string error;
    Records records;
    require(validatePath(file, root));
    require(!validatePath(root / "../outside/positions", root));
    require(!validatePath(outside / "positions", root));
    require(load(file, records, error, true) && records.empty());
    Records first{{{"nemo", "DP-1"}, {12, 40}}};
    Records second{{{"nemo", "DP-1"}, {90, 90}}};
    Records imported{{{"nemo", "DP-1"}, {999, 999}}, {{"nemo", "HDMI-1"}, {33, 44}}};
    Records merged = first;
    require(mergeMissing(merged, imported) == 1);
    require(merged.at({"nemo", "DP-1"}) == Point{12, 40});
    require(merged.at({"nemo", "HDMI-1"}) == Point{33, 44});
    require(mergeMissing(merged, imported) == 0);
    require(writeAtomic(file, first, error));
    require(load(file, records, error) && records == first);
    fs::create_directory_symlink(outside, root / "escape");
    fs::create_directory_symlink(outside, base / "aliased-state");
    require(validatePath(escaped, root)); // Lexical containment alone is insufficient.
    require(!load(base / "aliased-state" / "positions", records, error, true));
    require(!load(escaped, records, error));
    require(records == first);
    require(!writeAtomic(escaped, second, error));
    require(!fs::exists(outside / "positions"));
    fs::create_symlink(file, root / "state-link");
    require(!load(root / "state-link", records, error));
    require(!writeAtomic(root / "state-link", second, error));

    const fs::path nextFile = root / "nested" / "new-positions";
    {
        Writer writer;
        writer.start();
        writer.enqueue(file.string(), first);
        writer.enqueue(file.string(), second);
        require(writer.drain(error));
        require(load(file, records, error) && records == second);
        writer.enqueue(nextFile.string(), first);
        require(writer.drain(error));
        require(load(file, records, error) && records == second);
        require(load(nextFile, records, error) && records == first);
        writer.enqueue(nextFile.string(), second);
        writer.stop(); // Joining drains a pending latest snapshot without compositor callbacks.
    }
    require(load(nextFile, records, error) && records == second);
    {
        std::ofstream corrupt(file, std::ios::binary | std::ios::trunc);
        corrupt << "unsupported-state\n";
    }
    require(!load(file, records, error));
    require(!writeAtomic(file, second, error));
    std::ifstream preserved(file);
    std::string contents;
    std::getline(preserved, contents);
    require(contents == "unsupported-state");
    fs::remove_all(base);
}
