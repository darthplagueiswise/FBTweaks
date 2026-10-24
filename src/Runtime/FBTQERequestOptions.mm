#import "FBTQERequestOptions.h"
#include "FBTQERequestOptionsCore.hpp"
#include <mutex>

namespace {
std::mutex sOptionsMutex;
fbt_qe_options::Profile sOptions;
}
namespace fbt_qe_options {
Profile sessionProfile() {
    std::lock_guard<std::mutex> guard(sOptionsMutex);
    return sOptions;
}
}
NSDictionary *FBTQERequestOptionsSnapshot(void) {
    auto profile = fbt_qe_options::sessionProfile();
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < profile.values.size(); ++i)
        values[[NSString stringWithUTF8String:fbt_qe_options::keys()[i]]] = @(profile.values[i]);
    return @{@"enabled": @(profile.enabled), @"values": values, @"nonpersistent": @YES,
        @"all_qe_info": @(profile.allQE), @"scope": profile.allQE ? @"all_QE_info_requests" : @"verified_performNameDownload_same_thread_dispatch"};
}
void FBTQERequestOptionsSetEnabled(BOOL enabled) {
    std::lock_guard<std::mutex> guard(sOptionsMutex);
    sOptions.enabled = enabled;
}
void FBTQERequestOptionsSetAllQE(BOOL allQE) {
    std::lock_guard<std::mutex> guard(sOptionsMutex);
    sOptions.allQE = allQE;
}
BOOL FBTQERequestOptionsSetValue(NSString *key, BOOL value) {
    if (![key isKindOfClass:NSString.class]) return NO;
    for (size_t i = 0; i < fbt_qe_options::keys().size(); ++i) {
        if ([key isEqualToString:[NSString stringWithUTF8String:fbt_qe_options::keys()[i]]]) {
            std::lock_guard<std::mutex> guard(sOptionsMutex);
            sOptions.values[i] = value; return YES;
        }
    }
    return NO;
}
void FBTQERequestOptionsReset(BOOL completeProfile) {
    std::lock_guard<std::mutex> guard(sOptionsMutex);
    bool enabled = sOptions.enabled;
    bool allQE = sOptions.allQE;
    sOptions = fbt_qe_options::Profile();
    sOptions.enabled = enabled;
    sOptions.allQE = allQE;
    if (completeProfile) { sOptions.values.fill(true); sOptions.values[9] = false; }
}
