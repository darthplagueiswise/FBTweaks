#import "FBTNativeTrace.h"
#import "FBTNativeTraceCore.hpp"
#import "../FBTDefaults.h"
// No dynamic global C++ object in dyld image initializers.
static fbt_trace::Ring &FBTTraceRing(void) {
    static fbt_trace::Ring instance;
    return instance;
}
static int sTraceEnabled = 0;
void FBTNativeTraceReloadPrefs(void) {
 BOOL enabled=[FBTDefaults boolForKey:FBTKeyNativeTraceEnabled];
 FBTTraceRing().setEnabled(enabled);
 __atomic_store_n(&sTraceEnabled,enabled?1:0,__ATOMIC_RELEASE);
}
BOOL FBTNativeTraceIsEnabled(void){return __atomic_load_n(&sTraceEnabled,__ATOMIC_ACQUIRE)!=0;}
void FBTNativeTraceRecordBool(NSString *methodKey,int original,int effective){
 if(!FBTNativeTraceIsEnabled())return;
 FBTTraceRing().add(fbt_trace::BOOL_CALL,methodKey.UTF8String,"",original,effective);
}
static BOOL FBTTraceNetworkEventName(NSString *event){
 return [event hasPrefix:@"qe_info_"]||[event hasPrefix:@"name_download_"]||
        [event hasPrefix:@"tigon_"]||[event hasPrefix:@"network_"]||
        [event hasPrefix:@"mobileconfig_"]||[event hasPrefix:@"native_mc_"];
}
void FBTNativeTraceRecordNetwork(NSString *event,NSDictionary *safeDetails){
 if(!FBTNativeTraceIsEnabled()||![event isKindOfClass:[NSString class]]||!FBTTraceNetworkEventName(event))return;
 NSMutableArray<NSString*> *meta=[NSMutableArray array];
 for(NSString *key in @[@"request_id",@"http_status",@"server_error_code",@"network_error_code",@"error_code",@"request_path"]){
  id v=safeDetails[key];
  if([v isKindOfClass:[NSNumber class]]||[v isKindOfClass:[NSString class]]){
   NSString *raw=[v description];
   NSString *value=[raw substringToIndex:MIN((NSUInteger)48,raw.length)];
   [meta addObject:[NSString stringWithFormat:@"%@=%@",key,value]];
  }
 }
 NSString *note=[meta componentsJoinedByString:@" "];
 FBTTraceRing().add(fbt_trace::NETWORK,event.UTF8String,note.UTF8String,-1,-1);
}
NSDictionary *FBTNativeTraceSnapshot(void){
 std::vector<fbt_trace::Record>records=FBTTraceRing().snapshot();
 NSMutableArray *events=[NSMutableArray arrayWithCapacity:records.size()];
 for(auto it=records.rbegin();it!=records.rend();++it){
  const fbt_trace::Record &r=*it;
  [events addObject:@{
   @"sequence":@(r.sequence),@"uptime_ms":@(r.monotonic_ns/1000000ULL),
   @"kind":r.kind==fbt_trace::BOOL_CALL?@"BOOL":r.kind==fbt_trace::NETWORK?@"QE/Tigon":@"System",
   @"name":[NSString stringWithUTF8String:r.name]?:@"",
   @"detail":[NSString stringWithUTF8String:r.note]?:@"",
   @"original":r.original<0?(id)[NSNull null]:@(r.original!=0),
   @"effective":r.effective<0?(id)[NSNull null]:@(r.effective!=0)
  }];
 }
 return @{@"schema_version":@1,@"enabled":@(FBTNativeTraceIsEnabled()),@"capacity":@(fbt_trace::CAPACITY),
          @"dropped_on_contention":@(FBTTraceRing().dropped()),@"events":events};
}
void FBTNativeTraceClear(void){FBTTraceRing().clear();}
