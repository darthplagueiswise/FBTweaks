#include <cassert>
#include <stdexcept>
#include <thread>
#if __has_include("../src/Runtime/FBTQERequestOptionsCore.hpp")
#include "../src/Runtime/FBTQERequestOptionsCore.hpp"
#else
int main() { assert(!"Force Name options feature missing"); }
#endif
#ifdef FBT_QE_REQUEST_OPTIONS_CORE_HPP
using namespace fbt_qe_options;
static Pairs fixture() {
    return {{"with_universe_params","false"},{"with_current_experiment_group","false"},
        {"with_only_current_experiment_group","false"},{"with_experiments","false"},
        {"with_params","false"},{"with_groups","false"},{"with_group_params","false"},
        {"with_gatekeepers","false"},{"needs_name","true"},{"skip_qe","true"},
        {"queries","[private fixture]"},{"access_token","credential fixture"},{"api_version","9"}};
}
int main() {
    Profile p; p.enabled = true;
    p.values = {{true,false,true,false,true,false,true,false,false,false}};
    const auto native = fixture(); auto out = native;
    assert(applyCurrent("POST", "mobileconfig_qe_info", out) == Result::OutsideAction);
    assert(out == native);
    Profile global; global.enabled = true; global.allQE = true;
    global.values.fill(true); global.values[9] = false;
    out = native;
    assert(applyCurrent("POST", "mobileconfig_qe_info", out, global) == Result::Applied);
    assert(out[0].second == "true" && out[7].second == "true" && out[9].second == "false");
    out = native; global.allQE = false;
    assert(applyCurrent("POST", "mobileconfig_qe_info", out, global) == Result::OutsideAction);
    assert(out == native);
    {
        Scope scope(p);
        p.values.fill(true); // The in-flight snapshot must remain unchanged.
        assert(applyCurrent("POST", "mobileconfig", out) == Result::OtherRequest);
        assert(applyCurrent("GET", "mobileconfig_qe_info", out) == Result::OtherRequest);
        assert(out == native);
        std::thread other([&] { auto x = native;
            assert(applyCurrent("POST", "mobileconfig_qe_info", x) == Result::OutsideAction);
            assert(x == native); }); other.join();
        assert(applyCurrent("POST", "mobileconfig_qe_info", out) == Result::Applied);
        const Pairs expected = {{"with_universe_params","true"},{"with_current_experiment_group","false"},
            {"with_only_current_experiment_group","true"},{"with_experiments","false"},
            {"with_params","true"},{"with_groups","false"},{"with_group_params","true"},
            {"with_gatekeepers","false"},{"needs_name","false"},{"skip_qe","false"},
            {"queries","[private fixture]"},{"access_token","credential fixture"},{"api_version","9"}};
        assert(out == expected); assert(native == fixture());
        Profile disabled;
        { Scope nested(disabled); out = native;
          assert(applyCurrent("POST", "mobileconfig_qe_info", out) == Result::Disabled);
          assert(out == native); }
        try { Scope nested(disabled); throw std::runtime_error("test unwind"); } catch (...) {}
        out = native;
        assert(applyCurrent("POST", "mobileconfig_qe_info", out) == Result::Applied);
        auto missing = native; missing.erase(missing.begin()); const auto before = missing;
        assert(applyCurrent("POST", "mobileconfig_qe_info", missing) == Result::SchemaMismatch);
        assert(missing == before);
        auto duplicate = native; duplicate.push_back({"skip_qe","false"}); const auto dupBefore = duplicate;
        assert(applyCurrent("POST", "mobileconfig_qe_info", duplicate) == Result::SchemaMismatch);
        assert(duplicate == dupBefore);
    }
    out = native;
    assert(applyCurrent("POST", "mobileconfig_qe_info", out) == Result::OutsideAction);
    return 0;
}
#endif
