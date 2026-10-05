#pragma once

#include "position_store.hpp"

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <string>
#include <utility>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

namespace PositionStorage {
    namespace fs = std::filesystem;
    using PositionStore::Records;

    struct FD {
        int value = -1;
        explicit FD(int fd = -1) : value(fd) {}
        ~FD() { if (value >= 0) ::close(value); }
        FD(const FD&) = delete;
        FD& operator=(const FD&) = delete;
        FD(FD&& other) noexcept : value(std::exchange(other.value, -1)) {}
        FD& operator=(FD&& other) noexcept { if (this != &other) { if (value >= 0) ::close(value); value = std::exchange(other.value, -1); } return *this; }
        explicit operator bool() const { return value >= 0; }
    };

    inline bool validatePath(const fs::path& path, const fs::path& root) {
        if (!path.is_absolute() || !root.is_absolute() || path.string().size() > 4096 || root.string().size() > 4096 ||
            path.filename().empty() || path.filename().string().size() > 128) return false;
        for (const auto& component : path)
            if (component == "." || component == "..") return false;
        for (const auto& component : root)
            if (component == "." || component == "..") return false;
        const auto relative = path.lexically_relative(root);
        return !relative.empty() && relative != "." && *relative.begin() != "..";
    }

    inline FD openParent(const fs::path& path, bool create, std::string& error) {
        FD current(::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
        if (!current) { error = std::strerror(errno); return FD{}; }
        for (const auto& component : path.parent_path().relative_path()) {
            const auto name = component.string();
            int next = ::openat(current.value, name.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (next < 0 && create && errno == ENOENT) {
                if (::mkdirat(current.value, name.c_str(), 0700) < 0) {
                    if (errno != EEXIST) { error = std::strerror(errno); return FD{}; }
                } else if (::fsync(current.value) < 0) {
                    error = std::strerror(errno); return FD{};
                }
                next = ::openat(current.value, name.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            }
            if (next < 0) { error = std::strerror(errno); return FD{}; }
            current = FD(next);
        }
        return current;
    }

    inline bool load(const fs::path& path, Records& records, std::string& error, bool createParent = false) {
        FD dir = openParent(path, createParent, error);
        if (!dir) return false;
        FD file(::openat(dir.value, path.filename().c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC));
        if (!file && errno == ENOENT) { records.clear(); return true; }
        if (!file) { error = std::strerror(errno); return false; }
        struct stat info{};
        if (::fstat(file.value, &info) < 0 || !S_ISREG(info.st_mode) || info.st_size < 0 || info.st_size > 1024 * 1024) {
            error = "state is not a bounded regular file"; return false;
        }
        std::string text;
        char buffer[4096];
        while (true) {
            const auto n = ::read(file.value, buffer, sizeof(buffer));
            if (n < 0 && errno == EINTR) continue;
            if (n < 0) { error = std::strerror(errno); return false; }
            if (n == 0) break;
            if (text.size() + static_cast<size_t>(n) > 1024 * 1024) { error = "state exceeds size limit"; return false; }
            text.append(buffer, static_cast<size_t>(n));
        }
        auto parsed = PositionStore::parse(text);
        if (!parsed) { error = "invalid or unsupported state; original file preserved"; return false; }
        records = std::move(*parsed);
        return true;
    }

    inline bool writeAtomic(const fs::path& path, const Records& records, std::string& error) {
        Records previous;
        if (!load(path, previous, error)) return false;
        FD dir = openParent(path, false, error);
        if (!dir) return false;
        const auto data = PositionStore::serialize(records);
        if (data.size() > 1024 * 1024) { error = "state exceeds size limit"; return false; }
        FD old(::openat(dir.value, path.filename().c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC));
        if (!old && errno != ENOENT) { error = std::strerror(errno); return false; }
        char header[sizeof("persistent-position-v1\n") - 1]{};
        if (old) {
            struct stat info{};
            if (::fstat(old.value, &info) < 0 || !S_ISREG(info.st_mode)) { error = "state is not a regular file"; return false; }
            const auto n = ::read(old.value, header, sizeof(header));
            if (n < 0) { error = std::strerror(errno); return false; }
            if (n == sizeof(header) && std::string_view(header, sizeof(header)) == "persistent-position-v1\n") {
                // Preserve the original inode before upgrading; a failed rename leaves v1 in place.
                const auto backup = path.filename().string() + ".v1.bak";
                if (::linkat(dir.value, path.filename().c_str(), dir.value, backup.c_str(), 0) < 0) {
                    struct stat preserved{};
                    if (errno != EEXIST || ::fstatat(dir.value, backup.c_str(), &preserved, AT_SYMLINK_NOFOLLOW) < 0 ||
                        !S_ISREG(preserved.st_mode) || preserved.st_dev != info.st_dev || preserved.st_ino != info.st_ino) {
                        error = "cannot preserve v1 backup: existing backup differs or is unsafe"; return false;
                    }
                }
                if (::fsync(dir.value) < 0) { error = std::strerror(errno); return false; }
            }
        }
        static std::atomic<uint64_t> sequence = 0;
        std::string temporary;
        FD file;
        for (int i = 0; i < 16 && !file; ++i) {
            temporary = ".persistent-position-" + std::to_string(::getpid()) + "-" +
                std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) + "-" +
                std::to_string(sequence.fetch_add(1, std::memory_order_relaxed));
            file = FD(::openat(dir.value, temporary.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
            if (!file && errno != EEXIST) break;
        }
        if (!file) { error = std::strerror(errno); return false; }
        bool ok = true;
        size_t offset = 0;
        while (offset < data.size()) {
            const auto n = ::write(file.value, data.data() + offset, data.size() - offset);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) { ok = false; break; }
            offset += static_cast<size_t>(n);
        }
        if (ok) ok = ::fsync(file.value) == 0;
        if (ok) ok = ::renameat(dir.value, temporary.c_str(), dir.value, path.filename().c_str()) == 0;
        if (!ok) { error = std::strerror(errno); ::unlinkat(dir.value, temporary.c_str(), 0); return false; }
        if (::fsync(dir.value) < 0) { error = std::strerror(errno); return false; }
        return true;
    }
}
