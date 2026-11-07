// exifdump <image> [<image> ...] — prints the metadata ImageIO sees, so a saved
// result can be compared with the photo it came from.
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: exifdump <image> ...\n");
            return 2;
        }
        for (int i = 1; i < argc; i++) {
            NSString *path = [NSString stringWithUTF8String:argv[i]];
            printf("== %s\n", path.lastPathComponent.UTF8String);
            CGImageSourceRef src = CGImageSourceCreateWithURL(
                (__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
            if (!src) {
                printf("   cannot open\n");
                continue;
            }
            NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
            CFRelease(src);
            NSNumber *w = props[(id)kCGImagePropertyPixelWidth];
            NSNumber *h = props[(id)kCGImagePropertyPixelHeight];
            NSNumber *o = props[(id)kCGImagePropertyOrientation];
            printf("   size %ldx%ld  orientation %ld\n", (long)w.integerValue,
                   (long)h.integerValue, (long)o.integerValue);
            NSDictionary *exif = props[(id)kCGImagePropertyExifDictionary];
            NSDictionary *tiff = props[(id)kCGImagePropertyTIFFDictionary];
            if (exif) {
                printf("   exif: time=%s model=%s lens=%s f=%s exp=%s iso=%s\n",
                       [exif[(id)kCGImagePropertyExifDateTimeOriginal] description].UTF8String,
                       [tiff[(id)kCGImagePropertyTIFFModel] description].UTF8String,
                       [exif[(id)kCGImagePropertyExifLensModel] description].UTF8String,
                       [exif[(id)kCGImagePropertyExifFNumber] description].UTF8String,
                       [exif[(id)kCGImagePropertyExifExposureTime] description].UTF8String,
                       [exif[(id)kCGImagePropertyExifISOSpeedRatings] description].UTF8String);
            } else {
                printf("   exif: (none)\n");
            }
            NSDictionary *gps = props[(id)kCGImagePropertyGPSDictionary];
            printf("   gps:  %s\n", gps ? gps.description.UTF8String : "(none)");
        }
        return 0;
    }
}
