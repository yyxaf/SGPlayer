//
//  SGFFVideoToolBox.m
//  SGPlayer
//
//  Created by Single on 2017/2/21.
//  Copyright © 2017年 single. All rights reserved.
//

#import <SGPlatform/SGPlatform.h>
#import "SGFFVideoToolBox.h"
#import "SGPlayerNotification.h"
#import <libavutil/intreadwrite.h>

typedef NS_ENUM(NSUInteger, SGFFVideoToolBoxErrorCode) {
    SGFFVideoToolBoxErrorCodeExtradataSize,
    SGFFVideoToolBoxErrorCodeExtradataData,
    SGFFVideoToolBoxErrorCodeCreateFormatDescription,
    SGFFVideoToolBoxErrorCodeCreateSession,
    SGFFVideoToolBoxErrorCodeNotH264,
};

@interface SGFFVideoToolBox ()

{
    AVCodecContext * _codec_context;
    VTDecompressionSessionRef _vt_session;
    CMFormatDescriptionRef _format_description;
    
@public
    OSStatus _decode_status;
    CVImageBufferRef _decode_output;
}

@property (nonatomic, assign) BOOL vtSessionToken;
@property (nonatomic, assign) BOOL needConvertNALSize3To4;
@property (nonatomic, assign) BOOL needConvertByteStream;
@end


@implementation SGFFVideoToolBox

+ (instancetype)videoToolBoxWithCodecContext:(AVCodecContext *)codecContext
{
    return [[self alloc] initWithCodecContext:codecContext];
}

- (instancetype)initWithCodecContext:(AVCodecContext *)codecContext
{
    if (self = [super init]) {
        self->_codec_context = codecContext;
    }
    return self;
}

- (BOOL)trySetupVTSession
{
    if (!self.vtSessionToken) {
        NSError * error = [self setupVTSession];
        if (!error) {
            self.vtSessionToken = YES;
        }
    }
    return self.vtSessionToken;
}

- (NSError *)setupVTSession
{
    NSError * error;
    
    enum AVCodecID codec_id = self->_codec_context->codec_id;
    uint8_t * extradata = self->_codec_context->extradata;
    int extradata_size = self->_codec_context->extradata_size;
    int extrasize = extradata_size;
    
    if (codec_id == AV_CODEC_ID_H264) {
        if (extradata_size < 7 || extradata == NULL) {
            error = [NSError errorWithDomain:@"extradata error" code:SGFFVideoToolBoxErrorCodeExtradataSize userInfo:nil];
            return error;
        }

        if (extradata[0] == 1) {
            if (extradata[4] == 0xFE) {
                extradata[4] = 0xFF;
                self.needConvertNALSize3To4 = YES;
            }
            

            self->_format_description = CreateFormatDescription(kCMVideoCodecType_H264, _codec_context->width, _codec_context->height, extradata, extradata_size);
            if (self->_format_description == NULL) {
                error = [NSError errorWithDomain:@"create format description error" code:SGFFVideoToolBoxErrorCodeCreateFormatDescription userInfo:nil];
                return error;
            }
            
            CFMutableDictionaryRef destinationPixelBufferAttributes = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            cf_dict_set_int32(destinationPixelBufferAttributes, kCVPixelBufferPixelFormatTypeKey, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
            cf_dict_set_int32(destinationPixelBufferAttributes, kCVPixelBufferWidthKey, _codec_context->width);
            cf_dict_set_int32(destinationPixelBufferAttributes, kCVPixelBufferHeightKey, _codec_context->height);
            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLCompatibilityKey, YES);

#if SGPLATFORM_TARGET_OS_MAC
//            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLCompatibilityKey, YES);
//            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLTextureCacheCompatibilityKey, YES);
#elif SGPLATFORM_TARGET_OS_IPHONE
//            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLESCompatibilityKey, YES);
//            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLESTextureCacheCompatibilityKey, YES);
#endif
            
            VTDecompressionOutputCallbackRecord outputCallbackRecord;
            outputCallbackRecord.decompressionOutputCallback = outputCallback;
            outputCallbackRecord.decompressionOutputRefCon = (__bridge void *)self;
            
            OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault, self->_format_description, NULL, destinationPixelBufferAttributes, &outputCallbackRecord, &self->_vt_session);
            if (status != noErr) {
                error = [NSError errorWithDomain:@"create session error" code:SGFFVideoToolBoxErrorCodeCreateSession userInfo:nil];
                return error;
            }
            CFRelease(destinationPixelBufferAttributes);
            return nil;
        } else {
            {
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    self->_codec_context->width = 0;
                    self->_codec_context->height = 0;
                });
                
                if ((extradata[0] == 0 && extradata[1] == 0 && extradata[2] == 0 && extradata[3] == 1) ||
                    (extradata[0] == 0 && extradata[1] == 0 && extradata[2] == 1)) {
                    AVIOContext *pb;
                    if (avio_open_dyn_buf(&pb) < 0) {
                        error = [NSError errorWithDomain:@"deal extradata error" code:SGFFVideoToolBoxErrorCodeExtradataData userInfo:nil];
                        return error;
                    }
                    
                    self.needConvertByteStream = YES;

                    int width = 0;
                    int height = 0;
                    ff_get_video_resolution(extradata, extrasize, &width, &height);
                    if (height % 10 != 0) {
                        if ((height + 8) % 10 == 0) {
                            height += 8;
                        }
                        else if ((height - 8) % 10 == 0) {
                            height -= 8;
                        }
                    }
                    
                    
                    if (_codec_context->width != width || _codec_context->height != height) {
                        _codec_context->width = width;
                        _codec_context->height= height;
                        
                        NSDictionary * userInfo = @{
                                                    SGPlayerVideoResolutionWidthChangeKey : [NSNumber numberWithInteger:width] ,
                                                    SGPlayerVideoResolutionHeightChangeKey : [NSNumber numberWithInteger:height],
                                                    };
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter] postNotificationName:SGPlayerVideoResolutionChangeNotificationName object:nil userInfo:userInfo];
                        });
                    }

                    
                    ff_isom_write_avcc(pb, extradata, extrasize);
                    extradata = NULL;
                    
                    extradata_size = avio_close_dyn_buf(pb, &extradata);
                    
                    self->_format_description = CreateFormatDescription(kCMVideoCodecType_H264, _codec_context->width, _codec_context->height, extradata, extradata_size);
                    
                    
                    if (self->_format_description == NULL) {
                        error = [NSError errorWithDomain:@"create format description error" code:SGFFVideoToolBoxErrorCodeCreateFormatDescription userInfo:nil];
                        return error;
                    }
                    
                    CFMutableDictionaryRef destinationPixelBufferAttributes = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                    cf_dict_set_int32(destinationPixelBufferAttributes, kCVPixelBufferPixelFormatTypeKey, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
                    cf_dict_set_int32(destinationPixelBufferAttributes, kCVPixelBufferWidthKey, _codec_context->width);
                    cf_dict_set_int32(destinationPixelBufferAttributes, kCVPixelBufferHeightKey, _codec_context->height);
                    cf_dict_set_boolean(destinationPixelBufferAttributes,
                                        kCVPixelBufferOpenGLESCompatibilityKey, YES);
                    
#if SGPLATFORM_TARGET_OS_MAC
                    //            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLCompatibilityKey, YES);
                    //            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLTextureCacheCompatibilityKey, YES);
#elif SGPLATFORM_TARGET_OS_IPHONE
                    //            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLESCompatibilityKey, YES);
                    //                            cf_dict_set_boolean(destinationPixelBufferAttributes, kCVPixelBufferOpenGLESTextureCacheCompatibilityKey, YES);
#endif
                    
                    VTDecompressionOutputCallbackRecord outputCallbackRecord;
                    outputCallbackRecord.decompressionOutputCallback = outputCallback;
                    outputCallbackRecord.decompressionOutputRefCon = (__bridge void *)self;
                    
                    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault, self->_format_description, NULL, destinationPixelBufferAttributes, &outputCallbackRecord, &self->_vt_session);
                    if (status != noErr) {
                        error = [NSError errorWithDomain:@"create session error" code:SGFFVideoToolBoxErrorCodeCreateSession userInfo:nil];
                        return error;
                    }
                    CFRelease(destinationPixelBufferAttributes);
                    return nil;
                }
                else {
                    error = [NSError errorWithDomain:@"deal extradata error" code:SGFFVideoToolBoxErrorCodeExtradataData userInfo:nil];
                    return error;
                }
            }
        }
    } else {
        error = [NSError errorWithDomain:@"not h264 error" code:SGFFVideoToolBoxErrorCodeNotH264 userInfo:nil];
        return error;
    }
    
    return error;
}

- (void)cleanVTSession
{
    if (self->_format_description) {
        CFRelease(self->_format_description);
        self->_format_description = NULL;
    }
    if (self->_vt_session) {
        VTDecompressionSessionWaitForAsynchronousFrames(self->_vt_session);
        VTDecompressionSessionInvalidate(self->_vt_session);
        CFRelease(self->_vt_session);
        self->_vt_session = NULL;
    }
    self.needConvertNALSize3To4 = NO;
    self.vtSessionToken = NO;
}

- (void)cleanDecodeInfo
{
    self->_decode_status = noErr;
    self->_decode_output = NULL;
}

- (BOOL)sendPacket:(AVPacket)packet needFlush:(BOOL *)needFlush
{
    uint8_t *extradata = packet.data;
    
    int extradata_size = 0;
    if ((extradata[0] == 0 && extradata[1] == 0 && extradata[2] == 0 && extradata[3] == 1) ||
        (extradata[0] == 0 && extradata[1] == 0 && extradata[2] == 1)) {
        
        if (packet.size > 100) {
            
            int ret = ff_find_extradata(packet.data,100,&extradata_size);
            if (ret != AVERROR_INVALIDDATA) {
                if (extradata_size != _codec_context->extradata_size || memcmp(extradata, _codec_context->extradata, extradata_size)) {
                    
                    if (extradata_size > 0) {
                        av_realloc(_codec_context->extradata, extradata_size);
                        memcpy(_codec_context->extradata, extradata, extradata_size);
                        _codec_context->extradata_size = extradata_size;
                        
                        [self cleanVTSession];
                        return NO;
                    }
                }
            }
        }
    }
    

    BOOL setupResult = [self trySetupVTSession];
    if (!setupResult) return NO;
    [self cleanDecodeInfo];
    
    BOOL result = NO;
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = noErr;
    
    uint8_t * demux_buffer = NULL;
    int demux_size                  = 0;
    
    if (self.needConvertNALSize3To4) {
        AVIOContext * io_context = NULL;
        if (avio_open_dyn_buf(&io_context) < 0) {
            status = -1900;
        } else {
            uint32_t nal_size;
            uint8_t * end = packet.data + packet.size;
            uint8_t * nal_start = packet.data;
            while (nal_start < end) {
                nal_size = (nal_start[0] << 16) | (nal_start[1] << 8) | nal_start[2];
                avio_wb32(io_context, nal_size);
                nal_start += 3;
                avio_write(io_context, nal_start, nal_size);
                nal_start += nal_size;
            }
            uint8_t * demux_buffer = NULL;
            int demux_size = avio_close_dyn_buf(io_context, &demux_buffer);
            status = CMBlockBufferCreateWithMemoryBlock(NULL, demux_buffer, demux_size, kCFAllocatorNull, NULL, 0, packet.size, FALSE, &blockBuffer);
        }
    } else if (self.needConvertByteStream) {
        
        AVIOContext *pb                 = NULL;
        uint8_t *pData                  = packet.data;
        int iSize                       = packet.size;
        
        if(avio_open_dyn_buf(&pb) < 0) {
            status = -1900;
        }
        ff_avc_parse_nal_units(pb, pData, iSize);
        demux_size = avio_close_dyn_buf(pb, &demux_buffer);
        
        if (demux_size == 0) {
            status = -1900;
        }
        status = CMBlockBufferCreateWithMemoryBlock(NULL, demux_buffer, demux_size, kCFAllocatorNull, NULL, 0, packet.size, FALSE, &blockBuffer);
    } else {
        status = CMBlockBufferCreateWithMemoryBlock(NULL, packet.data, packet.size, kCFAllocatorNull, NULL, 0, packet.size, FALSE, &blockBuffer);
    }
    
    if (status == noErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        status = CMSampleBufferCreate( NULL, blockBuffer, TRUE, 0, 0, self->_format_description, 1, 0, NULL, 0, NULL, &sampleBuffer);
        
        if (status == noErr) {
            status = VTDecompressionSessionDecodeFrame(self->_vt_session, sampleBuffer, 0, NULL, 0);
            if (status == noErr) {
                if (self->_decode_status == noErr && self->_decode_output != NULL) {
                    result = YES;
                }
            } else if (status == kVTInvalidSessionErr) {
                * needFlush = YES;
            }
        }
        if (sampleBuffer) {
            CFRelease(sampleBuffer);
        }
    }
    if (blockBuffer) {
        CFRelease(blockBuffer);
    }
    if (demux_size) {
        av_free(demux_buffer);
    }
    return result;
}

- (CVImageBufferRef)imageBuffer
{
    if (self->_decode_status == noErr && self->_decode_output != NULL) {
        return self->_decode_output;
    }
    return NULL;
}

- (void)flush
{
    [self cleanVTSession];
    [self cleanDecodeInfo];
}

- (void)dealloc
{
    [self flush];
}

static void outputCallback(void * decompressionOutputRefCon, void * sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration)
{
    @autoreleasepool
    {
        SGFFVideoToolBox * videoToolBox = (__bridge SGFFVideoToolBox *)decompressionOutputRefCon;
        videoToolBox->_decode_status = status;
        videoToolBox->_decode_output = imageBuffer;
        if (imageBuffer != NULL) {
            CVPixelBufferRetain(imageBuffer);
        }
    }
}

static CMFormatDescriptionRef CreateFormatDescription(CMVideoCodecType codec_type, int width, int height, const uint8_t * extradata, int extradata_size)
{
    CMFormatDescriptionRef format_description = NULL;
    OSStatus status;
    
    CFMutableDictionaryRef par = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef atoms = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef extensions = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    // CVPixelAspectRatio
    cf_dict_set_int32(par, CFSTR("HorizontalSpacing"), 0);
    cf_dict_set_int32(par, CFSTR("VerticalSpacing"), 0);
    
    // SampleDescriptionExtensionAtoms
    cf_dict_set_data(atoms, CFSTR("avcC"), (uint8_t *)extradata, extradata_size);
    
    // Extensions
    cf_dict_set_string(extensions, CFSTR ("CVImageBufferChromaLocationBottomField"), "left");
    cf_dict_set_string(extensions, CFSTR ("CVImageBufferChromaLocationTopField"), "left");
    cf_dict_set_boolean(extensions, CFSTR("FullRangeVideo"), FALSE);
    cf_dict_set_object(extensions, CFSTR ("CVPixelAspectRatio"), (CFTypeRef *)par);
    cf_dict_set_object(extensions, CFSTR ("SampleDescriptionExtensionAtoms"), (CFTypeRef *)atoms);
    
    status = CMVideoFormatDescriptionCreate(NULL, codec_type, width, height, extensions, &format_description);
    
    CFRelease(extensions);
    CFRelease(atoms);
    CFRelease(par);
    
    if (status != noErr) {
        return NULL;
    }
    return format_description;
}

static void cf_dict_set_data(CFMutableDictionaryRef dict, CFStringRef key, uint8_t * value, uint64_t length)
{
    CFDataRef data;
    data = CFDataCreate(NULL, value, (CFIndex)length);
    CFDictionarySetValue(dict, key, data);
    CFRelease(data);
}

static void cf_dict_set_int32(CFMutableDictionaryRef dict, CFStringRef key, int32_t value)
{
    CFNumberRef number;
    number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(dict, key, number);
    CFRelease(number);
}

static void cf_dict_set_string(CFMutableDictionaryRef dict, CFStringRef key, const char * value)
{
    CFStringRef string;
    string = CFStringCreateWithCString(NULL, value, kCFStringEncodingASCII);
    CFDictionarySetValue(dict, key, string);
    CFRelease(string);
}

static void cf_dict_set_boolean(CFMutableDictionaryRef dict, CFStringRef key, BOOL value)
{
    CFDictionarySetValue(dict, key, value ? kCFBooleanTrue: kCFBooleanFalse);
}

static void cf_dict_set_object(CFMutableDictionaryRef dict, CFStringRef key, CFTypeRef *value)
{
    CFDictionarySetValue(dict, key, value);
}

#pragma mark - add
static const uint8_t *ff_avc_find_startcode_internal(const uint8_t *p, const uint8_t *end)
{
    const uint8_t *a = p + 4 - ((intptr_t)p & 3);
    
    for (end -= 3; p < a && p < end; p++) {
        if (p[0] == 0 && p[1] == 0 && p[2] == 1)
            return p;
    }
    
    for (end -= 3; p < end; p += 4) {
        uint32_t x = *(const uint32_t*)p;
        //      if ((x - 0x01000100) & (~x) & 0x80008000) // little endian
        //      if ((x - 0x00010001) & (~x) & 0x00800080) // big endian
        if ((x - 0x01010101) & (~x) & 0x80808080) { // generic
            if (p[1] == 0) {
                if (p[0] == 0 && p[2] == 1)
                    return p;
                if (p[2] == 0 && p[3] == 1)
                    return p+1;
            }
            if (p[3] == 0) {
                if (p[2] == 0 && p[4] == 1)
                    return p+2;
                if (p[4] == 0 && p[5] == 1)
                    return p+3;
            }
        }
    }
    
    for (end += 3; p < end; p++) {
        if (p[0] == 0 && p[1] == 0 && p[2] == 1)
            return p;
    }
    
    return end + 3;
}

const uint8_t *ff_avc_find_startcode(const uint8_t *p, const uint8_t *end){
    const uint8_t *out= ff_avc_find_startcode_internal(p, end);
    if(p<out && out<end && !out[-1]) out--;
    return out;
}

int ff_avc_parse_nal_units(AVIOContext *pb, const uint8_t *buf_in, int size)
{
    const uint8_t *p = buf_in;
    const uint8_t *end = p + size;
    const uint8_t *nal_start, *nal_end;
    
    size = 0;
    nal_start = ff_avc_find_startcode(p, end);
    for (;;) {
        while (nal_start < end && !*(nal_start++));
        if (nal_start == end)
            break;
        
        nal_end = ff_avc_find_startcode(nal_start, end);
        avio_wb32(pb, nal_end - nal_start);
        avio_write(pb, nal_start, nal_end - nal_start);
        size += 4 + nal_end - nal_start;
        nal_start = nal_end;
    }
    return size;
}

int ff_avc_parse_nal_units_buf(const uint8_t *buf_in, uint8_t **buf, int *size)
{
    AVIOContext *pb;
    int ret = avio_open_dyn_buf(&pb);
    if(ret < 0)
        return ret;
    
    ff_avc_parse_nal_units(pb, buf_in, *size);
    
    av_freep(buf);
    *size = avio_close_dyn_buf(pb, buf);
    return 0;
}


int ff_isom_write_avcc(AVIOContext *pb, const uint8_t *data, int len)
{
    if (len > 6) {
        /* check for H.264 start code */
        if (AV_RB32(data) == 0x00000001 ||
            AV_RB24(data) == 0x000001) {
            uint8_t *buf=NULL, *end, *start;
            uint32_t sps_size=0, pps_size=0;
            uint8_t *sps=0, *pps=0;
            
            int ret = ff_avc_parse_nal_units_buf(data, &buf, &len);
            if (ret < 0)
                return ret;
            start = buf;
            end = buf + len;
            
            /* look for sps and pps */
            while (end - buf > 4) {
                uint32_t size;
                uint8_t nal_type;
                size = FFMIN(AV_RB32(buf), end - buf - 4);
                buf += 4;
                nal_type = buf[0] & 0x1f;
                
                if (nal_type == 6) {
                    NSInteger i = 0;
                    i++;
                }
                
                if (nal_type == 7) { /* SPS */
                    sps = buf;
                    sps_size = size;
                    
                } else if (nal_type == 8) { /* PPS */
                    pps = buf;
                    pps_size = size;
                }
                
                buf += size;
            }
            
            if (!sps || !pps || sps_size < 4 || sps_size > UINT16_MAX || pps_size > UINT16_MAX)
            {
                av_free(start);
                return AVERROR_INVALIDDATA;
            }
            
            
            avio_w8(pb, 1); /* version */
            avio_w8(pb, sps[1]); /* profile */
            avio_w8(pb, sps[2]); /* profile compat */
            avio_w8(pb, sps[3]); /* level */
            avio_w8(pb, 0xff); /* 6 bits reserved (111111) + 2 bits nal size length - 1 (11) */
            avio_w8(pb, 0xe1); /* 3 bits reserved (111) + 5 bits number of sps (00001) */
            
            avio_wb16(pb, sps_size);
            avio_write(pb, sps, sps_size);
            avio_w8(pb, 1); /* number of pps */
            avio_wb16(pb, pps_size);
            avio_write(pb, pps, pps_size);
            av_free(start);
        } else {
            avio_write(pb, data, len);
        }
    }
    return 0;
}

int ff_find_extradata(const uint8_t *data, int dataLen, int* extradata_size)
{
    int ret_find_extradata = 1;
    if (dataLen > 6) {
        /* check for H.264 start code */
        if (AV_RB32(data) == 0x00000001 ||
            AV_RB24(data) == 0x000001) {
            uint8_t *buf=NULL, *end, *start;
            uint32_t sps_size=0, pps_size=0;
            uint8_t *sps=0, *pps=0;
            
            int ret = ff_avc_parse_nal_units_buf(data, &buf, &dataLen);
            if (ret < 0)
                return ret;
            start = buf;
            end = buf + dataLen;
            
            /* look for sps and pps */
            while (end - buf > 4) {
                uint32_t size;
                uint8_t nal_type;
                size = FFMIN(AV_RB32(buf), end - buf - 4);
                buf += 4;
                nal_type = buf[0] & 0x1f;

                if (nal_type == 7) { /* SPS */
                    sps = buf;
                    sps_size = size;
                    
                    *extradata_size += 4;
                    *extradata_size += sps_size;

                } else if (nal_type == 8) { /* PPS */
                    pps = buf;
                    pps_size = size;
                    
                    *extradata_size += 4;
                    *extradata_size += pps_size;
                }
                
                buf += size;
            }
            
            av_free(start);
            if (!sps || !pps || sps_size < 4 || sps_size > UINT16_MAX || pps_size > UINT16_MAX)
                return AVERROR_INVALIDDATA;
            
        } else {
            return AVERROR_INVALIDDATA;
        }
    }
    return ret_find_extradata;
}

int ff_avc_write_annexb_extradata(const uint8_t *in, uint8_t **buf, int *size)
{
    uint16_t sps_size, pps_size;
    uint8_t *out;
    int out_size;
    
    *buf = NULL;
    if (*size >= 4 && (AV_RB32(in) == 0x00000001 || AV_RB24(in) == 0x000001))
        return 0;
    if (*size < 11 || in[0] != 1)
        return AVERROR_INVALIDDATA;
    
    sps_size = AV_RB16(&in[6]);
    if (11 + sps_size > *size)
        return AVERROR_INVALIDDATA;
    pps_size = AV_RB16(&in[9 + sps_size]);
    if (11 + sps_size + pps_size > *size)
        return AVERROR_INVALIDDATA;
    out_size = 8 + sps_size + pps_size;
    out = av_mallocz(out_size + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!out)
        return AVERROR(ENOMEM);
    AV_WB32(&out[0], 0x00000001);
    memcpy(out + 4, &in[8], sps_size);
    AV_WB32(&out[4 + sps_size], 0x00000001);
    memcpy(out + 8 + sps_size, &in[11 + sps_size], pps_size);
    *buf = out;
    *size = out_size;
    return 0;
}

const uint8_t *ff_avc_mp4_find_startcode(const uint8_t *start,
                                         const uint8_t *end,
                                         int nal_length_size)
{
    unsigned int res = 0;
    
    if (end - start < nal_length_size)
        return NULL;
    while (nal_length_size--)
        res = (res << 8) | *start++;
    
    if (res > end - start)
        return NULL;
    
    return start + res;
}

void ff_get_video_resolution(uint8_t *extradata, int extradata_size, int *width, int *height)
{
    uint8_t *data = extradata;
    int len = extradata_size;
    
    if (len > 6) {
        /* check for H.264 start code */
        if (AV_RB32(data) == 0x00000001 ||
            AV_RB24(data) == 0x000001) {
            uint8_t *buf=NULL, *end, *start;
            uint32_t sps_size=0, pps_size=0;
            uint8_t *sps=0, *pps=0;
            
            int ret = ff_avc_parse_nal_units_buf(data, &buf, &len);
            if (ret < 0)
                return;
            start = buf;
            end = buf + len;
            
            /* look for sps and pps */
            while (end - buf > 4) {
                uint32_t size;
                uint8_t nal_type;
                size = FFMIN(AV_RB32(buf), end - buf - 4);
                buf += 4;
                nal_type = buf[0] & 0x1f;
                
                if (nal_type == 7) { /* SPS */
                    sps = buf;
                    sps_size = size;
                    
                } else if (nal_type == 8) { /* PPS */
                    pps = buf;
                    pps_size = size;
                }
                
                buf += size;
            }

            if (!sps || !pps || sps_size < 4 || sps_size > UINT16_MAX || pps_size > UINT16_MAX)
            {
                av_free(start);
                return;
            }

            int bitsCount = sps_size * 8 * sizeof(uint8_t);
            uint8_t *bits = malloc(bitsCount);
            for (int i = 0; i < sps_size; i++)
            {
                for (int j = 0; j < 8; j++)
                {
                    if ((sps[i] << j) & 0x80)
                    {
                        bits[i * 8 + j] = 1;
                    }
                    else
                    {
                        bits[i * 8 + j] = 0;
                    }
                }
            }

            int sps_bits_index = 0;
            int loopIndex = 0;
            while (sps_bits_index <= bitsCount) {
                loopIndex++;
                int leadingZeroBits = -1;
                for (int b = 0; !b && leadingZeroBits < bitsCount - sps_bits_index; leadingZeroBits++)
                {
                    b = bits[sps_bits_index++];
                }
                
                
                int value = 0;
                for (int leadingZeroBitsIndex = 0; leadingZeroBitsIndex < leadingZeroBits; leadingZeroBitsIndex++) {
                    int temp = bits[sps_bits_index++];
                    value = value << 1;
                    value += temp;
                }
                
                int codeNum = pow(2,leadingZeroBits) - 1 + value;
                
                if (loopIndex == 11) {
                    *width = (codeNum + 1) * 16;
                }
                if (loopIndex == 12) {
                    *height = (codeNum + 1) *16;
                }
            }
            free(bits);
            av_free(start);
        }
    }
}
@end
