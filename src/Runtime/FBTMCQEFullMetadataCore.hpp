#pragma once
// One-shot, exact-purpose metadata profile. No auth, identity, routing or callback edits.
#include <array>
#include <atomic>
#include <cstddef>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace fbt_qe_isolated {
using Pairs = std::vector<std::pair<std::string, std::string>>;

struct Field {
    const char *name;
    const char *value;
};
static const std::array<Field, 9> kFields = {{
    {"needs_name", "true"},
    {"skip_qe", "false"},
    {"with_experiments", "true"},
    {"with_params", "true"},
    {"with_groups", "true"},
    {"with_group_params", "true"},
    {"with_gatekeepers", "true"},
    {"with_universe_params", "true"},
    {"with_current_experiment_group", "true"}
}};

struct Result {
    bool applied = false;
    std::size_t changed = 0;
    const char *reason = "not_attempted";
};

// Atomic validation: never partially rewrite a malformed or ambiguous query.
inline Result apply(Pairs &copy) {
    Result result;
    std::array<std::size_t, kFields.size()> positions;
    for (std::size_t field = 0; field < kFields.size(); ++field) {
        std::size_t position = copy.size();
        for (std::size_t i = 0; i < copy.size(); ++i) {
            if (copy[i].first != kFields[field].name) continue;
            if (position != copy.size()) {
                result.reason = "duplicate_protocol_field";
                return result;
            }
            position = i;
        }
        if (position == copy.size()) {
            result.reason = "missing_protocol_field";
            return result;
        }
        const auto &value = copy[position].second;
        if (value != "true" && value != "false" && value != "0" && value != "1") {
            result.reason = "invalid_boolean_encoding";
            return result;
        }
        positions[field] = position;
    }
    for (std::size_t i = 0; i < kFields.size(); ++i) {
        auto &value = copy[positions[i]].second;
        if (value != kFields[i].value) {
            value = kFields[i].value;
            ++result.changed;
        }
    }
    result.applied = true;
    result.reason = "applied";
    return result;
}

// An armed profile applies to at most one POST QE-info fetch within 120 seconds.
// Unrelated fetches never consume it. Mutex guards the arm/cancel/consume race.
class OneShot {
    mutable std::mutex mutex_;
    bool armed_ = false;
    double deadline_ = 0;
public:
    void arm(double monotonicNow) {
        std::lock_guard<std::mutex> hold(mutex_);
        armed_ = true;
        deadline_ = monotonicNow + 120.0;
    }
    void cancel() {
        std::lock_guard<std::mutex> hold(mutex_);
        armed_ = false;
        deadline_ = 0;
    }
    bool pending(double monotonicNow) const {
        std::lock_guard<std::mutex> hold(mutex_);
        return armed_ && monotonicNow < deadline_;
    }
    bool consume(const std::string &method, const std::string &purpose, double now) {
        if (method != "POST" || purpose != "mobileconfig_qe_info") return false;
        std::lock_guard<std::mutex> hold(mutex_);
        bool selected = armed_ && now < deadline_;
        armed_ = false;
        deadline_ = 0;
        return selected;
    }
};
} // namespace fbt_qe_isolated
