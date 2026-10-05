#pragma once

#include "position_storage.hpp"

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
        void enqueue(std::string path, const Records& records) {
            Snapshot snapshot{std::move(path), records};
            {
                std::lock_guard lock(m_mutex);
                m_pending = std::move(snapshot);
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
                    m_error = std::move(error);
                    m_writing = false;
                }
                m_cv.notify_all();
            }
        }
        std::mutex m_mutex;
        std::condition_variable m_cv;
        std::optional<Snapshot> m_pending;
        std::thread m_thread;
        bool m_writing = false;
        bool m_stopping = false;
        std::string m_error;
    };
}
