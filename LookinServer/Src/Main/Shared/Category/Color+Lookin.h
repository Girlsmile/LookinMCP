#ifdef SHOULD_COMPILE_LOOKIN_SERVER 

//
//  Color+Lookin.h
//  LookinShared
//
//  Created by 李凯 on 2022/4/2.
//

#import <Foundation/Foundation.h>
#import "TargetConditionals.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
#import <AppKit/AppKit.h>
#endif

#if TARGET_OS_IPHONE

#elif TARGET_OS_MAC

@interface NSColor (Lookin)

+ (instancetype)lookin_colorFromRGBAComponents:(NSArray<NSNumber *> *)components;

- (NSArray<NSNumber *> *)lookin_rgbaComponents;

@end

#endif


#endif /* SHOULD_COMPILE_LOOKIN_SERVER */
