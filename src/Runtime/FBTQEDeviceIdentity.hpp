#ifndef FBT_QE_DEVICE_IDENTITY_HPP
#define FBT_QE_DEVICE_IDENTITY_HPP
#include <algorithm>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace fbt_qe_identity {
struct Evidence {
    size_t count = 0, bytes = 0;
    unsigned long long observation = 0;
    const char *format = "not_observed";
};
// Values stay in bounded process memory. Export only opaque sequential IDs.
// These compare exact request-field bytes; they never validate identity.
class Registry {
    std::mutex mutex_;
    std::map<std::string, unsigned long long> observed_;
    unsigned long long next_ = 0;
    static bool hex(char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }
public:
    Evidence observe(const std::vector<std::pair<std::string,std::string>> &pairs) {
        Evidence result; const std::string *value = nullptr;
        for (const auto &pair : pairs) if (pair.first == "device_id") { ++result.count; value = &pair.second; }
        if (result.count != 1 || !value) return result;
        result.bytes = value->size();
        if (value->empty()) { result.format = "empty"; return result; }
        if (value->size() > 4096) { result.format = "over_limit"; return result; }
        bool uuid = value->size() == 36;
        for (size_t i = 0; uuid && i < value->size(); ++i)
            uuid = i == 8 || i == 13 || i == 18 || i == 23 ? (*value)[i] == '-' : hex((*value)[i]);
        result.format = *value == "device_id" ? "field_name_literal" : uuid ? "uuid_text" :
            std::all_of(value->begin(), value->end(), [](char c) { return c >= '0' && c <= '9'; }) ? "decimal_text" : "other_text";
        std::lock_guard<std::mutex> guard(mutex_);
        auto found = observed_.find(*value);
        if (found != observed_.end()) result.observation = found->second;
        else if (observed_.size() < 128) result.observation = observed_.emplace(*value, ++next_).first->second;
        return result;
    }
};
}
#endif
