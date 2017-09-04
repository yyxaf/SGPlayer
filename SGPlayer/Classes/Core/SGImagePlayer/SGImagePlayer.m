//
//  SGImagePlayer.m
//  SGPlayer
//
//  Created by 徐鳌飞 on 2017/8/31.
//  Copyright © 2017年 single. All rights reserved.
//

#import "SGImagePlayer.h"
#import "SGPlayer+DisplayView.h"
@interface SGImagePlayer()
@property (nonatomic, weak) SGPlayer * abstractPlayer;
@end


@implementation SGImagePlayer
+ (instancetype)playerWithAbstractPlayer:(SGPlayer *)abstractPlayer
{
    return [[self alloc] initWithAbstractPlayer:abstractPlayer];
}

- (instancetype)initWithAbstractPlayer:(SGPlayer *)abstractPlayer
{
    if (self = [super init]) {
        self.abstractPlayer = abstractPlayer;
        self.abstractPlayer.displayView.playerOutputIM = self;
        [self.abstractPlayer.displayView playerOutputTypeIM];
        [self.abstractPlayer.displayView rendererTypeOpenGL];
        
    }
    return self;
}

- (void)replaceImage {

}

#pragma mark - SGImagePlayerOutput
- (UIImage*)imagePlayerOutputGetImage
{
    return self.abstractPlayer.contentImage;
}
@end
