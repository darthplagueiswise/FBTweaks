#import <UIKit/UIKit.h>
#import "../FBTUtils.h"
@interface FBTUtils (FBTBrowserCompat)
+ (NSDictionary *)getDictPref:(NSString *)key;
+ (void)setPref:(id)value forKey:(NSString *)key;
+ (UIColor *)FBTColor_Primary;
+ (void)showToastForDuration:(double)duration title:(NSString *)title;
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle;
@end
