//
//  UINavigationController+FullscreenPopGesture.m
//  FullscreenPopGestureDemo
//
//  Created by HE Jianfeng on 2017/3/28.
//  Copyright © 2017年 hjfrun. All rights reserved.
//

#import "UINavigationController+FullscreenPopGesture.h"
#import <objc/runtime.h>

@interface _FullscreenPopGestureRecognizerDelegate : NSObject <UIGestureRecognizerDelegate>

@property (nonatomic, weak) UINavigationController *navigationController;

@end

@implementation _FullscreenPopGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer
{
    // 没有可pop的控制器，不相应
    if (self.navigationController.viewControllers.count <= 1) {
        return NO;
    }
    
    // 最顶上控制器要求不相应，则不相应
    UIViewController *topViewController = self.navigationController.viewControllers.lastObject;
    
    if (topViewController.hjf_interactivePopDisabled) {
        return NO;
    }
    
    // 开始位置离左边太远也不相应
    CGPoint beginningLocation = [gestureRecognizer locationInView:gestureRecognizer.view];
    
    CGFloat maxAllowedInitialDistance = topViewController.hjf_interactivePopMaxAllowedInitialDistanceToLeftEdge;
    if (maxAllowedInitialDistance > 0 && beginningLocation.x > maxAllowedInitialDistance) {
        return NO;
    }
    
    // 正在进行动画，则不相应
    if ([[self.navigationController valueForKeyPath:@"_isTransitioning"] boolValue]) {
        return NO;
    }
    
    // 向左滑动，也不相应
    CGPoint translation = [gestureRecognizer translationInView:gestureRecognizer.view];
    
    if (translation.x <= 0) {
        return NO;
    }
    
    return YES;
}

@end

typedef void(^_HJFViewControllerWillAppearInjectBlock)(UIViewController *viewController, BOOL animated);

@interface UIViewController (FullscreenPopGesturePrivate)

@property (nonatomic, copy) _HJFViewControllerWillAppearInjectBlock hjf_willAppearInjectBlock;

@end

@implementation UIViewController (FullscreenPopGesturePrivate)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(viewWillAppear:);
        SEL swizzledSelector = @selector(hjf_viewWillAppear:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        BOOL success = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        if (success) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (void)hjf_viewWillAppear:(BOOL)animated
{
    [self hjf_viewWillAppear:animated];
    
    if (self.hjf_willAppearInjectBlock) {
        self.hjf_willAppearInjectBlock(self, animated);
    }
}

- (_HJFViewControllerWillAppearInjectBlock)hjf_willAppearInjectBlock
{
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setHjf_willAppearInjectBlock:(_HJFViewControllerWillAppearInjectBlock)block
{
    objc_setAssociatedObject(self, @selector(hjf_willAppearInjectBlock), block, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end

@implementation UINavigationController (FullscreenPopGesture)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(pushViewController:animated:);
        SEL swizzledSelector = @selector(hjf_pushViewController:animated:);
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        BOOL success = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        if (success) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
        
    });
}

- (void)hjf_pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (![self.interactivePopGestureRecognizer.view.gestureRecognizers containsObject:self.hjf_fullscreenPopGestureRecognizer]) {
        [self.interactivePopGestureRecognizer.view addGestureRecognizer:self.hjf_fullscreenPopGestureRecognizer];
        
        NSArray *internalTargets = [self.interactivePopGestureRecognizer valueForKeyPath:@"targets"];
        id internalTarget = [internalTargets.firstObject valueForKeyPath:@"target"];
        SEL internalAction = NSSelectorFromString(@"handleNavigationTransition:");
        self.hjf_fullscreenPopGestureRecognizer.delegate = self.hjf_popGestureRecognizerDelegate;
        [self.hjf_fullscreenPopGestureRecognizer addTarget:internalTarget action:internalAction];
        
        self.interactivePopGestureRecognizer.enabled = NO;
    }
    
    [self hjf_setupViewControllerBasedNavigationBarAppearanceIfNeeded:viewController];
    
    if (![self.viewControllers containsObject:viewController]) {
        [self hjf_pushViewController:viewController animated:animated];
    }
}

- (void)hjf_setupViewControllerBasedNavigationBarAppearanceIfNeeded:(UIViewController *)appearingViewController
{
    if (!self.hjf_viewControllerBasedNavigationBarAppearanceEnabled) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    _HJFViewControllerWillAppearInjectBlock block = ^(UIViewController *viewController, BOOL animated) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf setNavigationBarHidden:viewController.hjf_prefersNavigationBarHidden animated:animated];
        }
    };
    
    appearingViewController.hjf_willAppearInjectBlock = block;
    UIViewController *disappearingViewController = self.viewControllers.lastObject;
    if (disappearingViewController && !disappearingViewController.hjf_willAppearInjectBlock) {
        disappearingViewController.hjf_willAppearInjectBlock = block;
    }
    
}


- (_FullscreenPopGestureRecognizerDelegate *)hjf_popGestureRecognizerDelegate
{
    _FullscreenPopGestureRecognizerDelegate *delegate = objc_getAssociatedObject(self, _cmd);
    if (!delegate) {
        delegate = [[_FullscreenPopGestureRecognizerDelegate alloc] init];
        delegate.navigationController = self;
        objc_setAssociatedObject(self, _cmd, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return delegate;
}

- (UIPanGestureRecognizer *)hjf_fullscreenPopGestureRecognizer
{
    UIPanGestureRecognizer *panGestureRecognizer = objc_getAssociatedObject(self, _cmd);
    
    if (!panGestureRecognizer) {
        panGestureRecognizer = [[UIPanGestureRecognizer alloc] init];
        panGestureRecognizer.maximumNumberOfTouches = 1;
        objc_setAssociatedObject(self, _cmd, panGestureRecognizer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return panGestureRecognizer;
}

- (BOOL)hjf_viewControllerBasedNavigationBarAppearanceEnabled
{
    NSNumber *number = objc_getAssociatedObject(self, _cmd);
    if (number) {
        return number.boolValue;
    }
    self.hjf_viewControllerBasedNavigationBarAppearanceEnabled = YES;
    return YES;
}

- (void)setHjf_viewControllerBasedNavigationBarAppearanceEnabled:(BOOL)enabled
{
    SEL key = @selector(hjf_viewControllerBasedNavigationBarAppearanceEnabled);
    objc_setAssociatedObject(self, key, @(enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}


@end


@implementation UIViewController (FullscreenPopGesture)

- (BOOL)hjf_interactivePopDisabled
{
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)setHjf_interactivePopDisabled:(BOOL)disabled
{
    objc_setAssociatedObject(self, @selector(hjf_interactivePopDisabled), @(disabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)hjf_prefersNavigationBarHidden
{
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)setHjf_prefersNavigationBarHidden:(BOOL)hidden
{
    objc_setAssociatedObject(self, @selector(hjf_prefersNavigationBarHidden), @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)hjf_interactivePopMaxAllowedInitialDistanceToLeftEdge
{
#if CGFLOAT_IS_DOUBLE
    return [objc_getAssociatedObject(self, _cmd) doubleValue];
#else
    return [objc_getAssociatedObject(self, _cmd) floatValue];
#endif
}

- (void)setHjf_interactivePopMaxAllowedInitialDistanceToLeftEdge:(CGFloat)distance
{
    SEL key = @selector(hjf_interactivePopMaxAllowedInitialDistanceToLeftEdge);
    objc_setAssociatedObject(self, key, @(MAX(0, distance)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end





