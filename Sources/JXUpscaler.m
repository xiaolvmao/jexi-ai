//
//  JXUpscaler.m
//  jexi-ai
//

#import "JXUpscaler.h"
#import <CoreML/CoreML.h>
#import <Accelerate/Accelerate.h>

NSString *const JXUpscalerErrorDomain = @"JXUpscalerErrorDomain";

static NSError *JXError(JXUpscalerError code, NSString *message)
{
    return [NSError errorWithDomain:JXUpscalerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message ?: @"error"}];
}

CVPixelBufferRef JXCreateBGRABuffer(size_t width, size_t height)
{
    NSDictionary *attrs = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    };
    CVPixelBufferRef pb = NULL;
    CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                     kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)attrs, &pb);
    return (r == kCVReturnSuccess) ? pb : NULL;
}

CVPixelBufferRef JXRescaleBuffer(CVPixelBufferRef source, size_t width, size_t height)
{
    CVPixelBufferRef dst = JXCreateBGRABuffer(width, height);
    if (!dst) return NULL;
    CVPixelBufferLockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(dst, 0);
    vImage_Buffer in = {
        .data = CVPixelBufferGetBaseAddress(source),
        .height = CVPixelBufferGetHeight(source),
        .width = CVPixelBufferGetWidth(source),
        .rowBytes = CVPixelBufferGetBytesPerRow(source),
    };
    vImage_Buffer out = {
        .data = CVPixelBufferGetBaseAddress(dst),
        .height = height,
        .width = width,
        .rowBytes = CVPixelBufferGetBytesPerRow(dst),
    };
    vImage_Error err = vImageScale_ARGB8888(&in, &out, NULL, kvImageHighQualityResampling);
    CVPixelBufferUnlockBaseAddress(dst, 0);
    CVPixelBufferUnlockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    if (err != kvImageNoError) {
        CVPixelBufferRelease(dst);
        return NULL;
    }
    return dst;
}

#pragma mark - JXSRModel

@interface JXSRModel ()
@property (nonatomic, strong) MLModel *model;
@property (nonatomic, assign) NSInteger inputTileSize;
@property (nonatomic, assign) NSInteger scale;
@property (nonatomic, copy) NSString *inputName;
@property (nonatomic, copy) NSString *outputName;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong) NSURL *compiledURL;
@end

@implementation JXSRModel

+ (instancetype)modelWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
    return [self modelWithContentsOfURL:url cacheDirectory:nil error:error];
}

+ (instancetype)modelWithContentsOfURL:(NSURL *)url
                       cacheDirectory:(NSURL *)cacheDirectory
                                error:(NSError **)error
{
    NSError *err = nil;
    NSURL *compiled = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (cacheDirectory) {
        [fm createDirectoryAtURL:cacheDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *name = url.lastPathComponent.stringByDeletingPathExtension;
        NSURL *cached = [cacheDirectory URLByAppendingPathComponent:
                                             [name stringByAppendingPathExtension:@"mlmodelc"]];
        if ([fm fileExistsAtPath:cached.path]) {
            compiled = cached;
        } else {
            NSURL *fresh = [MLModel compileModelAtURL:url error:&err];
            if (fresh) {
                if (![fm copyItemAtURL:fresh toURL:cached error:NULL]) compiled = fresh;
                else compiled = cached;
            }
        }
    } else {
        compiled = [MLModel compileModelAtURL:url error:&err];
    }
    if (!compiled) {
        if (error) *error = JXError(JXUpscalerErrorBadModel,
                                    [NSString stringWithFormat:@"compile failed: %@",
                                                               err.localizedDescription]);
        return nil;
    }
    MLModelConfiguration *cfg = [MLModelConfiguration new];
    cfg.computeUnits = MLComputeUnitsAll;
    MLModel *ml = [MLModel modelWithContentsOfURL:compiled configuration:cfg error:&err];
    if (!ml) {
        if (error) *error = JXError(JXUpscalerErrorBadModel,
                                    [NSString stringWithFormat:@"load failed: %@",
                                                               err.localizedDescription]);
        return nil;
    }
    MLModelDescription *desc = ml.modelDescription;
    NSString *inName = desc.inputDescriptionsByName.allKeys.firstObject;
    MLFeatureDescription *inDesc = inName ? desc.inputDescriptionsByName[inName] : nil;
    MLImageConstraint *ic = inDesc.imageConstraint;
    if (!ic) {
        if (error) *error = JXError(JXUpscalerErrorBadModel, @"input is not an image");
        return nil;
    }
    NSString *outName = desc.outputDescriptionsByName.allKeys.firstObject;
    MLFeatureDescription *outDesc = outName ? desc.outputDescriptionsByName[outName] : nil;
    MLImageConstraint *oc = outDesc.imageConstraint;
    if (!oc) {
        if (error) *error = JXError(JXUpscalerErrorBadModel, @"output is not an image");
        return nil;
    }
    if ((NSInteger)ic.pixelsWide != (NSInteger)ic.pixelsHigh) {
        if (error) *error = JXError(JXUpscalerErrorBadModel, @"input tile is not square");
        return nil;
    }
    NSInteger scale = (NSInteger)llround((double)oc.pixelsWide / (double)ic.pixelsWide);
    if (scale < 1) {
        if (error) *error = JXError(JXUpscalerErrorBadModel, @"bad scale");
        return nil;
    }
    JXSRModel *m = [JXSRModel new];
    m.model = ml;
    m.inputTileSize = (NSInteger)ic.pixelsWide;
    m.scale = scale;
    m.inputName = inName;
    m.outputName = outName;
    m.compiledURL = compiled;
    m.displayName = url.lastPathComponent.stringByDeletingPathExtension;
    return m;
}

- (CVPixelBufferRef)runTile:(CVPixelBufferRef)tile error:(NSError **)error
{
    NSError *err = nil;
    MLDictionaryFeatureProvider *p =
        [[MLDictionaryFeatureProvider alloc]
            initWithDictionary:@{self.inputName : [MLFeatureValue featureValueWithPixelBuffer:tile]}
                         error:&err];
    id<MLFeatureProvider> res = p ? [self.model predictionFromFeatures:p error:&err] : nil;
    MLFeatureValue *fv = res ? [res featureValueForName:self.outputName] : nil;
    if (!fv.imageBufferValue) {
        if (error)
            *error = JXError(JXUpscalerErrorTileFailed,
                             [NSString stringWithFormat:@"tile failed: %@",
                                                        err.localizedDescription]);
        return NULL;
    }
    return CVPixelBufferRetain(fv.imageBufferValue);
}

- (BOOL)warmUpWithError:(NSError **)error
{
    NSInteger t = self.inputTileSize;
    CVPixelBufferRef pb = JXCreateBGRABuffer(t, t);
    if (!pb) {
        if (error) *error = JXError(JXUpscalerErrorBuffer, @"warm-up buffer");
        return NO;
    }
    CVPixelBufferLockBaseAddress(pb, 0);
    memset(CVPixelBufferGetBaseAddress(pb), 0x80,
           CVPixelBufferGetBytesPerRow(pb) * (size_t)t);
    CVPixelBufferUnlockBaseAddress(pb, 0);
    NSError *err = nil;
    MLDictionaryFeatureProvider *p =
        [[MLDictionaryFeatureProvider alloc]
            initWithDictionary:@{self.inputName : [MLFeatureValue featureValueWithPixelBuffer:pb]}
                         error:&err];
    id<MLFeatureProvider> res = p ? [self.model predictionFromFeatures:p error:&err] : nil;
    CVPixelBufferRelease(pb);
    if (!res) {
        if (error) *error = JXError(JXUpscalerErrorTileFailed,
                                    [NSString stringWithFormat:@"warm-up failed: %@",
                                                               err.localizedDescription]);
        return NO;
    }
    return YES;
}

@end

#pragma mark - tiling helpers

/// Evenly spaced tile origins along one axis so the last tile lands exactly on
/// the edge and no tiny sliver tile is created.
static void JXOrigins(long n, long tile, long step, long *out, int *count)
{
    if (n <= tile) {
        out[0] = 0;
        *count = 1;
        return;
    }
    long span = n - tile;
    int c = (int)((span + step - 1) / step) + 1;
    if (c > 4096) c = 4096;
    for (int i = 0; i < c; i++) {
        double f = (c == 1) ? 0.0 : (double)i / (double)(c - 1);
        out[i] = (long)llround(f * (double)span);
    }
    *count = c;
}

/// Cross-fades one tile's output into the destination.  `band` is the overlap
/// in output pixels; only the left/top edges that sit on top of an earlier tile
/// are feathered.
static void JXBlendTile(CVPixelBufferRef dst, CVPixelBufferRef tile,
                        long dx, long dy, long band,
                        BOOL featherLeft, BOOL featherTop)
{
    const long tw = (long)CVPixelBufferGetWidth(tile);
    const long th = (long)CVPixelBufferGetHeight(tile);
    const long dw = (long)CVPixelBufferGetWidth(dst);
    const long dh = (long)CVPixelBufferGetHeight(dst);
    CVPixelBufferLockBaseAddress(dst, 0);
    CVPixelBufferLockBaseAddress(tile, kCVPixelBufferLock_ReadOnly);
    uint8_t *db = CVPixelBufferGetBaseAddress(dst);
    uint8_t *tb = CVPixelBufferGetBaseAddress(tile);
    size_t ds = CVPixelBufferGetBytesPerRow(dst);
    size_t ts = CVPixelBufferGetBytesPerRow(tile);
    for (long y = 0; y < th; y++) {
        long ty = dy + y;
        if (ty < 0 || ty >= dh) continue;
        float ay = 1.0f;
        if (featherTop && y < band) ay = (y + 0.5f) / (float)band;
        uint8_t *drow = db + (size_t)ty * ds;
        uint8_t *trow = tb + (size_t)y * ts;
        for (long x = 0; x < tw; x++) {
            long tx = dx + x;
            if (tx < 0 || tx >= dw) continue;
            uint8_t *d = drow + (size_t)tx * 4;
            uint8_t *t = trow + (size_t)x * 4;
            float ax = 1.0f;
            if (featherLeft && x < band) ax = (x + 0.5f) / (float)band;
            float a = ax * ay;
            if (a >= 0.999f) {
                d[0] = t[0];
                d[1] = t[1];
                d[2] = t[2];
            } else if (a > 0.001f) {
                float inv = 1.0f - a;
                d[0] = (uint8_t)(d[0] * inv + t[0] * a + 0.5f);
                d[1] = (uint8_t)(d[1] * inv + t[1] * a + 0.5f);
                d[2] = (uint8_t)(d[2] * inv + t[2] * a + 0.5f);
            }
            d[3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(tile, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferUnlockBaseAddress(dst, 0);
}

/// Copies a T x T window out of `src`, replicating edge pixels when the window
/// runs past the picture (small photos, last row/column).
static void JXExtractTile(CVPixelBufferRef src, long sx, long sy, long tile,
                          CVPixelBufferRef out)
{
    const long sw = (long)CVPixelBufferGetWidth(src);
    const long sh = (long)CVPixelBufferGetHeight(src);
    CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(out, 0);
    const uint8_t *sb = CVPixelBufferGetBaseAddress(src);
    size_t ss = CVPixelBufferGetBytesPerRow(src);
    uint8_t *ob = CVPixelBufferGetBaseAddress(out);
    size_t os = CVPixelBufferGetBytesPerRow(out);
    BOOL inside = (sx >= 0 && sy >= 0 && sx + tile <= sw && sy + tile <= sh);
    for (long y = 0; y < tile; y++) {
        long yy = sy + y;
        if (yy < 0) yy = 0;
        if (yy >= sh) yy = sh - 1;
        const uint8_t *srow = sb + (size_t)yy * ss;
        uint8_t *orow = ob + (size_t)y * os;
        if (inside) {
            memcpy(orow, srow + (size_t)sx * 4, (size_t)tile * 4);
            continue;
        }
        for (long x = 0; x < tile; x++) {
            long xx = sx + x;
            if (xx < 0) xx = 0;
            if (xx >= sw) xx = sw - 1;
            memcpy(orow + (size_t)x * 4, srow + (size_t)xx * 4, 4);
        }
    }
    CVPixelBufferUnlockBaseAddress(out, 0);
    CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
}

#pragma mark - JXUpscaler

@interface JXUpscaler ()
@property (nonatomic, strong) JXSRModel *model;
@property (nonatomic, assign) NSInteger totalTiles;
@property (nonatomic, assign) BOOL didPrescale;
@property (nonatomic, assign) CGSize outputSize;
@end

@implementation JXUpscaler

- (instancetype)initWithModel:(JXSRModel *)model
{
    self = [super init];
    if (self) {
        _model = model;
        _overlapPixels = 32;
        _maxOutputEdge = 4096;
    }
    return self;
}

- (CVPixelBufferRef)upscalePixelBuffer:(CVPixelBufferRef)source
                              progress:(JXProgressBlock)progress
                              canceled:(JXCancelBlock)canceled
                                 error:(NSError **)error
{
    const NSInteger tile = self.model.inputTileSize;
    const NSInteger scale = self.model.scale;
    long sw = (long)CVPixelBufferGetWidth(source);
    long sh = (long)CVPixelBufferGetHeight(source);
    if (sw <= 0 || sh <= 0) {
        if (error) *error = JXError(JXUpscalerErrorBuffer, @"empty source");
        return NULL;
    }

    // 1. Keep the promised output size: shrink first when the upscaled picture
    //    would be larger than maxOutputEdge.
    CVPixelBufferRef work = CVPixelBufferRetain(source);
    self.didPrescale = NO;
    if (self.maxOutputEdge > 0) {
        long long outW = (long long)sw * scale, outH = (long long)sh * scale;
        long long longest = MAX(outW, outH);
        if (longest > self.maxOutputEdge) {
            double f = (double)self.maxOutputEdge / (double)longest;
            long nw = (long)llround(sw * f);
            long nh = (long)llround(sh * f);
            if (nw < 1) nw = 1;
            if (nh < 1) nh = 1;
            CVPixelBufferRef scaled = JXRescaleBuffer(source, (size_t)nw, (size_t)nh);
            if (!scaled) {
                if (error) *error = JXError(JXUpscalerErrorBuffer, @"prescale failed");
                CVPixelBufferRelease(work);
                return NULL;
            }
            CVPixelBufferRelease(work);
            work = scaled;
            sw = nw;
            sh = nh;
            self.didPrescale = YES;
        }
    }

    long dw = sw * scale, dh = sh * scale;
    CVPixelBufferRef dst = JXCreateBGRABuffer((size_t)dw, (size_t)dh);
    if (!dst) {
        if (error) *error = JXError(JXUpscalerErrorTooLarge,
                                    [NSString stringWithFormat:@"cannot allocate %ldx%ld output",
                                                               dw, dh]);
        CVPixelBufferRelease(work);
        return NULL;
    }
    CVPixelBufferLockBaseAddress(dst, 0);
    memset(CVPixelBufferGetBaseAddress(dst), 0,
           CVPixelBufferGetBytesPerRow(dst) * (size_t)dh);
    CVPixelBufferUnlockBaseAddress(dst, 0);

    // 2. Tile grid.  The step is chosen so neighbours overlap by overlapPixels
    //    in output space (overlapPixels / scale in source pixels).
    long band = self.overlapPixels > 0 ? self.overlapPixels : 0;
    long overlapSrc = band / scale;
    long step = tile - overlapSrc;
    if (step < 1) step = 1;
    long xs[4096], ys[4096];
    int nx = 0, ny = 0;
    JXOrigins(sw, tile, step, xs, &nx);
    JXOrigins(sh, tile, step, ys, &ny);
    long total = (long)nx * ny;
    self.totalTiles = (NSInteger)total;

    CVPixelBufferRef inTile = JXCreateBGRABuffer((size_t)tile, (size_t)tile);
    if (!inTile) {
        if (error) *error = JXError(JXUpscalerErrorBuffer, @"tile buffer");
        CVPixelBufferRelease(dst);
        CVPixelBufferRelease(work);
        return NULL;
    }

    NSDate *started = [NSDate date];
    long done = 0;
    for (int ty = 0; ty < ny; ty++) {
        for (int tx = 0; tx < nx; tx++) {
            if (canceled && canceled()) {
                if (error) *error = JXError(JXUpscalerErrorCanceled, @"canceled");
                CVPixelBufferRelease(inTile);
                CVPixelBufferRelease(dst);
                CVPixelBufferRelease(work);
                return NULL;
            }
            long ox = xs[tx], oy = ys[ty];
            JXExtractTile(work, ox, oy, tile, inTile);

            @autoreleasepool {
                NSError *err = nil;
                MLDictionaryFeatureProvider *p =
                    [[MLDictionaryFeatureProvider alloc]
                        initWithDictionary:@{self.model.inputName :
                                                 [MLFeatureValue featureValueWithPixelBuffer:inTile]}
                                     error:&err];
                id<MLFeatureProvider> res =
                    p ? [self.model.model predictionFromFeatures:p error:&err] : nil;
                MLFeatureValue *fv = res ? [res featureValueForName:self.model.outputName] : nil;
                CVPixelBufferRef outBuf = fv.imageBufferValue;
                if (!outBuf) {
                    if (error) *error = JXError(JXUpscalerErrorTileFailed,
                                                [NSString stringWithFormat:@"tile %d,%d failed: %@",
                                                                           tx, ty,
                                                                           err.localizedDescription]);
                    CVPixelBufferRelease(inTile);
                    CVPixelBufferRelease(dst);
                    CVPixelBufferRelease(work);
                    return NULL;
                }
                JXBlendTile(dst, outBuf, ox * scale, oy * scale, band,
                            tx > 0, ty > 0);
            }

            done++;
            if (progress) {
                double elapsed = -[started timeIntervalSinceNow];
                progress(done, total, done > 0 ? elapsed / done : 0);
            }
        }
    }

    CVPixelBufferRelease(inTile);
    CVPixelBufferRelease(work);
    self.outputSize = CGSizeMake((CGFloat)dw, (CGFloat)dh);
    return dst;
}

@end
