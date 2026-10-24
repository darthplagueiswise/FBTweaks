#ifndef FBT_QE_REQUEST_OPTIONS_CORE_HPP
#define FBT_QE_REQUEST_OPTIONS_CORE_HPP
#include <array>
#include <string>
#include <utility>
#include <vector>

namespace fbt_qe_options {
using Pairs = std::vector<std::pair<std::string, std::string>>;
inline const std::array<const char *, 10> &keys() {
    static const std::array<const char *, 10> names = {{
        "with_universe_params", "with_current_experiment_group",
        "with_only_current_experiment_group", "with_experiments", "with_params",
        "with_groups", "with_group_params", "with_gatekeepers", "needs_name", "skip_qe"}};
    return names;
}
struct Profile {
    bool enabled = false;
    bool allQE = true;
    std::array<bool, 10> values = {{false,false,false,false,false,false,false,false,true,true}};
};
// Each scope owns an immutable snapshot. No global "next QE" association.
class Scope {
    Profile snapshot_;
    const Profile *previous_;
    static const Profile *&slot() {
        static thread_local const Profile *value = nullptr;
        return value;
    }
public:
    explicit Scope(const Profile &profile) : snapshot_(profile), previous_(slot()) { slot() = &snapshot_; }
    ~Scope() { slot() = previous_; }
    Scope(const Scope &) = delete;
    Scope &operator=(const Scope &) = delete;
    static const Profile *current() { return slot(); }
};
enum class Result { OutsideAction, Disabled, OtherRequest, SchemaMismatch, Applied };
inline const char *label(Result result) {
    switch (result) {
        case Result::Applied: return "applied";
        case Result::Disabled: return "disabled";
        case Result::OtherRequest: return "other_request";
        case Result::SchemaMismatch: return "schema_mismatch_native_preserved";
        default: return "outside_selected_scope";
    }
}
inline Result applyCurrent(const std::string &method, const std::string &purpose, Pairs &pairs,
        const Profile &fallback = Profile()) {
    const auto profile = Scope::current() ? Scope::current() : fallback.allQE && fallback.enabled ? &fallback : nullptr;
    if (!profile) return Result::OutsideAction;
    if (!profile->enabled) return Result::Disabled;
    if (method != "POST" || purpose != "mobileconfig_qe_info") return Result::OtherRequest;
    std::array<size_t, 10> positions = {{}};
    // Reject the entire edit before changing any value if the native schema drifts.
    for (size_t i = 0; i < keys().size(); ++i) {
        size_t count = 0;
        for (size_t j = 0; j < pairs.size(); ++j)
            if (pairs[j].first == keys()[i]) { ++count; positions[i] = j; }
        if (count != 1) return Result::SchemaMismatch;
    }
    // Copy/swap also preserves the original on allocation failure.
    Pairs edited(pairs);
    for (size_t i = 0; i < positions.size(); ++i)
        edited[positions[i]].second = profile->values[i] ? "true" : "false";
    pairs.swap(edited);
    return Result::Applied;
}
Profile sessionProfile();
}
#endif
