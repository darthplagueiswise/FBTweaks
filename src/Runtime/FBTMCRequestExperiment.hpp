#pragma once
#include <algorithm>
#include <mutex>
#include <string>
#include <utility>
#include <vector>
namespace fbt_mc_probe {
using Pairs = std::vector<std::pair<std::string, std::string>>;
struct Selection { int mode = -1; std::string id; };
class OneShot {
    std::mutex mutex;
    Selection next;
    double deadline = 0;
public:
    void arm(bool employee, const std::string &id, double now) {
        std::lock_guard<std::mutex> guard(mutex);
        next.mode = employee ? 1 : 0; next.id = id; deadline = now + 120;
    }
    void cancel() { std::lock_guard<std::mutex> guard(mutex); next = Selection(); deadline = 0; }
    Selection pending(double now) {
        std::lock_guard<std::mutex> guard(mutex);
        return now < deadline ? next : Selection();
    }
    Selection consume(const std::string &method, const std::string &purpose, double now) {
        if (method != "POST" || purpose != "mobileconfig_qe_info") return Selection();
        std::lock_guard<std::mutex> guard(mutex);
        Selection result = now < deadline ? next : Selection();
        next = Selection(); deadline = 0;
        return result;
    }
};
inline bool append(Pairs &copy) {
    if (std::any_of(copy.begin(), copy.end(), [](const Pairs::value_type &p) { return p.first == "is_employee"; })) return false;
    copy.emplace_back("is_employee", "true");
    return true;
}
}
