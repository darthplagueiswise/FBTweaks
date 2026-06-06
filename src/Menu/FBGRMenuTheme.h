#pragma once
#import <UIKit/UIKit.h>
UIColor *FBGRBackgroundColor(void);
UIColor *FBGRTextColor(void);
UIColor *FBGRSecondaryTextColor(void);
UIColor *FBGRAccentColor(void);
UIFont *FBGRTitleFont(void);
UIFont *FBGRDetailFont(void);
UIImage *FBGRSymbol(NSString *name, UIColor *color);
void FBGRApplyGlassController(UIViewController *vc);
void FBGRApplyGlassTable(UITableView *tableView);
void FBGRApplyGlassCell(UITableViewCell *cell);
void FBGRApplyReadableTextCell(UITableViewCell *cell, NSString *title, NSString *detail);
UIVisualEffectView *FBGRCreateRealGlassView(void);
void FBGRApplySearchController(UISearchController *search);
void FBGRConfigureCompactSwitch(UISwitch *sw);
