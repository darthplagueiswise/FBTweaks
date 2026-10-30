#include "../src/Runtime/FBTMCQEFullProfile.hpp"
#include <cassert>
#include <string>
using fbt_mc_qe::Pairs;

int main() {
    Pairs incoming = {
      {"with_universe_params","false"},
      {"with_current_experiment_group","false"},
      {"with_only_current_experiment_group","false"},
      {"with_experiments","false"},
      {"with_params","false"},
      {"with_groups","false"},
      {"with_group_params","false"},
      {"with_gatekeepers","false"},
      {"needs_name","true"},
      {"skip_qe","true"},
      {"device_id","device_id"},
      {"queries","[\"4627:42\"]"},
      {"api_version","9"}
    };
    unsigned changed = fbt_mc_qe::apply(incoming);
    assert(changed == 8);
    assert(incoming.size() == 13);
    for (const auto &p:incoming) {
      if (p.first == "with_only_current_experiment_group" || p.first == "skip_qe") assert(p.second == "false");
      else if (p.first.find("with_") == 0 || p.first == "needs_name") assert(p.second == "true");
      else if (p.first == "device_id") assert(p.second == "device_id");
      else if (p.first == "queries") assert(p.second == "[\"4627:42\"]");
      else if (p.first == "api_version") assert(p.second == "9");
    }
    assert(fbt_mc_qe::apply(incoming) == 0);
    return 0;
}
