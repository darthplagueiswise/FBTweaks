#include <cassert>
#if __has_include("../src/Runtime/FBTQEDeviceIdentity.hpp")
#include "../src/Runtime/FBTQEDeviceIdentity.hpp"
int main() {
    fbt_qe_identity::Registry registry;
    auto a = registry.observe({{"device_id","opaque-test-a"}});
    auto b = registry.observe({{"device_id","opaque-test-a"}});
    auto c = registry.observe({{"device_id","opaque-test-b"}});
    assert(a.count == 1 && a.bytes == 13 && a.observation != 0);
    assert(a.observation == b.observation && a.observation != c.observation);
    assert(registry.observe({}).count == 0);
    auto empty = registry.observe({{"device_id",""}});
    assert(empty.observation == 0 && empty.bytes == 0);
    auto dup = registry.observe({{"device_id","a"},{"device_id","b"}});
    assert(dup.count == 2 && dup.observation == 0);
    assert(std::string(registry.observe({{"device_id","123456789"}}).format) == "decimal_text");
    assert(std::string(registry.observe({{"device_id","11111111-2222-3333-4444-555555555555"}}).format) == "uuid_text");
    assert(std::string(registry.observe({{"device_id","not-a-uuid"}}).format) == "other_text");
    assert(std::string(registry.observe({{"device_id","device_id"}}).format) == "field_name_literal");
    assert(registry.observe({{"device_id",std::string(4097,'x')}}).observation == 0);
    for (int i = 0; i < 200; ++i) registry.observe({{"device_id","fixture"+std::to_string(i)}});
    assert(registry.observe({{"device_id","new-after-capacity"}}).observation == 0);
    assert(registry.observe({{"device_id","opaque-test-a"}}).observation == a.observation);
}
#else
int main() { assert(!"Device identity observations missing"); }
#endif
