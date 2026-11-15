#import <UIKit/UIKit.h>
@interface FBTLocalConfigViewController : UITableViewController
- (instancetype)initWithSearchQuery:(NSString *)query;
- (instancetype)initWithConfiguration:(NSDictionary *)configuration;
@end
