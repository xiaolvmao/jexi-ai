//
//  JXImageIO.m
//  jexi-ai
//

#import "JXImageIO.h"
#import "JXUpscaler.h"
#import <ImageIO/ImageIO.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <os/log.h>

static os_log_t JXSaveLog(void)
{
    static os_log_t log = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.liu.jexiai", "save"); });
    return log;
}

static NSError *JXIOError(NSString *message)
{
    return [NSError errorWithDomain:@"JXImageIOErrorDomain"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : message ?: @"error"}];
}

void JXNote(NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]],
                                                message];
    NSString *path = @"/var/mobile/jexi-ai-debug.log";
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
    os_log(JXSaveLog(), "%{public}@", message);
}

CVPixelBufferRef JXCreatePixelBufferFromImageData(NSData *data, UIImage **outPreview,
                                                  NSError **error)
{
    if (data.length == 0) {
        if (error) *error = JXIOError(@"空图片数据");
        return NULL;
    }
    UIImage *image = [UIImage imageWithData:data scale:1.0];
    if (!image || image.size.width < 1 || image.size.height < 1) {
        if (error) *error = JXIOError(@"无法解码这张照片");
        return NULL;
    }
    // Bake the EXIF orientation into pixels: draw through UIKit once, then copy
    // the upright result into a BGRA buffer.
    CGSize size = CGSizeMake(floor(image.size.width), floor(image.size.height));
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    UIImage *upright = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
    if (!upright.CGImage) {
        if (error) *error = JXIOError(@"无法归一化照片方向");
        return NULL;
    }

    size_t w = CGImageGetWidth(upright.CGImage);
    size_t h = CGImageGetHeight(upright.CGImage);
    CVPixelBufferRef buffer = JXCreateBGRABuffer(w, h);
    if (!buffer) {
        if (error) *error = JXIOError(@"内存不足：无法为这张照片分配缓冲区");
        return NULL;
    }
    CVPixelBufferLockBaseAddress(buffer, 0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), w, h, 8,
                                             CVPixelBufferGetBytesPerRow(buffer), cs,
                                             kCGImageAlphaNoneSkipFirst |
                                                 kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        CVPixelBufferRelease(buffer);
        if (error) *error = JXIOError(@"无法创建绘图上下文");
        return NULL;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), upright.CGImage);
    CGContextRelease(ctx);
    CVPixelBufferUnlockBaseAddress(buffer, 0);

    if (outPreview) {
        *outPreview = upright;
    }
    return buffer;
}

UIImage *JXImageFromPixelBuffer(CVPixelBufferRef buffer)
{
    if (!buffer) return nil;
    size_t w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer);
    CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), w, h, 8,
                                             CVPixelBufferGetBytesPerRow(buffer), cs,
                                             kCGImageAlphaNoneSkipFirst |
                                                 kCGBitmapByteOrder32Little);
    CGImageRef cg = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    if (ctx) CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    if (!cg) return nil;
    UIImage *image = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return image;
}

NSDictionary *JXImagePropertiesFromData(NSData *data)
{
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return nil;
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
    CFRelease(src);
    return props;
}

static NSDictionary *JXMetadataForUprightImage(NSDictionary *original, size_t w, size_t h)
{
    NSMutableDictionary *props = original ? [original mutableCopy] : [NSMutableDictionary dictionary];
    // Pixels are upright now, so orientation must be 1 in every place it is stored.
    props[(id)kCGImagePropertyOrientation] = @1;
    props[(id)kCGImagePropertyPixelWidth] = @(w);
    props[(id)kCGImagePropertyPixelHeight] = @(h);
    NSDictionary *tiff = props[(id)kCGImagePropertyTIFFDictionary];
    if (tiff) {
        NSMutableDictionary *t = [tiff mutableCopy];
        t[(id)kCGImagePropertyTIFFOrientation] = @1;
        props[(id)kCGImagePropertyTIFFDictionary] = t;
    }
    NSDictionary *exif = props[(id)kCGImagePropertyExifDictionary];
    if (exif) {
        NSMutableDictionary *e = [exif mutableCopy];
        e[(id)kCGImagePropertyExifPixelXDimension] = @(w);
        e[(id)kCGImagePropertyExifPixelYDimension] = @(h);
        // A thumbnail of the original would contradict the new picture.
        [e removeObjectForKey:@"Thumbnail"];
        props[(id)kCGImagePropertyExifDictionary] = e;
    }
    [props removeObjectForKey:@"Thumbnail"];
    return props;
}

static BOOL JXWriteJPEG(UIImage *image, NSDictionary *originalProperties, NSString *path,
                        NSError **error)
{
    CGImageRef cg = image.CGImage;
    if (!cg) {
        if (error) *error = JXIOError(@"结果图无效");
        return NO;
    }
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    NSDictionary *props = JXMetadataForUprightImage(originalProperties, w, h);
    os_log(JXSaveLog(), "writing %zux%zu jpeg, source keys=%{public}lu exif=%{public}d gps=%{public}d",
           w, h, (unsigned long)originalProperties.count,
           props[(id)kCGImagePropertyExifDictionary] != nil,
           props[(id)kCGImagePropertyGPSDictionary] != nil);
    JXNote(@"save: %zux%zu, source keys=%lu exif=%lu tiff=%lu gps=%lu -> exif=%lu gps=%lu",
           w, h, (unsigned long)originalProperties.count,
           (unsigned long)[originalProperties[(id)kCGImagePropertyExifDictionary] count],
           (unsigned long)[originalProperties[(id)kCGImagePropertyTIFFDictionary] count],
           (unsigned long)[originalProperties[(id)kCGImagePropertyGPSDictionary] count],
           (unsigned long)[props[(id)kCGImagePropertyExifDictionary] count],
           (unsigned long)[props[(id)kCGImagePropertyGPSDictionary] count]);
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                CFSTR("public.jpeg"), 1, NULL);
    if (!dst) {
        if (error) *error = JXIOError(@"无法创建 JPEG 输出");
        return NO;
    }
    CGImageDestinationAddImage(dst, cg, (__bridge CFDictionaryRef)props);
    BOOL ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    if (!ok && error) *error = JXIOError(@"写入 JPEG 失败");
    return ok;
}

void JXSaveImageToPhotoLibrary(UIImage *image, NSDictionary *originalProperties,
                               void (^completion)(BOOL, NSError *))
{
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                               handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized &&
            status != PHAuthorizationStatusLimited) {
            NSError *err = JXIOError(@"没有相册写入权限。设置 ▸ 隐私与安全性 ▸ 照片 里允许 jexi-ai 添加照片。");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, err); });
            return;
        }
        NSString *tmp = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"jexi-ai-%@.jpg",
                                                                      [[NSUUID UUID] UUIDString]]];
        NSError *err = nil;
        if (!JXWriteJPEG(image, originalProperties, tmp, &err)) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, err); });
            return;
        }
        NSURL *fileURL = [NSURL fileURLWithPath:tmp];
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *opts = [PHAssetResourceCreationOptions new];
            opts.originalFilename = @"jexi-ai.jpg";
            [req addResourceWithType:PHAssetResourceTypePhoto fileURL:fileURL options:opts];
        } completionHandler:^(BOOL success, NSError *error) {
            [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
            NSError *out = error;
            if (!success && !out) out = JXIOError(@"保存到相册失败");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success, out); });
        }];
    }];
}
