// metatest <source image> [<out.jpg>]
// Decodes a photo, writes it back as JPEG with the same metadata using the same
// ImageIO calls the app uses, then dumps what came out — to tell whether the
// metadata is lost on the way in or on the way out.
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

static NSDictionary *dump(NSDictionary *props, NSString *label)
{
    NSNumber *w = props[(id)kCGImagePropertyPixelWidth];
    NSNumber *h = props[(id)kCGImagePropertyPixelHeight];
    NSDictionary *exif = props[(id)kCGImagePropertyExifDictionary];
    NSDictionary *tiff = props[(id)kCGImagePropertyTIFFDictionary];
    NSDictionary *gps = props[(id)kCGImagePropertyGPSDictionary];
    printf("%s: %ldx%ld keys=%lu\n", label.UTF8String, (long)w.integerValue,
           (long)h.integerValue, (unsigned long)props.count);
    printf("   exif=%lu tiff=%lu gps=%lu time=%s model=%s\n",
           (unsigned long)exif.count, (unsigned long)tiff.count, (unsigned long)gps.count,
           [exif[(id)kCGImagePropertyExifDateTimeOriginal] description].UTF8String,
           [tiff[(id)kCGImagePropertyTIFFModel] description].UTF8String);
    printf("   keys: %s\n", [props.allKeys componentsJoinedByString:@","].UTF8String);
    return props;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: metatest <source> [out.jpg]\n");
            return 2;
        }
        NSString *inPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outPath = argc > 2 ? [NSString stringWithUTF8String:argv[2]]
                                     : @"/var/mobile/metatest-out.jpg";
        CGImageSourceRef src = CGImageSourceCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:inPath], NULL);
        if (!src) {
            fprintf(stderr, "cannot open source\n");
            return 1;
        }
        CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
        CFRelease(src);
        if (!image) {
            fprintf(stderr, "cannot decode source\n");
            return 1;
        }
        dump(props, @"source");

        NSMutableDictionary *out = [props mutableCopy];
        out[(id)kCGImagePropertyOrientation] = @1;
        size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
        out[(id)kCGImagePropertyPixelWidth] = @(w);
        out[(id)kCGImagePropertyPixelHeight] = @(h);

        CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:outPath], CFSTR("public.jpeg"), 1, NULL);
        if (!dst) {
            fprintf(stderr, "cannot create destination\n");
            return 1;
        }
        CGImageDestinationAddImage(dst, image, (__bridge CFDictionaryRef)out);
        BOOL ok = CGImageDestinationFinalize(dst);
        CFRelease(dst);
        printf("wrote %s ok=%d\n", outPath.UTF8String, ok);

        CGImageSourceRef back = CGImageSourceCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:outPath], NULL);
        if (back) {
            NSDictionary *p = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(back, 0, NULL));
            dump(p, @"written");
            CFRelease(back);
        }
        CGImageRelease(image);
        return 0;
    }
}
