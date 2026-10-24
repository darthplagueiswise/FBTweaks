#include "../src/Runtime/FBTMCServiceEvidence.hpp"
#include <cassert>
#include <thread>
#include <vector>
int main() {
    fbt_mc_evidence::ServiceRegistry registry(3);
    assert(registry.observe(0) == 0); // Missing observation must not become a service.
    assert(registry.observe(0x100) == 1);
    assert(registry.observe(0x200) == 2);
    assert(registry.observe(0x100) == 1); // QE/value observations share the same identity.
    assert(registry.observe(0x300) == 3);
    assert(registry.observe(0x400) == 0); // Bounded; no evicted identity reused for another object.
    assert(registry.observe(0x100) == 1);
    registry.reset();
    assert(registry.observe(0x400) == 4); // Old in-flight callbacks cannot alias the new capture.
    assert(registry.observe(0x100) == 5);
    fbt_mc_evidence::ServiceRegistry concurrent(32);
    std::vector<std::thread> threads;
    for (int i=0;i<16;i++) threads.emplace_back([&] {
        for (int j=0;j<1000;j++) assert(concurrent.observe(0x555) == 1);
    });
    for (auto &thread : threads) thread.join();
    using namespace fbt_mc_evidence;
    assert(compare(0, 1) == Relation::Unknown);
    assert(compare(1, 0) == Relation::Unknown);
    assert(compare(1, 1) == Relation::SameObservedService);
    assert(compare(1, 2) == Relation::DifferentObservedServices);
}
