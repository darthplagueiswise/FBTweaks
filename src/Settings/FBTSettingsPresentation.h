#import <UIKit/UIKit.h>
@interface FBTSettingsSwitch : UISwitch
@property (nonatomic, copy) NSString *prefKey;
@end
// Shared by the shipping settings controller and the native simulator harness.
void FBTConfigureSettingsMenuCell(UITableViewCell *cell, NSDictionary *item, BOOL switchValue, id target, SEL action);
NSString *FBTSettingsFooter(NSDictionary *section);
