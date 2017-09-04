//
//  SGImagePlayer.h
//  SGPlayer
//
//  Created by 徐鳌飞 on 2017/8/31.
//  Copyright © 2017年 single. All rights reserved.
//
#import "SGPlayerImp.h"
#import <Foundation/Foundation.h>

@protocol SGImagePlayerOutput <NSObject>
- (UIImage*)imagePlayerOutputGetImage;
@end


@interface SGImagePlayer : NSObject<SGImagePlayerOutput>
+ (instancetype)new NS_UNAVAILABLE;
+ (instancetype)init NS_UNAVAILABLE;

+ (instancetype)playerWithAbstractPlayer:(SGPlayer *)abstractPlayer;

@property (nonatomic, weak, readonly) SGPlayer * abstractPlayer;

@property (nonatomic, assign, readonly) SGPlayerState state;

- (void)replaceImage;
@end
