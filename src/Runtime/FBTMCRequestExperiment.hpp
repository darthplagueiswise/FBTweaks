#pragma once
#include <algorithm>
#include <mutex>
#include <string>
#include <utility>
#include <vector>
namespace fbt_mc_probe {
using Pairs = std::vector<std::pair<std::string, std::string>>;
struct Selection { int mode = -1; std::string id; };
class OneShot {
    std::mutex mutex;
    Selection next;
    double deadline = 0;
public:
    void arm(bool employee, const std::string &id, double now) {
        std::lock_guard<std::mutex> guard(mutex);
        next.mode = employee ? 1 : 0; next.id = id; deadline = now + 120;
    }
    void cancel() { std::lock_guard<std::mutex> guard(mutex); next = Selection(); deadline = 0; }
    Selection pending(double now) {
        std::lock_guard<std::mutex> guard(mutex);
        return now < deadline ? next : Selection();
    }
    Selection consume(const std::string &method, const std::string &purpose, double now) {
        if (method != "POST" || purpose != "mobileconfig_qe_info") return Selection();
        std::lock_guard<std::mutex> guard(mutex);
        Selection result = now < deadline ? next : Selection();
        next = Selection(); deadline = 0;
        return result;
    }
};
// Deliberately limited to a nine-field protocol profile. Identity, tokens,
 // queries, authentication and routing are neither inspected nor changed.
struct MetadataResult {
    bool applied = false;
    std::size_t changed = 0;
    std::string reason;
};
inline MetadataResult applyFullMetadata(Pairs &copy) {
    static const std::pair<const char *, const char *> desired[] = {
        {"needs_name", "true"},
        {"skip_qe", "false"},
        {"with_experiments", "true"},
        {"with_params", "true"},
        {"with_groups", "true"},
        {"with_group_params", "true"},
        {"with_gatekeepers", "true"},
        {"with_universe_params", "true"},
        {"with_current_experiment_group", "true"}
    };
    MetadataResult result;
    std::vector<std::size_t> positions;
    for (const auto &field : desired) {
        std::size_t found = copy.size();
        for (std::size_t i = 0; i < copy.size(); ++i) {
            if (copy[i].first != field.first) continue;
            if (found != copy.size()) {
                result.reason = "duplicate_protocol_field";
                return result;
            }
            found = i;
        }
        if (found == copy.size()) {
            result.reason = "missing_protocol_field";
            return result;
        }
        const std::string &value = copy[found].second;
        if (value != "true" && value != "false" && value != "0" && value != "1") {
            result.reason = "invalid_boolean_encoding";
            return result;
        }
        positions.push_back(found);
    }
    for (std::size_t i = 0; i < positions.size(); ++i) {
        if (copy[positions[i]].second != desired[i].second) {
            copy[positions[i]].second = desired[i].second;
            ++result.changed;
        }
    }
    result.applied = true;
    result.reason = "applied";
    return result;
}
inline bool append(Pairs &copy) {
    if (std::any_of(copy.begin(), copy.end(), [](const Pairs::value_type &p) { return p.first == "is_employee"; })) return false;
    copy.emplace_back("is_employee", "true");
    return true;
}
}
