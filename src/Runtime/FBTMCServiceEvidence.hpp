#pragma once
#include <cstdint>
#include <limits>
#include <mutex>
#include <unordered_map>

namespace fbt_mc_evidence {
// Pointer keys stay in memory. Numbers describe observations, never account IDs
// or proof of object lifetime/session authorization. IDs are not reused on reset
// because an earlier native completion can still arrive after a new capture.
class ServiceRegistry {
    std::mutex mutex_;
    std::unordered_map<std::uintptr_t, std::uint64_t> identities_;
    const std::size_t limit_;
    std::uint64_t next_ = 0;
public:
    explicit ServiceRegistry(std::size_t limit = 256) : limit_(limit) {}
    std::uint64_t observe(std::uintptr_t pointer) noexcept {
        try {
            if (!pointer) return 0;
            std::lock_guard<std::mutex> lock(mutex_);
            auto found = identities_.find(pointer);
            if (found != identities_.end()) return found->second;
            if (identities_.size() >= limit_ || next_ == std::numeric_limits<std::uint64_t>::max()) return 0;
            return identities_[pointer] = ++next_;
        } catch (...) { return 0; } // Diagnostics must never fail the native fetch.
    }
    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        identities_.clear();
    }
};
enum class Relation { Unknown, SameObservedService, DifferentObservedServices };
inline Relation compare(std::uint64_t a, std::uint64_t b) {
    return !a || !b ? Relation::Unknown : a == b ?
        Relation::SameObservedService : Relation::DifferentObservedServices;
}
}
