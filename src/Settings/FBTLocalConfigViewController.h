#import "../UI/FBTStyledTableViewController.h"
@interface FBTLocalConfigViewController : FBTStyledTableViewController
- (instancetype)initWithSearchQuery:(NSString *)query;
- (instancetype)initWithConfiguration:(NSDictionary *)configuration;
@end
