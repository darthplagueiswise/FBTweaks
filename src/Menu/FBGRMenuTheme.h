#pragma once
#import <UIKit/UIKit.h>
UIColor *FBGRBg(void);
UIColor *FBGRCell(void);
UIColor *FBGRText(void);
UIColor *FBGRSub(void);
UIColor *FBGRAccent(NSInteger idx);
UIColor *FBGRAccentForProvider(NSString *color);
void     FBGRApplyTable(UITableView *_Nullable tv, UIViewController *_Nullable vc);
void     FBGRApplyCell(UITableViewCell *c, NSInteger idx, NSString *_Nullable color);
UIImage *_Nullable FBGRSymbol(NSString *name, UIColor *tint);
