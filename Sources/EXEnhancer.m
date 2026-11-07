#import "EXEnhancer.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>

@implementation EXEnhancer

+ (BOOL)upscaleURL:(NSURL *)source
             toURL:(NSURL *)destination
             scale:(CGFloat)scale
      maxDimension:(CGFloat)maxDimension
             error:(NSError **)error {
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)source, NULL);
    if (imageSource == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"EXEnhancer" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"读不出这张照片"}];
        }
        return NO;
    }
    CFStringRef type = CGImageSourceGetType(imageSource);
    CGImageRef image = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    CFDictionaryRef copied = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
    CFRelease(imageSource);

    if (image == NULL || type == NULL) {
        if (image) {
            CGImageRelease(image);
        }
        if (error) {
            *error = [NSError errorWithDomain:@"EXEnhancer" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"解不出这张图片"}];
        }
        return NO;
    }

    CGFloat longSide = (CGFloat)MAX(CGImageGetWidth(image), CGImageGetHeight(image));
    CGFloat effective = scale;
    if (longSide > 0 && longSide * effective > maxDimension) {
        effective = maxDimension / longSide;
    }
    if (effective < 1.0) {
        effective = 1.0;
    }

    CIImage *ciImage = [CIImage imageWithCGImage:image];
    if (effective > 1.001) {
        CIFilter *lanczos = [CIFilter filterWithName:@"CILanczosScaleTransform"];
        if (lanczos != nil) {
            [lanczos setValue:ciImage forKey:kCIInputImageKey];
            [lanczos setValue:@(effective) forKey:kCIInputScaleKey];
            [lanczos setValue:@1.0 forKey:kCIInputAspectRatioKey];
            if (lanczos.outputImage != nil) {
                ciImage = lanczos.outputImage;

                CIFilter *sharpen = [CIFilter filterWithName:@"CIUnsharpMask"];
                if (sharpen != nil) {
                    [sharpen setValue:ciImage forKey:kCIInputImageKey];
                    [sharpen setValue:@2.0 forKey:@"inputRadius"];
                    [sharpen setValue:@0.6 forKey:@"inputIntensity"];
                    if (sharpen.outputImage != nil) {
                        ciImage = sharpen.outputImage;
                    }
                }
            }
        }
    }
    CGImageRelease(image);

    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef output = [context createCGImage:ciImage fromRect:ciImage.extent];
    if (output == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"EXEnhancer" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"放大处理失败"}];
        }
        if (copied) {
            CFRelease(copied);
        }
        return NO;
    }

    NSMutableDictionary *properties = copied ? [(__bridge_transfer NSDictionary *)copied mutableCopy]
                                             : [NSMutableDictionary dictionary];
    [properties removeObjectForKey:(NSString *)kCGImagePropertyPixelWidth];
    [properties removeObjectForKey:(NSString *)kCGImagePropertyPixelHeight];
    [properties removeObjectForKey:(NSString *)kCGImagePropertyDepth];
    properties[(NSString *)kCGImageDestinationLossyCompressionQuality] = @0.95;

    CGImageDestinationRef destinationRef = CGImageDestinationCreateWithURL((__bridge CFURLRef)destination, type, 1, NULL);
    if (destinationRef == NULL) {
        CGImageRelease(output);
        if (error) {
            *error = [NSError errorWithDomain:@"EXEnhancer" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法写出放大后的图片"}];
        }
        return NO;
    }
    CGImageDestinationAddImage(destinationRef, output, (__bridge CFDictionaryRef)properties);
    BOOL ok = CGImageDestinationFinalize(destinationRef);
    CFRelease(destinationRef);
    CGImageRelease(output);

    if (!ok && error) {
        *error = [NSError errorWithDomain:@"EXEnhancer" code:5
                                 userInfo:@{NSLocalizedDescriptionKey: @"写出放大后的图片失败"}];
    }
    return ok;
}

@end
