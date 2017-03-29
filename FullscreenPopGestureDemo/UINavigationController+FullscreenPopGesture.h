//
//  UINavigationController+FullscreenPopGesture.h
//  FullscreenPopGestureDemo
//
//  Created by HE Jianfeng on 2017/3/28.
//  Copyright © 2017年 hjfrun. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UINavigationController (FullscreenPopGesture)

@property (nonatomic, strong, readonly) UIPanGestureRecognizer *hjf_fullscreenPopGestureRecognizer;

@property (nonatomic, assign) BOOL hjf_viewControllerBasedNavigationBarAppearanceEnabled;

@end

@interface UIViewController (FullscreenPopGesture)

@property (nonatomic, assign) BOOL hjf_interactivePopDisabled;

@property (nonatomic, assign) BOOL hjf_prefersNavigationBarHidden;

@property (nonatomic, assign) CGFloat hjf_interactivePopMaxAllowedInitialDistanceToLeftEdge;

@end
