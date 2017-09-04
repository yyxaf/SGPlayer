//
//  SGGLTextureRGBA.m
//  SGPlayer
//
//  Created by 徐鳌飞 on 2017/9/1.
//  Copyright © 2017年 single. All rights reserved.
//

#import "SGGLTextureRGBA.h"
#import "SGPlayerMacro.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@interface SGGLTextureRGBA ()
@property (retain, nonatomic) UIImage *image;
@end

@implementation SGGLTextureRGBA
static GLuint gl_texture;

- (instancetype)init
{
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            glGenTextures(1, &gl_texture);
        });
    }
    return self;
}

- (BOOL)updateTextureWithGLFrame:(SGGLFrame *)glFrame aspect:(CGFloat *)aspect
{
    UIImage *image = [glFrame getImage];
    GLsizei textureWidth = image.size.width;
    GLsizei textureHeight = image.size.height;
    
    if (!image) {
        return NO;
    }
    
    if ([image isEqual:self.image]) {
        * aspect = (textureWidth * 1.0) / (textureHeight * 1.0);
        return YES;
    }
    
    self.image = image;
    * aspect = (textureWidth * 1.0) / (textureHeight * 1.0);
    
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, gl_texture);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
     void *imageData = malloc( textureWidth * textureHeight * 4 );
    CGContextRef context = CGBitmapContextCreate( imageData, textureWidth, textureHeight, 8, 4 * textureWidth, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big );
    CGColorSpaceRelease( colorSpace );
    CGContextClearRect( context, CGRectMake( 0, 0, textureWidth, textureHeight ) );
    CGContextDrawImage( context, CGRectMake( 0, 0, textureWidth, textureHeight ), image.CGImage );
    
    //glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureWidth, textureHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, imageData);
    CGContextRelease(context);
    free(imageData);

    return YES;
}


- (void)dealloc
{
    SGPlayerLog(@"SGAVGLTexture release");
}
@end
