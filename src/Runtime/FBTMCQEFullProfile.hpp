#ifndef FBT_MC_QE_FULL_PROFILE_HPP
#define FBT_MC_QE_FULL_PROFILE_HPP
#include <string>
#include <utility>
#include <vector>

// One explicit user-selected experiment, never the native name-only default.
// The caller owns authentication and identity. In particular, this function
// MUST NOT modify device_id, queries, routing or opaque hash fields.
namespace fbt_mc_qe {
using Pairs = std::vector<std::pair<std::string,std::string>>;
inline unsigned apply(Pairs &pairs) {
    unsigned changed = 0;
    for (auto &pair : pairs) {
        const std::string &name = pair.first;
        if (name == "with_only_current_experiment_group" || name == "skip_qe") {
            if (pair.second != "false") { pair.second = "false"; ++changed; }
        } else if (name == "needs_name" || name == "with_universe_params" ||
                   name == "with_current_experiment_group" || name == "with_experiments" ||
                   name == "with_params" || name == "with_groups" ||
                   name == "with_group_params" || name == "with_gatekeepers") {
            if (pair.second != "true") { pair.second = "true"; ++changed; }
        }
    }
    return changed;
}
}
#endif
