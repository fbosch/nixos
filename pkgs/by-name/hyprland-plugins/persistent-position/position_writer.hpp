#pragma once

#include "position_storage.hpp"

#include <cstdint>
#include <condition_variable>
#include <cstdio>
#include <exception>
#include <mutex>
#include <optional>
#include <thread>

namespace PositionStorage {
    struct Snapshot {
        std::string path;
        Records records;
        uint64_t generation;
    };

    class Writer {
      public:
        Writer() = default;
        ~Writer() { stop(); }
        Writer(const Writer&) = delete;
        Writer& operator=(const Writer&) = delete;

        void start() {
            m_thread = std::thread([this] { run(); });
        }
        bool persisted(uint64_t generation) {
            std::lock_guard lock(m_mutex);
            return m_persisted == generation;
        }
        // Generations identify immutable snapshots and must increase across path/policy changes.
        void enqueue(std::string path, const Records& records, uint64_t generation) {
            {
                std::lock_guard lock(m_mutex);
                if (m_persisted == generation || m_writingGeneration == generation ||
                    (m_pending && m_pending->generation == generation)) return;
                m_pending = Snapshot{std::move(path), records, generation};
            }
            m_cv.notify_one();
        }
        bool drain(std::string& error) {
            std::unique_lock lock(m_mutex);
            m_cv.wait(lock, [this] { return !m_pending && !m_writing; });
            error = m_error;
            return error.empty();
        }
        void stop() {
            if (!m_thread.joinable()) return;
            {
                std::lock_guard lock(m_mutex);
                m_stopping = true;
            }
            m_cv.notify_one();
            m_thread.join();
        }

      private:
        void run() {
            while (true) {
                std::optional<Snapshot> snapshot;
                {
                    std::unique_lock lock(m_mutex);
                    m_cv.wait(lock, [this] { return m_stopping || m_pending.has_value(); });
                    if (!m_pending) return;
                    snapshot = std::move(m_pending);
                    m_pending.reset();
                    m_writing = true;
                    m_writingGeneration = snapshot->generation;
                }
                std::string error;
                try {
                    if (!writeAtomic(snapshot->path, snapshot->records, error) && error.empty())
                        error = "state write failed";
                } catch (const std::exception& e) {
                    error = e.what();
                }
                if (!error.empty()) std::fprintf(stderr, "persistent-position: %s\n", error.c_str());
                {
                    std::lock_guard lock(m_mutex);
                    if (error.empty()) m_persisted = snapshot->generation;
                    m_writingGeneration.reset();
                    m_error = std::move(error);
                    m_writing = false;
                }
                m_cv.notify_all();
            }
        }
        std::mutex m_mutex;
        std::condition_variable m_cv;
        std::optional<Snapshot> m_pending;
        std::optional<uint64_t> m_writingGeneration;
        std::optional<uint64_t> m_persisted;
        std::thread m_thread;
        bool m_writing = false;
        bool m_stopping = false;
        std::string m_error;
    };
}
