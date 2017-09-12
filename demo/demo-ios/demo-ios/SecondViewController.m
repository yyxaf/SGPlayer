//
//  SecondViewController.m
//  demo-ios
//
//  Created by 徐鳌飞 on 2017/9/5.
//  Copyright © 2017年 single. All rights reserved.
//

#import "SecondViewController.h"
#import <SGPlayer/SGPlayer.h>


@interface SecondViewController ()
@property (nonatomic, strong) SGPlayer * player;
@end

@implementation SecondViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor lightGrayColor];
    
    self.player = [SGPlayer player];
    [self.player registerPlayerNotificationTarget:self
                                      stateAction:@selector(stateAction:)
                                   progressAction:@selector(progressAction:)
                                   playableAction:@selector(playableAction:)
                                      errorAction:@selector(errorAction:)];
    
    [self.view insertSubview:self.player.view atIndex:0];

    self.player.decoder = [SGPlayerDecoder decoderByFFmpeg];
    self.player.decoder.hardwareAccelerateEnableForFFmpeg = YES;
    self.player.decoder.optimizedDelayForFFmpeg = YES;
    self.player.decoder.optimizedmaxFrameQueueDuration = 0.2f;
    UIImage *image = [UIImage imageNamed:@"PIC_20170809_311.jpg"];
    [self.player replaceImage:image videoType:SGVideoTypeVR];
    
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        UIImage *image = [UIImage imageNamed:@"Snip20170901_1.png"];
//        [self.player replaceImage:image videoType:SGVideoTypeNormal];
//    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.player.view.frame = self.view.bounds;
}

- (IBAction)action_pop:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)stateAction:(NSNotification *)notification
{
    SGState * state = [SGState stateFromUserInfo:notification.userInfo];
    
    NSString * text;
    switch (state.current) {
        case SGPlayerStateNone:
            text = @"None";
            break;
        case SGPlayerStateBuffering:
            text = @"Buffering...";
            break;
        case SGPlayerStateReadyToPlay:
            text = @"Prepare";
            [self.player play];
            break;
        case SGPlayerStatePlaying:
            text = @"Playing";
            break;
        case SGPlayerStateSuspend:
            text = @"Suspend";
            break;
        case SGPlayerStateFinished:
            text = @"Finished";
            break;
        case SGPlayerStateFailed:
            text = @"Error";
            break;
    }
}

- (void)progressAction:(NSNotification *)notification
{

}

- (void)playableAction:(NSNotification *)notification
{
    SGPlayable * playable = [SGPlayable playableFromUserInfo:notification.userInfo];
    NSLog(@"playable time : %f", playable.current);
}

- (void)errorAction:(NSNotification *)notification
{
    SGError * error = [SGError errorFromUserInfo:notification.userInfo];
    NSLog(@"player did error : %@", error.error);
}


@end
