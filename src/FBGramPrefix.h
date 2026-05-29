#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSString * const kFBTweaksSuite = @"com.darthplagueiswise.fbtweaks";

static inline NSUserDefaults *FBGRPrefs(void) {
    static NSUserDefaults *u;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ u = [[NSUserDefaults alloc] initWithSuiteName:kFBTweaksSuite] ?: NSUserDefaults.standardUserDefaults; });
    return u;
}
static inline BOOL FBGRPref(NSString *k) { return [FBGRPrefs() boolForKey:k]; }

// ── mc_param_t types — all {Q} = struct { uint64_t value; } ──────────────────
typedef struct { uint64_t value; } mc_bool_param_t;
typedef struct { uint64_t value; } mc_adminID_bool_param_t;
typedef struct { uint64_t value; } mc_sessionbased_bool_param_t;
typedef struct { uint64_t value; } mc_sessionless_bool_param_t;
typedef struct { uint64_t value; } mc_string_param_t;

// ── Master pref keys ──────────────────────────────────────────────────────────
static NSString * const kFBGRLiquidGlassMaster  = @"fbgr_liquid_glass_master";
static NSString * const kFBGREmployeeMaster      = @"fbgr_employee_master";
static NSString * const kFBGRMCObserverEnabled   = @"fbgr_mc_observer_enabled";

// ── Logging ───────────────────────────────────────────────────────────────────
#define FBGRLog(fmt,...)         NSLog(@"[FBTweaks] "     fmt, ##__VA_ARGS__)
#define FBGRLogHook(tag,fmt,...) NSLog(@"[FBTweaks][" tag "] " fmt, ##__VA_ARGS__)

// ── MCGate cache refresh (call after toggling overrides in menu) ──────────────
// Declared here so menu .m files can call it without a separate header
