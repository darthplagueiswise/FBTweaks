#include "../src/Runtime/FBTMCRequestExperiment.hpp"
#include <atomic>
#include <cassert>
#include <iostream>
#include <thread>
int main() {
    using namespace fbt_mc_probe;
    OneShot state;
    assert(state.consume("POST", "mobileconfig_qe_info", 0).mode == -1);
    state.arm(true, "B", 1);
    assert(state.consume("POST", "mobileconfig", 2).mode == -1);
    assert(state.consume("GET", "mobileconfig_qe_info", 2).mode == -1);
    assert(state.pending(2).mode == 1);
    assert(state.consume("POST", "mobileconfig_qe_info", 3).id == "B");
    assert(state.consume("POST", "mobileconfig_qe_info", 4).mode == -1);
    state.arm(true, "expired", 1);
    assert(state.consume("POST", "mobileconfig_qe_info", 121).mode == -1);
    state.arm(false, "A", 1); state.cancel();
    assert(state.pending(2).mode == -1);
    state.arm(false, "A", 1);
    assert(state.consume("POST", "mobileconfig_qe_info", 2).mode == 0);
    const Pairs original{{"access_token", "fixture-secret"}, {"skip_qe", "false"}, {"with_params", "true"}};
    Pairs candidate = original;
    assert(append(candidate));
    assert(candidate.size() == original.size() + 1);
    assert(std::equal(original.begin(), original.end(), candidate.begin()));
    assert(candidate.back() == Pairs::value_type("is_employee", "true"));
    const auto once = candidate;
    assert(!append(candidate) && candidate == once);
    Pairs existing{{"is_employee", "false"}};
    assert(!append(existing) && existing[0].second == "false");
    state.arm(true, "concurrent", 1);
    std::atomic<int> selected(0);
    std::thread a([&]{ if(state.consume("POST", "mobileconfig_qe_info", 2).mode == 1) ++selected; });
    std::thread b([&]{ if(state.consume("POST", "mobileconfig_qe_info", 2).mode == 1) ++selected; });
    a.join(); b.join(); assert(selected == 1);
    // Nine-field metadata profile: atomic rewrite, no injection, no token/ID changes.
    Pairs native{{"device_id", "fixture-device"}, {"access_token", "fixture-secret"},
        {"queries", "[\"fixture-query\"]"}, {"needs_name", "true"},
        {"skip_qe", "true"}, {"with_experiments", "false"},
        {"with_params", "false"}, {"with_groups", "false"},
        {"with_group_params", "false"}, {"with_gatekeepers", "false"},
        {"with_universe_params", "false"}, {"with_current_experiment_group", "false"},
        {"with_only_current_experiment_group", "false"}};
    auto full = native;
    MetadataResult applied = applyFullMetadata(full);
    assert(applied.applied && applied.reason == "applied" && applied.changed == 8);
    assert(full.size() == native.size());
    assert(full[0] == native[0] && full[1] == native[1] && full[2] == native[2]);
    assert(full[3].second == "true" && full[4].second == "false");
    for (std::size_t i = 5; i <= 11; ++i) assert(full[i].second == "true");
    assert(full[12] == native[12]); // only_current remains FALSE
    MetadataResult again = applyFullMetadata(full);
    assert(again.applied && again.changed == 0 && full.size() == native.size());
    auto missing = native;
    missing.erase(missing.begin() + 11);
    auto preserved = missing;
    MetadataResult absent = applyFullMetadata(missing);
    assert(!absent.applied && absent.reason == "missing_protocol_field" && missing == preserved);
    auto duplicate = native;
    duplicate.emplace_back("skip_qe", "true");
    preserved = duplicate;
    MetadataResult ambiguous = applyFullMetadata(duplicate);
    assert(!ambiguous.applied && ambiguous.reason == "duplicate_protocol_field" && duplicate == preserved);
    auto invalid = native;
    invalid[7].second = "unexpected";
    preserved = invalid;
    MetadataResult bad = applyFullMetadata(invalid);
    assert(!bad.applied && bad.reason == "invalid_boolean_encoding" && invalid == preserved);
    OneShot metadataOnce;
    metadataOnce.arm(false, "C", 1);
    assert(metadataOnce.consume("POST", "mobileconfig", 2).mode == -1);
    assert(metadataOnce.consume("GET", "mobileconfig_qe_info", 2).mode == -1);
    assert(metadataOnce.consume("POST", "mobileconfig_qe_info", 3).id == "C");
    assert(metadataOnce.consume("POST", "mobileconfig_qe_info", 4).mode == -1);
    metadataOnce.arm(false, "expired-C", 1);
    assert(metadataOnce.consume("POST", "mobileconfig_qe_info", 121).mode == -1);
    std::cout << "PASS: one-shot scope, expiration, cancellation, concurrency and preserved native parameters\n";
}
