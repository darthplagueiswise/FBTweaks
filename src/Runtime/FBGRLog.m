#import "FBGRLog.h"

static NSMutableArray<NSString *> *gLog;
static dispatch_queue_t gLogQ;
static dispatch_once_t gLogOnce;

static void FBGRLogInit(void) {
    dispatch_once(&gLogOnce, ^{
        gLog  = [NSMutableArray arrayWithCapacity:512];
        gLogQ = dispatch_queue_create("com.fbtweaks.log", DISPATCH_QUEUE_SERIAL);
    });
}

void FBGRLogAppend(NSString *msg) {
    FBGRLogInit();
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
        dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *line = [NSString stringWithFormat:@"[%@] %@", ts, msg];
    dispatch_async(gLogQ, ^{
        [gLog addObject:line];
        if (gLog.count > 1000) [gLog removeObjectAtIndex:0];
    });
}

NSString *FBGRLogSnapshot(void) {
    FBGRLogInit();
    __block NSString *result;
    dispatch_sync(gLogQ, ^{
        result = [gLog componentsJoinedByString:@"\n"] ?: @"(vazio)";
    });
    return result;
}

void FBGRLogClear(void) {
    FBGRLogInit();
    dispatch_async(gLogQ, ^{ [gLog removeAllObjects]; });
}
