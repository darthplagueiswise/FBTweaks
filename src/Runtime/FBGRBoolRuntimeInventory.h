#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSUInteger, FBGRBoolRuntimeImageKind) {
    FBGRBoolRuntimeImageKindExecutable = 0,
    FBGRBoolRuntimeImageKindFBSharedFramework = 1,
};

@interface FBGRBoolRuntimeCandidate : NSObject
@property(nonatomic, copy) NSString *imageKindName;
@property(nonatomic, copy) NSString *imagePath;
@property(nonatomic, copy) NSString *className;
@property(nonatomic, copy) NSString *selectorName;
@property(nonatomic, copy) NSString *typeEncoding;
@property(nonatomic, assign) BOOL classMethod;
@property(nonatomic, assign) BOOL hooked;
@property(nonatomic, assign) BOOL overrideSet;
@property(nonatomic, assign) BOOL overrideValue;
@property(nonatomic, copy, readonly) NSString *stableKey;
@property(nonatomic, copy, readonly) NSString *displayTitle;
@property(nonatomic, copy, readonly) NSString *displaySubtitle;
@end

NSString *FBGRBoolRuntimeImageTitle(FBGRBoolRuntimeImageKind kind);
NSArray<FBGRBoolRuntimeCandidate *> *FBGRBoolRuntimeCandidates(FBGRBoolRuntimeImageKind kind, BOOL forceRefresh);
FBGRBoolRuntimeCandidate *FBGRBoolRuntimeCandidateForKey(NSString *key);

BOOL FBGRBoolRuntimeInstallHook(FBGRBoolRuntimeCandidate *candidate, NSError **error);
void FBGRBoolRuntimeSetOverride(FBGRBoolRuntimeCandidate *candidate, BOOL value);
void FBGRBoolRuntimeClearOverride(FBGRBoolRuntimeCandidate *candidate);
void FBGRBoolRuntimeClearAllForImageKind(FBGRBoolRuntimeImageKind kind);
NSUInteger FBGRBoolRuntimeOverrideCountForImageKind(FBGRBoolRuntimeImageKind kind);
NSString *FBGRBoolRuntimeDiagnostic(FBGRBoolRuntimeImageKind kind);
