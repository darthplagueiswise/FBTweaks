#pragma once
#import <UIKit/UIKit.h>
UIColor *FBGRBackgroundColor(void);
UIColor *FBGRGroupedCellColor(void);
UIColor *FBGRTextColor(void);
UIColor *FBGRSecondaryTextColor(void);
UIColor *FBGRAccentColor(void);
UIImage *FBGRSymbol(NSString *name, UIColor *color);
void FBGRApplyGlassController(UIViewController *vc);
void FBGRApplyGlassTable(UITableView *tableView);
void FBGRApplyGlassCell(UITableViewCell *cell);
void FBGRApplySearchController(UISearchController *search);
void FBGRConfigureCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIImage *image);
void FBGRConfigureSwitchCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UISwitch *sw, UIImage *image);
