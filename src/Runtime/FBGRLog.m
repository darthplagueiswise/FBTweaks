#import "FBGRLog.h"

static NSMutableArray<NSString *> *gLog;
static dispatch_queue_t gLogQ;

static void FBGRLogInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLog = [NSMutableArray arrayWithCapacity:256];
        gLogQ = dispatch_queue_create("com.fbtweaks.log", DISPATCH_QUEUE_SERIAL);
    });
}

void FBGRLogAppend(NSString *msg) {
    if (!msg.length) return;
    FBGRLogInit();
    dispatch_async(gLogQ, ^{
        NSString *line = [NSString stringWithFormat:@"%@ %@", NSDate.date, msg];
        [gLog addObject:line];
        if (gLog.count > 500) [gLog removeObjectsInRange:NSMakeRange(0, gLog.count - 500)];
    });
}

NSString *FBGRLogSnapshot(void) {
    FBGRLogInit();
    __block NSString *out = nil;
    dispatch_sync(gLogQ, ^{ out = [gLog componentsJoinedByString:@"\n"]; });
    return out ?: @"";
}

void FBGRLogClear(void) {
    FBGRLogInit();
    dispatch_async(gLogQ, ^{ [gLog removeAllObjects]; });
}
