#include "../src/Runtime/FBTMCRequestExperiment.hpp"
#include <cassert>
#include <string>
using fbt_mc_probe::Pairs;
int main() {
    fbt_mc_probe::OneShot test;
    test.arm(true, "B", 1000.);
    assert(test.consume("GET", "mobileconfig_qe_info", 1001.).mode == -1);
    assert(test.consume("POST", "mobileconfig", 1001.).mode == -1);
    auto b = test.consume("POST", "mobileconfig_qe_info", 1001.);
    assert(b.mode == 1 && b.id == "B");
    Pairs p{{"api_version", "9"}, {"device_id", "device_id"}, {"needs_name", "true"}};
    assert(fbt_mc_probe::append(p));
    assert(p.size() == 4 && p[3].first == "is_employee" && p[3].second == "true");
    assert(!fbt_mc_probe::append(p));
    assert(test.consume("POST", "mobileconfig_qe_info", 1002.).mode == -1);
    test.arm(true, "expired", 2000.);
    assert(test.consume("POST", "mobileconfig_qe_info", 2121.).mode == -1);
    test.arm(false, "A", 3000.);
    assert(test.consume("POST", "mobileconfig_qe_info", 3005.).mode == 0);
    return 0;
}
