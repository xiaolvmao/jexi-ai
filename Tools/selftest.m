// selftest [--big] <model.mlmodel> [<model2.mlmodel> ...]
//
// Runs the whole inference core against a model and checks, in order:
//   1. the model loads and its tile size / scale are what the kernel assumes
//   2. one tile: output size, channel order (red left / green middle / blue
//      right survives the round trip), value range and noise
//   3. tiling: a picture that is exactly one tile must come out identical to a
//      single direct prediction, and a multi-tile picture must not show a
//      brightness step where two tiles were cross-faded
//   4. --big: the 4096 cap on a 3000x2000 photo, with time and peak memory
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreML/CoreML.h>
#import <mach/mach.h>
#import "JXUpscaler.h"

static double footprintMB(void)
{
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
        return -1;
    return info.phys_footprint / (1024.0 * 1024.0);
}

static int gFailures = 0;

static void check(BOOL ok, NSString *what, NSString *detail)
{
    printf("  [%s] %s%s%s\n", ok ? "PASS" : "FAIL", what.UTF8String,
           detail.length ? " — " : "", detail.length ? detail.UTF8String : "");
    if (!ok) gFailures++;
}

/// Red left third, green middle, blue right third: after a round trip through
/// the model and BGRA the dominant channel in each third tells us whether the
/// channel order survived.
static CVPixelBufferRef makeColourTest(size_t w, size_t h)
{
    CVPixelBufferRef pb = JXCreateBGRABuffer(w, h);
    if (!pb) return NULL;
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *base = CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    for (size_t y = 0; y < h; y++) {
        uint8_t *row = base + y * stride;
        for (size_t x = 0; x < w; x++) {
            uint8_t *p = row + x * 4;
            p[0] = (x < w / 3) ? 255 : 0;                             // B
            p[1] = (x >= w / 3 && x < 2 * w / 3) ? 255 : 0;           // G
            p[2] = (x >= 2 * w / 3) ? 255 : 0;                        // R
            p[3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

/// A soft gradient with texture, so tile boundaries land on content rather than
/// on a flat colour where a seam could not show anyway.
static CVPixelBufferRef makeGradient(size_t w, size_t h)
{
    CVPixelBufferRef pb = JXCreateBGRABuffer(w, h);
    if (!pb) return NULL;
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *base = CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    for (size_t y = 0; y < h; y++) {
        uint8_t *row = base + y * stride;
        for (size_t x = 0; x < w; x++) {
            uint8_t *p = row + x * 4;
            double v = 0.5 + 0.35 * sin((double)x / 37.0) * cos((double)y / 53.0)
                             + 0.1 * sin((double)(x + y) / 9.0);
            uint8_t c = (uint8_t)MAX(0, MIN(255, (int)(v * 255)));
            p[0] = c;
            p[1] = (uint8_t)MAX(0, MIN(255, (int)((v * 0.9 + 0.05) * 255)));
            p[2] = (uint8_t)MAX(0, MIN(255, (int)((v * 0.8 + 0.1) * 255)));
            p[3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

typedef struct { double r, g, b; } JXRGBTriple;

static JXRGBTriple regionMean(CVPixelBufferRef pb, size_t x0, size_t x1)
{
    size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
    if (x1 > w) x1 = w;
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    uint8_t *base = CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    double sb = 0, sg = 0, sr = 0;
    size_t n = 0;
    for (size_t y = 0; y < h; y += 4) {
        uint8_t *row = base + y * stride;
        for (size_t x = x0; x < x1; x += 4) {
            uint8_t *p = row + x * 4;
            sb += p[0]; sg += p[1]; sr += p[2];
            n++;
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    JXRGBTriple t = {sr / (double)MAX(n, 1), sg / (double)MAX(n, 1), sb / (double)MAX(n, 1)};
    return t;  // r, g, b order for readability
}

/// Mean absolute horizontal difference across one column, and across the whole
/// picture, so a cross-fade seam can be compared with ordinary image gradient.
static void columnStats(CVPixelBufferRef pb, size_t col, double *atCol, double *overall)
{
    size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    uint8_t *base = CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    double colSum = 0;
    long colN = 0;
    double allSum = 0;
    long allN = 0;
    for (size_t y = 0; y < h; y += 2) {
        uint8_t *row = base + y * stride;
        for (size_t x = 1; x < w; x += 2) {
            uint8_t *a = row + (x - 1) * 4;
            uint8_t *b = row + x * 4;
            double d = fabs((double)a[0] - b[0]) + fabs((double)a[1] - b[1]) +
                       fabs((double)a[2] - b[2]);
            allSum += d;
            allN++;
            if (x >= col && x < col + 2) {
                colSum += d;
                colN++;
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    *atCol = colN ? colSum / colN : 0;
    *overall = allN ? allSum / allN : 0;
}

static BOOL runModelOnce(JXSRModel *model, CVPixelBufferRef tile, CVPixelBufferRef *out)
{
    NSError *err = nil;
    *out = [model runTile:tile error:&err];
    if (!*out) {
        printf("  direct prediction failed: %s\n", err.localizedDescription.UTF8String);
        return NO;
    }
    return YES;
}

static void testModel(NSURL *url, BOOL big)
{
    printf("\n=== %s ===\n", url.lastPathComponent.UTF8String);
    NSError *err = nil;
    double m0 = footprintMB();
    NSDate *t0 = [NSDate date];
    JXSRModel *model = [JXSRModel modelWithContentsOfURL:url error:&err];
    if (!model) {
        check(NO, @"load", err.localizedDescription);
        return;
    }
    printf("  tile %ldx%ld, scale %ldx, load %.1f s, footprint %.0f MB\n",
           (long)model.inputTileSize, (long)model.inputTileSize, (long)model.scale,
           -[t0 timeIntervalSinceNow], footprintMB() - m0);
    check(model.inputTileSize >= 64, @"tile size sane",
          [NSString stringWithFormat:@"%ld", (long)model.inputTileSize]);
    check(model.scale == 2 || model.scale == 4, @"scale is 2 or 4",
          [NSString stringWithFormat:@"%ld", (long)model.scale]);

    NSInteger tile = model.inputTileSize;

    // ---- 2. one tile, colour order and range
    CVPixelBufferRef colour = makeColourTest((size_t)tile, (size_t)tile);
    CVPixelBufferRef direct = NULL;
    if (!colour || !runModelOnce(model, colour, &direct)) {
        check(NO, @"direct tile run", @"failed");
        if (colour) CVPixelBufferRelease(colour);
        return;
    }
    size_t ow = CVPixelBufferGetWidth(direct), oh = CVPixelBufferGetHeight(direct);
    check(ow == (size_t)(tile * model.scale) && oh == (size_t)(tile * model.scale),
          @"direct output size",
          [NSString stringWithFormat:@"%zux%zu (expected %ld)", ow, oh,
                                     (long)(tile * model.scale)]);

    JXRGBTriple left = regionMean(direct, ow / 8, ow / 4);
    JXRGBTriple mid = regionMean(direct, ow * 3 / 8, ow * 5 / 8);
    JXRGBTriple right = regionMean(direct, ow * 3 / 4, ow * 7 / 8);
    printf("  thirds R/G/B: left %.0f/%.0f/%.0f  mid %.0f/%.0f/%.0f  right %.0f/%.0f/%.0f\n",
           left.r, left.g, left.b, mid.r, mid.g, mid.b, right.r, right.g, right.b);
    // BGRA in memory: byte 0 is B, so the left third of the source is blue and
    // the right third red.  A model that swapped channels flips these.
    check(left.b > left.r + 20 && left.b > left.g + 20, @"blue third stays blue", @"");
    check(mid.g > mid.r + 20 && mid.g > mid.b + 20, @"green third stays green", @"");
    check(right.r > right.b + 20 && right.r > right.g + 20, @"red third stays red", @"");

    // A model that emits garbage (all black, all white, NaN-ish) fails here.
    CVPixelBufferLockBaseAddress(direct, kCVPixelBufferLock_ReadOnly);
    uint8_t *db = CVPixelBufferGetBaseAddress(direct);
    size_t ds = CVPixelBufferGetBytesPerRow(direct);
    long mn = 255, mx = 0;
    double sum = 0;
    long n = 0;
    for (size_t y = 0; y < oh; y += 3) {
        for (size_t x = 0; x < ow; x += 3) {
            uint8_t *p = db + y * ds + x * 4;
            for (int c = 0; c < 3; c++) {
                if (p[c] < mn) mn = p[c];
                if (p[c] > mx) mx = p[c];
                sum += p[c];
            }
            n++;
        }
    }
    CVPixelBufferUnlockBaseAddress(direct, kCVPixelBufferLock_ReadOnly);
    check(mx - mn > 100, @"output has real contrast",
          [NSString stringWithFormat:@"channel min %ld max %ld", mn, mx]);

    // ---- 3a. one tile through the tiler must equal the direct run
    JXUpscaler *up = [[JXUpscaler alloc] initWithModel:model];
    CVPixelBufferRef tiled = [up upscalePixelBuffer:colour progress:nil canceled:nil error:&err];
    if (!tiled) {
        check(NO, @"tiled run", err.localizedDescription);
        CVPixelBufferRelease(colour);
        CVPixelBufferRelease(direct);
        return;
    }
    check(up.totalTiles == 1, @"one-tile image uses one tile",
          [NSString stringWithFormat:@"%ld", (long)up.totalTiles]);
    {
        long diff = 0, maxd = 0;
        CVPixelBufferLockBaseAddress(direct, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferLockBaseAddress(tiled, kCVPixelBufferLock_ReadOnly);
        uint8_t *a = CVPixelBufferGetBaseAddress(direct);
        uint8_t *b = CVPixelBufferGetBaseAddress(tiled);
        size_t as = CVPixelBufferGetBytesPerRow(direct);
        size_t bs = CVPixelBufferGetBytesPerRow(tiled);
        for (size_t y = 0; y < oh; y++) {
            for (size_t x = 0; x < ow; x++) {
                for (int c = 0; c < 3; c++) {
                    int d = abs((int)a[y * as + x * 4 + c] - (int)b[y * bs + x * 4 + c]);
                    diff += d;
                    if (d > maxd) maxd = d;
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(tiled, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferUnlockBaseAddress(direct, kCVPixelBufferLock_ReadOnly);
        check(maxd == 0, @"tiled single-tile == direct prediction",
              [NSString stringWithFormat:@"max diff %ld", maxd]);
    }
    CVPixelBufferRelease(tiled);
    CVPixelBufferRelease(colour);
    CVPixelBufferRelease(direct);

    // ---- 3b. seams in a 2x2 tile picture
    size_t sw = (size_t)tile * 2, sh = (size_t)tile * 2 - (size_t)tile / 2;
    CVPixelBufferRef grad = makeGradient(sw, sh);
    NSDate *s = [NSDate date];
    CVPixelBufferRef wide = [up upscalePixelBuffer:grad progress:nil canceled:nil error:&err];
    double dt = -[s timeIntervalSinceNow];
    if (!wide) {
        check(NO, @"multi-tile run", err.localizedDescription);
        CVPixelBufferRelease(grad);
        return;
    }
    printf("  %zux%zu -> %zux%zu in %.2f s, %ld tiles\n", sw, sh,
           CVPixelBufferGetWidth(wide), CVPixelBufferGetHeight(wide), dt,
           (long)up.totalTiles);
    check(CVPixelBufferGetWidth(wide) == sw * model.scale, @"multi-tile output width", @"");
    {
        // The cross-faded column is where the second tile starts.
        long stepPx = tile - (up.overlapPixels / model.scale);
        size_t seam = (size_t)stepPx * (size_t)model.scale;
        double atSeam = 0, overall = 0;
        columnStats(wide, seam, &atSeam, &overall);
        check(atSeam <= overall * 3.0 + 2.0, @"no brightness step at the seam",
              [NSString stringWithFormat:@"seam %.1f vs picture %.1f", atSeam, overall]);
    }
    CVPixelBufferRelease(wide);
    CVPixelBufferRelease(grad);

    // ---- 4. the 4096 cap on a big photo
    if (big) {
        size_t bw = 3000, bh = 2000;
        CVPixelBufferRef photo = makeGradient(bw, bh);
        double before = footprintMB();
        s = [NSDate date];
        CVPixelBufferRef out = [up upscalePixelBuffer:photo progress:^(NSInteger done,
                                                                       NSInteger total,
                                                                       double perTile) {
            if (done == total)
                printf("  big: %ld/%ld tiles, %.2f s/tile\n", (long)done, (long)total, perTile);
        } canceled:nil error:&err];
        double elapsed = -[s timeIntervalSinceNow];
        double peak = footprintMB();
        if (!out) {
            check(NO, @"big photo", err.localizedDescription);
        } else {
            check(up.didPrescale, @"big photo was prescaled to the cap", @"");
            long long longest = MAX(CVPixelBufferGetWidth(out), CVPixelBufferGetHeight(out));
            check(longest <= 4096, @"output long edge <= 4096",
                  [NSString stringWithFormat:@"%lld", longest]);
            printf("  big: %zux%zu -> %llux%llu in %.1f s, peak +%.0f MB\n", bw, bh,
                   (unsigned long long)CVPixelBufferGetWidth(out),
                   (unsigned long long)CVPixelBufferGetHeight(out), elapsed, peak - before);
            check(peak - before < 700, @"peak memory under 700 MB",
                  [NSString stringWithFormat:@"%.0f MB", peak - before]);
            CVPixelBufferRelease(out);
        }
        CVPixelBufferRelease(photo);
    }
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        BOOL big = NO;
        NSMutableArray *paths = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            NSString *a = [NSString stringWithUTF8String:argv[i]];
            if ([a isEqualToString:@"--big"])
                big = YES;
            else
                [paths addObject:a];
        }
        if (paths.count == 0) {
            fprintf(stderr, "usage: selftest [--big] <model.mlmodel> ...\n");
            return 2;
        }
        for (NSString *p in paths) {
            NSURL *u = [NSURL fileURLWithPath:p];
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) {
                printf("\n=== %s === missing\n", p.lastPathComponent.UTF8String);
                gFailures++;
                continue;
            }
            testModel(u, big);
        }
        printf("\n%s (%d failure%s)\n", gFailures == 0 ? "ALL PASS" : "FAILURES",
               gFailures, gFailures == 1 ? "" : "s");
        return gFailures == 0 ? 0 : 1;
    }
}
