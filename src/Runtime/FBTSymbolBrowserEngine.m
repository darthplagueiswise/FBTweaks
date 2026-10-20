// Symbol browser is a browse-only facade; RuntimeBoolBrowser owns every BOOL hook.
#import "FBTSymbolBrowserEngine.h"
#import "FBTRuntimeBoolBrowser.h"
#import <objc/runtime.h>
#import <string.h>
static const char *kImageSuffix[4]={"/Facebook","/FBSharedFramework",
                                    "/FBReactNativeProductsFramework","/FBSharedDynamicFramework"};
static NSString *FBTKey(NSString *cls,NSString *sel,BOOL meta){
    return [NSString stringWithFormat:@"%@%@#%@",meta?@"+":@"",cls?:@"",sel?:@""];
}
static BOOL FBTParseKey(NSString *key,NSString **cls,NSString **sel,BOOL *meta){
    if(![key isKindOfClass:NSString.class]||!key.length)return NO;
    BOOL c=[key hasPrefix:@"+"];
    NSString *s=c?[key substringFromIndex:1]:key;
    NSRange hash=[s rangeOfString:@"#"];
    if(hash.location==NSNotFound||hash.location==0||NSMaxRange(hash)>=s.length)return NO;
    if(cls)*cls=[s substringToIndex:hash.location];
    if(sel)*sel=[s substringFromIndex:NSMaxRange(hash)];
    if(meta)*meta=c;
    return YES;
}
static void FBTAppend(NSMutableArray<FBTSymbolGetter*> *out,Class cls,NSString *name,BOOL meta){
    Class owner=meta?object_getClass(cls):cls;
    unsigned count=0;
    Method *methods=owner?class_copyMethodList(owner,&count):NULL;
    for(unsigned i=0;i<count;i++){
        Method m=methods[i];
        if(method_getNumberOfArguments(m)!=2)continue;
        const char *enc=method_getTypeEncoding(m);
        if(!enc||(strcmp(enc,"B16@0:8")&&strcmp(enc,"c16@0:8")))continue;
        const char *selector=sel_getName(method_getName(m));
        if(!selector||strchr(selector,':')||!strncmp(selector,"set",3)||
           !strncmp(selector,"init",4))continue;
        FBTSymbolGetter *g=[FBTSymbolGetter new];
        g.ownerClassName=name;g.selectorName=[NSString stringWithUTF8String:selector];g.isClassMethod=meta;
        [out addObject:g];
    }
    if(methods)free(methods);
}
@implementation FBTSymbolGetter
- (NSString *)overrideKey {return FBTKey(self.ownerClassName,self.selectorName,self.isClassMethod);}
- (NSNumber *)override {return [FBTSymbolBrowserEngine overrideForKey:self.overrideKey];}
- (NSNumber *)liveValue {return [FBTSymbolBrowserEngine liveValueForClass:self.ownerClassName
 selector:self.selectorName isClassMethod:self.isClassMethod];}
@end
@implementation FBTSymbolClass @end
@implementation FBTSymbolBrowserEngine
+ (NSArray<FBTSymbolClass*>*)classesForImage:(FBTSymbolImage)image {
    if(image<FBTSymbolImageFacebook||image>FBTSymbolImageFBSharedDynamic)return @[];
    const char *suffix=kImageSuffix[image];size_t suffixLen=strlen(suffix);
    unsigned count=0;Class *classes=objc_copyClassList(&count);
    if(!classes)return @[];
    NSMutableArray<FBTSymbolClass*> *out=[NSMutableArray array];
    for(unsigned i=0;i<count;i++){
        Class cls=classes[i];const char *path=class_getImageName(cls);if(!path)continue;
        size_t len=strlen(path);
        if(len<suffixLen||strcmp(path+len-suffixLen,suffix))continue;
        NSString *name=NSStringFromClass(cls);if(!name.length)continue;
        NSMutableArray<FBTSymbolGetter*> *getters=[NSMutableArray array];
        FBTAppend(getters,cls,name,NO);FBTAppend(getters,cls,name,YES);
        if(!getters.count)continue;
        [getters sortUsingComparator:^NSComparisonResult(FBTSymbolGetter *a,FBTSymbolGetter *b){
            return [a.overrideKey compare:b.overrideKey];
        }];
        FBTSymbolClass *c=[FBTSymbolClass new];c.className=name;c.getters=getters;[out addObject:c];
    }
    free(classes);
    [out sortUsingComparator:^NSComparisonResult(FBTSymbolClass *a,FBTSymbolClass *b){
        return [a.className compare:b.className];
    }];
    return out;
}
+ (NSNumber*)liveValueForClass:(NSString*)cls selector:(NSString*)sel isClassMethod:(BOOL)meta {
    // No arbitrary getter invocation. Return the last original naturally observed.
    return FBTRuntimeBoolObservedOriginal(FBTKey(cls,sel,meta));
}
+ (NSNumber*)overrideForKey:(NSString*)key {
    FBTRuntimeBoolMigrateLegacySymbolOverrides();
    NSDictionary *entry=FBTRuntimeBoolOverridesSnapshot()[key];
    id value=[entry isKindOfClass:NSDictionary.class]?entry[@"force"]:nil;
    return [value isKindOfClass:NSNumber.class]?value:nil;
}
+ (BOOL)hookInstalledForKey:(NSString*)key {return FBTRuntimeBoolHookInstalledForKey(key);}
+ (BOOL)installOverrideForKey:(NSString*)key {return FBTRuntimeBoolInstallPersistedKey(key);}
+ (void)setOverride:(NSNumber*)value forClass:(NSString*)cls selector:(NSString*)sel isClassMethod:(BOOL)meta {
    FBTRuntimeBoolMigrateLegacySymbolOverrides();
    NSString *key=FBTKey(cls,sel,meta);
    NSDictionary *candidate=@{@"class":cls?:@"",@"selector":sel?:@"",@"classMethod":@(meta),@"key":key};
    if(value)FBTRuntimeBoolSetOverride(candidate,value.boolValue);
    else FBTRuntimeBoolClearOverride(candidate);
}
+ (void)reinstallPersistedHooks {FBTRuntimeBoolReinstallPersistedHooks();}
@end
