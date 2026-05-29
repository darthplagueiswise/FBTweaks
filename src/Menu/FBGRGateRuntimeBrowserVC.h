#pragma once
#import <UIKit/UIKit.h>
#import "../Runtime/FBGRGateRegistry.h"
@interface FBGRGateRuntimeBrowserVC : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithProvider:(nullable FBGRGateProvider *)provider;  // nil = all params
@end
