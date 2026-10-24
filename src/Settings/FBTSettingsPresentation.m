#import "FBTSettingsPresentation.h"
#import "../UI/FBTUIKit26LiquidGlass.h"
#import "../FBTDefaults.h"
#ifndef FBT_BUILD_NUMBER
#define FBT_BUILD_NUMBER 0
#endif
@implementation FBTSettingsSwitch @end
static UIColor *Accent(NSString *name) {
    if ([name isEqual:@"purple"]) return UIColor.systemPurpleColor;
    if ([name isEqual:@"teal"]) return UIColor.systemTealColor;
    if ([name isEqual:@"pink"]) return UIColor.systemPinkColor;
    if ([name isEqual:@"orange"]) return UIColor.systemOrangeColor;
    return UIColor.systemBlueColor;
}
void FBTConfigureSettingsMenuCell(UITableViewCell *cell, NSDictionary *item, BOOL switchValue, id target, SEL action) {
    FBTUIKit26ConfigureTableCell(cell);
    NSString *kind = item[@"kind"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = item[@"title"];
    cfg.secondaryText = item[@"subtitle"];
    cfg.image = [UIImage systemImageNamed:item[@"icon"] ?: @"gearshape"] ?: [UIImage systemImageNamed:@"gearshape"];
    cfg.imageProperties.tintColor = Accent(item[@"color"]);
    cfg.imageProperties.maximumSize = CGSizeMake(25,25);
    cfg.textProperties.color = [item[@"action"] isEqual:@"clear"] ? UIColor.systemRedColor :
        [kind isEqual:@"action"] ? UIColor.systemBlueColor : UIColor.labelColor;
    cfg.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cfg.textProperties.adjustsFontForContentSizeCategory = YES;
    cfg.textProperties.numberOfLines = 0;
    cfg.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cfg.secondaryTextProperties.adjustsFontForContentSizeCategory = YES;
    cfg.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cfg.secondaryTextProperties.numberOfLines = 0;
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(13,16,13,16);
    cell.contentConfiguration = cfg;
    if ([kind isEqual:@"switch"]) {
        FBTSettingsSwitch *toggle = [FBTSettingsSwitch new];
        toggle.prefKey = item[@"key"]; toggle.on = switchValue;
        toggle.accessibilityLabel = item[@"title"];
        toggle.accessibilityHint = item[@"subtitle"];
        toggle.accessibilityIdentifier = [@"fbtweak.setting." stringByAppendingString:toggle.prefKey];
        if (target && action) [toggle addTarget:target action:action forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqual:@"nav"]) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = [@"fbtweak.route." stringByAppendingString:item[@"dest"] ?: item[@"action"] ?: item[@"key"] ?: @"unknown"];
}
NSString *FBTSettingsFooter(NSDictionary *section) {
    NSString *footer = section[@"footer"] ?: @"";
    if ([section[@"category"] isEqual:@"general"]) {
        NSString *build = FBT_BUILD_NUMBER > 0 ? [NSString stringWithFormat:@"Build %d",FBT_BUILD_NUMBER] : @"Build local";
        return [NSString stringWithFormat:@"FBTweak · %@ · %@\n%@",build,
            [FBTDefaults boolForKey:FBTKeyMasterEnabled] ? @"Ativa" : @"Pausada",footer];
    }
    return footer;
}
