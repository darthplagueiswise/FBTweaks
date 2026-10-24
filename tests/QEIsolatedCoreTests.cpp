#include "../src/Runtime/FBTMCQEFullMetadataCore.hpp"
#include <cassert>
#include <iostream>
#include <thread>
#include <atomic>

using namespace fbt_qe_isolated;

static Pairs sample() {
    return Pairs{
        {"access_token", "SECRET_DO_NOT_TOUCH"},
        {"device_id", "IDENTITY_DO_NOT_TOUCH"},
        {"queries", "[\"remote-query-unchanged\"]"},
        {"needs_name", "true"},
        {"skip_qe", "true"},
        {"with_experiments", "false"},
        {"with_params", "false"},
        {"with_groups", "false"},
        {"with_group_params", "false"},
        {"with_gatekeepers", "false"},
        {"with_universe_params", "false"},
        {"with_current_experiment_group", "false"},
        {"with_only_current_experiment_group", "false"},
        {"api_version", "9"}
    };
}

int main() {
    Pairs original = sample(), modified = original;
    auto result = apply(modified);
    assert(result.applied && result.changed == 8);
    assert(modified.size() == original.size());
    for (std::size_t i = 0; i < 3; ++i) assert(modified[i] == original[i]);
    assert(modified[3].second == "true");
    assert(modified[4].second == "false");
    for (std::size_t i = 5; i <= 11; ++i) assert(modified[i].second == "true");
    assert(modified[12] == original[12] && modified[13] == original[13]);
    auto noChange = apply(modified);
    assert(noChange.applied && noChange.changed == 0);

    Pairs missing = original;
    missing.erase(missing.begin() + 9);
    Pairs preserved = missing;
    auto absent = apply(missing);
    assert(!absent.applied && std::string(absent.reason) == "missing_protocol_field");
    assert(missing == preserved);

    Pairs duplicate = original;
    duplicate.emplace_back("skip_qe", "true");
    preserved = duplicate;
    auto ambiguous = apply(duplicate);
    assert(!ambiguous.applied && std::string(ambiguous.reason) == "duplicate_protocol_field");
    assert(duplicate == preserved);

    Pairs malformed = original;
    malformed[7].second = "unexpected";
    preserved = malformed;
    auto invalid = apply(malformed);
    assert(!invalid.applied && std::string(invalid.reason) == "invalid_boolean_encoding");
    assert(malformed == preserved);

    OneShot once;
    once.arm(1);
    assert(once.pending(2));
    assert(!once.consume("GET", "mobileconfig_qe_info", 2));
    assert(!once.consume("POST", "mobileconfig", 2));
    assert(once.consume("POST", "mobileconfig_qe_info", 3));
    assert(!once.pending(4));
    assert(!once.consume("POST", "mobileconfig_qe_info", 4));
    once.arm(1);
    assert(!once.consume("POST", "mobileconfig_qe_info", 121));

    once.arm(40);
    once.cancel();
    assert(!once.consume("POST", "mobileconfig_qe_info", 41));

    // Concurrent callers must not both consume the same authorization.
    once.arm(10);
    std::atomic<unsigned> applied(0);
    std::thread left([&] { if (once.consume("POST", "mobileconfig_qe_info", 11)) ++applied; });
    std::thread right([&] { if (once.consume("POST", "mobileconfig_qe_info", 11)) ++applied; });
    left.join(); right.join();
    assert(applied.load() == 1);
    std::cout << "PASS: isolated atomic flags, unchanged identity/query fields, one-shot, expiration, concurrency" << std::endl;
}
