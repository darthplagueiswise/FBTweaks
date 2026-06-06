#pragma once
#import <UIKit/UIKit.h>

UIColor *FBGRBackgroundColor(void);
UIColor *FBGRGroupedCellColor(void);
UIColor *FBGRTextColor(void);
UIColor *FBGRSecondaryTextColor(void);
UIColor *FBGRSeparatorColor(void);
UIColor *FBGRAccentColor(void);
UIFont *FBGRTitleFont(void);
UIFont *FBGRDetailFont(void);
UIFont *FBGRRootTitleFont(void);
UIFont *FBGRRootDetailFont(void);
UIImage *FBGRSymbol(NSString *name, UIColor *color);
void FBGRApplyGlassController(UIViewController *vc);
void FBGRApplyGlassTable(UITableView *tableView);
void FBGRApplyGlassCell(UITableViewCell *cell);
void FBGRApplyReadableTextCell(UITableViewCell *cell, NSString *title, NSString *detail);
void FBGRApplyReadableTextCellWithReservedTrailing(UITableViewCell *cell, NSString *title, NSString *detail, CGFloat reservedTrailing);
void FBGRApplyRootTextCell(UITableViewCell *cell, NSString *title, NSString *detail);
UIVisualEffectView *FBGRCreateRealGlassView(void);
void FBGRApplySearchController(UISearchController *search);
void FBGRConfigureCompactSwitch(UISwitch *sw);
void FBGRInstallSwitchInCell(UITableViewCell *cell, UISwitch *sw);
