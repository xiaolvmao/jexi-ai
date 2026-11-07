// icongen <outdir> [prefix]
//
// Draws the app icon with Core Graphics only (no UIKit): a dark gradient tile,
// a photo frame with a mountain and sun, and a "4×" mark.  Writes the loose PNG
// sizes a jailbreak-installed app needs (CFBundleIconFiles), plus a 1024px
// marketing icon.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>

// Small helper so the drawing code reads the same in C.  The colour is created
// once per call and left to the process (this tool draws eleven icons and exits).
static inline CGColorRef UIColorFromRGB(CGFloat r, CGFloat g, CGFloat b)
{
    static CGColorSpaceRef space = NULL;
    if (!space) space = CGColorSpaceCreateDeviceRGB();
    CGFloat c[4] = {r, g, b, 1.0};
    return CGColorCreate(space, c);
}

static void drawIcon(CGContextRef ctx, CGFloat s)
{
    // background: deep navy to blue
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat colours[8] = {0.043, 0.055, 0.086, 1.0, 0.078, 0.212, 0.427, 1.0};
    CGFloat locations[2] = {0.0, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(cs, colours, locations, 2);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, s), CGPointMake(s * 0.35, 0),
                                kCGGradientDrawsBeforeStartLocation |
                                    kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(cs);

    // subtle glow behind the frame
    CGContextSaveGState(ctx);
    CGContextSetFillColorWithColor(ctx, UIColorFromRGB(0.29, 0.67, 1.0));
    CGContextSetAlpha(ctx, 0.16);
    CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.08, s * 0.10, s * 0.84, s * 0.84));
    CGContextRestoreGState(ctx);

    // photo frame
    CGRect frame = CGRectMake(s * 0.17, s * 0.30, s * 0.66, s * 0.50);
    CGPathRef rounded = CGPathCreateWithRoundedRect(frame, s * 0.09, s * 0.09, NULL);
    CGContextAddPath(ctx, rounded);
    CGContextSetFillColorWithColor(ctx, UIColorFromRGB(1, 1, 1));
    CGContextSetAlpha(ctx, 0.10);
    CGContextFillPath(ctx);
    CGContextAddPath(ctx, rounded);
    CGContextSetStrokeColorWithColor(ctx, UIColorFromRGB(1, 1, 1));
    CGContextSetAlpha(ctx, 0.55);
    CGContextSetLineWidth(ctx, MAX(2.0, s * 0.012));
    CGContextStrokePath(ctx);
    CGPathRelease(rounded);

    // sun (upper left inside the frame; Core Graphics origin is bottom-left)
    CGContextSetFillColorWithColor(ctx, UIColorFromRGB(1, 0.86, 0.45));
    CGContextSetAlpha(ctx, 0.95);
    CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.25, s * 0.60, s * 0.115, s * 0.115));

    // mountain, sitting on the frame's bottom edge
    CGMutablePathRef mountain = CGPathCreateMutable();
    CGPathMoveToPoint(mountain, NULL, s * 0.21, s * 0.32);
    CGPathAddLineToPoint(mountain, NULL, s * 0.41, s * 0.60);
    CGPathAddLineToPoint(mountain, NULL, s * 0.55, s * 0.44);
    CGPathAddLineToPoint(mountain, NULL, s * 0.64, s * 0.54);
    CGPathAddLineToPoint(mountain, NULL, s * 0.79, s * 0.32);
    CGPathCloseSubpath(mountain);
    CGContextAddPath(ctx, mountain);
    CGContextSetFillColorWithColor(ctx, UIColorFromRGB(0.85, 0.93, 1));
    CGContextSetAlpha(ctx, 0.92);
    CGContextFillPath(ctx);
    CGPathRelease(mountain);

    // "4×" mark, bottom right
    CTFontRef font = CTFontCreateWithName(CFSTR("HelveticaNeue-Bold"), s * 0.26, NULL);
    NSDictionary *attrs = @{
        (id)kCTFontAttributeName : (__bridge id)font,
        (id)kCTForegroundColorAttributeName : (__bridge id)UIColorFromRGB(0.55, 0.85, 1),
    };
    NSAttributedString *mark = [[NSAttributedString alloc] initWithString:@"4×" attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)mark);
    CGRect bounds = CTLineGetImageBounds(line, ctx);
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextSetTextPosition(ctx, s * 0.90 - bounds.size.width,
                             s * 0.20 - bounds.size.height * 0.5);
    CTLineDraw(line, ctx);
    CFRelease(line);
    CFRelease(font);
}

static BOOL writePNG(CGContextRef ctx, size_t px, NSString *path)
{
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    if (!image) return NO;
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                CFSTR("public.png"), 1, NULL);
    if (!dst) {
        CGImageRelease(image);
        return NO;
    }
    CGImageDestinationAddImage(dst, image, (__bridge CFDictionaryRef) @{});
    BOOL ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    CGImageRelease(image);
    return ok;
}

static BOOL render(size_t px, NSString *path)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, px, px, 8, 0, cs,
                                             kCGImageAlphaPremultipliedLast |
                                                 kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return NO;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextSetAllowsAntialiasing(ctx, true);
    drawIcon(ctx, (CGFloat)px);
    BOOL ok = writePNG(ctx, px, path);
    CGContextRelease(ctx);
    return ok;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: icongen <outdir>\n");
            return 2;
        }
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

        // name -> pixel size (points x scale)
        NSArray *specs = @[
            @[@"AppIcon20x20@2x", @40], @[@"AppIcon20x20@3x", @60],
            @[@"AppIcon29x29@2x", @58], @[@"AppIcon29x29@3x", @87],
            @[@"AppIcon40x40@2x", @80], @[@"AppIcon40x40@3x", @120],
            @[@"AppIcon60x60@2x", @120], @[@"AppIcon60x60@3x", @180],
            @[@"AppIcon76x76@2x", @152], @[@"AppIcon83.5x83.5@2x", @167],
            @[@"AppIcon1024", @1024],
        ];
        for (NSArray *spec in specs) {
            NSString *name = spec[0];
            size_t px = (size_t)[spec[1] integerValue];
            NSString *path = [dir stringByAppendingPathComponent:
                                      [name stringByAppendingPathExtension:@"png"]];
            if (!render(px, path)) {
                fprintf(stderr, "failed: %s\n", name.UTF8String);
                return 1;
            }
            printf("wrote %s (%zux%zu)\n", path.UTF8String, px, px);
        }
        return 0;
    }
}
