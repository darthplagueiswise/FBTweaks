#import "FBTBrowserCompat.h"
#import "../FBTUtils.h"

@implementation FBTUtils (FBTBrowserCompat)
+ (NSDictionary *)getDictPref:(NSString *)key {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:key];
    return d ?: @{};
}
+ (void)setPref:(id)value forKey:(NSString *)key {
    if (value) [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
+ (UIColor *)FBTColor_Primary { return [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0]; }
+ (void)showToastForDuration:(double)duration title:(NSString *)title {
    [self showToastForDuration:duration title:title subtitle:nil];
}
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        for (UIWindow *w in UIApplication.sharedApplication.windows) { if (w.isKeyWindow) { win = w; break; } }
        if (!win) win = UIApplication.sharedApplication.windows.firstObject;
        if (!win) return;
        UILabel *l = [UILabel new]; l.numberOfLines = 0;
        l.text = subtitle.length ? [NSString stringWithFormat:@"%@\n%@", title, subtitle] : (title ?: @"");
        l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:13.0];
        l.textAlignment = NSTextAlignmentCenter;
        l.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.82];
        l.layer.cornerRadius = 12.0; l.clipsToBounds = YES;
        CGFloat maxW = MIN(320.0, win.bounds.size.width - 40.0);
        CGSize sz = [l sizeThatFits:CGSizeMake(maxW - 24.0, 999.0)];
        l.frame = CGRectMake((win.bounds.size.width - (sz.width + 24.0)) / 2.0,
                             win.bounds.size.height - 160.0, sz.width + 24.0, sz.height + 20.0);
        l.alpha = 0.0; [win addSubview:l];
        [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1.0; } completion:^(BOOL f){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{ l.alpha = 0.0; } completion:^(BOOL f2){ [l removeFromSuperview]; }];
            });
        }];
    });
}
@end
