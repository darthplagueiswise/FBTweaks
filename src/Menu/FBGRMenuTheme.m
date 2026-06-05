#import "FBGRMenuTheme.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

UIColor *FBGRBg(void)   { return [UIColor colorWithRed:.02 green:.02 blue:.025 alpha:1]; }
UIColor *FBGRCell(void) { return [UIColor colorWithWhite:.12 alpha:FBGRRealLiquidGlassAvailable() ? .28 : 1.0]; }
UIColor *FBGRText(void) { return UIColor.whiteColor; }
UIColor *FBGRSub(void)  { return [UIColor colorWithWhite:.70 alpha:1]; }
UIColor *FBGRAccent(NSInteger i) { static NSArray *p; static dispatch_once_t o; dispatch_once(&o, ^{ p=@[UIColor.systemCyanColor,UIColor.systemPurpleColor,UIColor.systemOrangeColor,UIColor.systemGreenColor,UIColor.systemBlueColor,UIColor.systemPinkColor,UIColor.systemYellowColor,UIColor.systemTealColor]; }); return p[(NSUInteger)labs((long)i)%p.count]; }
UIColor *FBGRAccentForProvider(NSString *c) { NSDictionary *m=@{@"cyan":UIColor.systemCyanColor,@"purple":UIColor.systemPurpleColor,@"orange":UIColor.systemOrangeColor,@"green":UIColor.systemGreenColor,@"blue":UIColor.systemBlueColor,@"pink":UIColor.systemPinkColor,@"teal":UIColor.systemTealColor}; return m[c ?: @""] ?: UIColor.systemBlueColor; }

static UIVisualEffect *FBGRCreateRealGlassEffect(void) {
    NSArray *classes=@[@"UIGlassEffect", @"_UIGlassEffect", @"_UILiquidGlassEffect", @"UILiquidGlassEffect"];
    NSArray *selectors=@[@"effect", @"regularEffect", @"glassEffect", @"defaultEffect"];
    for (NSString *cn in classes) {
        Class cls=NSClassFromString(cn); if (!cls) continue;
        for (NSString *sn in selectors) {
            SEL sel=NSSelectorFromString(sn); if (![cls respondsToSelector:sel]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id obj=[cls performSelector:sel];
#pragma clang diagnostic pop
            if ([obj isKindOfClass:UIVisualEffect.class]) return (UIVisualEffect *)obj;
        }
    }
    return nil;
}
BOOL FBGRRealLiquidGlassAvailable(void) { static BOOL ok; static dispatch_once_t once; dispatch_once(&once, ^{ ok = FBGRCreateRealGlassEffect() != nil; }); return ok; }
void FBGRInstallLiquidGlassBackground(UIView *view) {
    if (!view || [view viewWithTag:260260]) return;
    UIVisualEffect *effect=FBGRCreateRealGlassEffect(); if (!effect) return; // real only: no blur simulation fallback.
    UIVisualEffectView *glass=[[UIVisualEffectView alloc] initWithEffect:effect];
    glass.tag=260260; glass.userInteractionEnabled=NO; glass.frame=view.bounds; glass.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    glass.layer.cornerRadius=24; glass.layer.masksToBounds=YES;
    [view insertSubview:glass atIndex:0];
}
void FBGRApplyTable(UITableView *tv, UIViewController *vc) {
    if (vc) { vc.view.backgroundColor = FBGRRealLiquidGlassAvailable() ? UIColor.clearColor : FBGRBg(); FBGRInstallLiquidGlassBackground(vc.view); }
    if (!tv) return;
    tv.backgroundColor = UIColor.clearColor; tv.separatorColor=[UIColor colorWithWhite:.35 alpha:FBGRRealLiquidGlassAvailable()?.35:1]; tv.separatorInset=UIEdgeInsetsZero;
}
void FBGRApplyCell(UITableViewCell *c, NSInteger idx, NSString *color) {
    c.backgroundColor = FBGRCell(); c.contentView.backgroundColor = UIColor.clearColor;
    c.textLabel.textColor = FBGRText(); c.detailTextLabel.textColor = FBGRSub();
    c.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; c.detailTextLabel.font=[UIFont systemFontOfSize:12];
    c.tintColor = color ? FBGRAccentForProvider(color) : FBGRAccent(idx);
    c.selectedBackgroundView=[UIView new]; c.selectedBackgroundView.backgroundColor=[UIColor colorWithWhite:.35 alpha:.25];
    c.layer.cornerCurve = kCACornerCurveContinuous; c.layer.cornerRadius = 14; c.layer.masksToBounds = YES;
}
UIImage *FBGRSymbol(NSString *name, UIColor *tint) { UIImage *img=[UIImage systemImageNamed:name ?: @"circle"]; if (tint) img=[img imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal]; return img; }
