#pragma once
#import <UIKit/UIKit.h>
#import "../Runtime/FBGRGateRegistry.h"
@interface FBGRGateCategoryVC : UITableViewController
- (instancetype)initWithProvider:(FBGRGateProvider *)provider;
@end
