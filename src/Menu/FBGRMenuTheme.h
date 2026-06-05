#pragma once
#import <UIKit/UIKit.h>
UIColor *FBGRBackgroundColor(void);
UIColor *FBGRTextColor(void);
UIColor *FBGRSecondaryTextColor(void);
UIColor *FBGRAccentColor(void);
UIImage *FBGRSymbol(NSString *name, UIColor *color);
void FBGRApplyGlassController(UIViewController *vc);
void FBGRApplyGlassTable(UITableView *tableView);
void FBGRApplyGlassCell(UITableViewCell *cell);
UIVisualEffectView *FBGRCreateRealGlassView(void);
void FBGRApplySearchController(UISearchController *search);
