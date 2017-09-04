//
//  SGGLProgramRGBA.m
//  SGPlayer
//
//  Created by 徐鳌飞 on 2017/9/4.
//  Copyright © 2017年 single. All rights reserved.
//

#import "SGGLProgramRGBA.h"
#define SG_GLES_STRINGIZE(x) #x

static const char vertexShaderString[] = SG_GLES_STRINGIZE
(
 attribute vec4 position;
 attribute vec2 textureCoord;
 uniform mat4 mvp_matrix;
 varying vec2 v_textureCoord;
 
 void main()
 {
     v_textureCoord = textureCoord;
     gl_Position = mvp_matrix * position;
 }
 );

#if SGPLATFORM_TARGET_OS_MAC
static const char fragmentShaderString[] = SG_GLES_STRINGIZE
(
 uniform sampler2D u_Texture;
 varying mediump vec2 v_textureCoord;
 
 void main()
 {
     gl_FragColor =  texture2D(u_Texture, v_textureCoord);
 }
 );
#elif SGPLATFORM_TARGET_OS_IPHONE_OR_TV
static const char fragmentShaderString[] = SG_GLES_STRINGIZE
(
 uniform sampler2D u_Texture;
 varying mediump vec2 v_textureCoord;
 
 void main()
 {
     gl_FragColor =  texture2D(u_Texture, v_textureCoord);
 }
 );
#endif

@implementation SGGLProgramRGBA

+ (instancetype)program
{
    return [self programWithVertexShader:[NSString stringWithUTF8String:vertexShaderString]
                          fragmentShader:[NSString stringWithUTF8String:fragmentShaderString]];
}

- (void)bindVariable
{
    glEnableVertexAttribArray(self.position_location);
    glEnableVertexAttribArray(self.texture_coord_location);
    
    glUniform1i(self.sampler, 0);
}

- (void)setupVariable
{
    self.position_location = glGetAttribLocation(self.program_id, "position");
    self.texture_coord_location = glGetAttribLocation(self.program_id, "textureCoord");
    self.matrix_location = glGetUniformLocation(self.program_id, "mvp_matrix");
    
    self.sampler = glGetUniformLocation(self.program_id, "u_Texture");
}
@end
