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
    std::cout << "PASS: one-shot scope, expiration, cancellation, concurrency and preserved native parameters\n";
}
