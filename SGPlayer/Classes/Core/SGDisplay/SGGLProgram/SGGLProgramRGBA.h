//
//  SGGLProgramRGBA.h
//  SGPlayer
//
//  Created by 徐鳌飞 on 2017/9/4.
//  Copyright © 2017年 single. All rights reserved.
//

#import "SGGLProgram.h"

@interface SGGLProgramRGBA : SGGLProgram

+ (instancetype)program;

@property (nonatomic, assign) GLint sampler;
@end
