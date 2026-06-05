#pragma once
#import <UIKit/UIKit.h>
#import "../Runtime/FBGRBoolRuntimeInventory.h"

@interface FBGRBoolRuntimeBrowserVC : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithImageKind:(FBGRBoolRuntimeImageKind)kind;
@end
