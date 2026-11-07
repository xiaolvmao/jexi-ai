// modelprobe <model.mlmodel> [--sizes 2048,512,256] [--runs 3] [--units all|cpu] [--pattern gray|red]
//
// Loads a Core ML model through MLModel.compileModelAtURL, prints every input
// and output description (types, image constraints, multiarray shapes), then
// runs one inference per requested size to measure time and peak memory and to
// look at the output's shape and value range.
#import <Foundation/Foundation.h>
#import <CoreML/CoreML.h>
#import <CoreVideo/CoreVideo.h>
#import <mach/mach.h>

static double physFootprintMB(void)
{
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
        return -1;
    return info.phys_footprint / (1024.0 * 1024.0);
}

static const char *typeName(MLFeatureType t)
{
    switch (t) {
        case MLFeatureTypeInvalid: return "invalid";
        case MLFeatureTypeInt64: return "Int64";
        case MLFeatureTypeDouble: return "Double";
        case MLFeatureTypeString: return "String";
        case MLFeatureTypeImage: return "Image";
        case MLFeatureTypeMultiArray: return "MultiArray";
        case MLFeatureTypeDictionary: return "Dictionary";
        case MLFeatureTypeSequence: return "Sequence";
        default: return "?";
    }
}

static const char *dataTypeName(MLMultiArrayDataType t)
{
    switch (t) {
        case MLMultiArrayDataTypeDouble: return "float64";
        case MLMultiArrayDataTypeFloat32: return "float32";
        case MLMultiArrayDataTypeInt32: return "int32";
        default: return "?";
    }
}

static const char *sizeConstraintName(MLImageSizeConstraintType t)
{
    switch (t) {
        case MLImageSizeConstraintTypeUnspecified: return "Unspecified (any size)";
        case MLImageSizeConstraintTypeEnumerated: return "Enumerated (fixed set)";
        case MLImageSizeConstraintTypeRange: return "Range (min..max, multiple of step)";
        default: return "?";
    }
}

static void dumpFeature(MLFeatureDescription *d, BOOL isInput)
{
    printf("    - %s  type=%s  optional=%s\n", d.name.UTF8String, typeName(d.type),
           d.optional ? "yes" : "no");
    if (d.imageConstraint) {
        MLImageConstraint *c = d.imageConstraint;
        printf("        image: %ldx%ld  pixelFormat=0x%08x  sizeConstraint=%s\n",
               (long)c.pixelsWide, (long)c.pixelsHigh, c.pixelFormatType,
               sizeConstraintName(c.sizeConstraint.type));
        if (c.sizeConstraint.type == MLImageSizeConstraintTypeEnumerated) {
            NSMutableString *s = [NSMutableString string];
            for (MLImageSize *z in c.sizeConstraint.enumeratedImageSizes)
                [s appendFormat:@"%ldx%ld ", (long)z.pixelsWide, (long)z.pixelsHigh];
            printf("        enumerated sizes: %s\n", s.UTF8String);
        } else if (c.sizeConstraint.type == MLImageSizeConstraintTypeRange) {
            printf("        range: width %ld..%ld, height %ld..%ld\n",
                   (long)c.sizeConstraint.pixelsWideRange.location,
                   (long)(c.sizeConstraint.pixelsWideRange.location + c.sizeConstraint.pixelsWideRange.length - 1),
                   (long)c.sizeConstraint.pixelsHighRange.location,
                   (long)(c.sizeConstraint.pixelsHighRange.location + c.sizeConstraint.pixelsHighRange.length - 1));
        }
    }
    if (d.multiArrayConstraint) {
        MLMultiArrayConstraint *c = d.multiArrayConstraint;
        NSMutableString *s = [NSMutableString string];
        for (NSNumber *n in c.shape) [s appendFormat:@"%@ ", n];
        printf("        multiArray: shape=[%s] dataType=%s\n", s.UTF8String,
               dataTypeName(c.dataType));
    }
    (void)isInput;
}

// BGRA buffer with a recognisable test pattern: a red/green/blue split and a
// horizontal gradient, so an output that swapped channels or rolled the image
// is obvious in the statistics.
static CVPixelBufferRef makePattern(long w, long h, int mode)
{
    NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVPixelBufferRef pb = NULL;
    CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)attrs, &pb);
    if (r != kCVReturnSuccess || !pb) return NULL;
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *base = CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    for (long y = 0; y < h; y++) {
        uint8_t *row = base + y * stride;
        for (long x = 0; x < w; x++) {
            uint8_t *p = row + x * 4;
            if (mode == 0) {                     // gray with a gradient
                uint8_t v = (uint8_t)((x * 255) / (w > 1 ? w - 1 : 1));
                p[0] = p[1] = p[2] = v;
            } else {                             // red left / green middle / blue right
                p[0] = (x < w / 3) ? 255 : 0;    // B
                p[1] = (x >= w / 3 && x < 2 * w / 3) ? 255 : 0; // G
                p[2] = (x >= 2 * w / 3) ? 255 : 0;  // R
            }
            p[3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

static void dumpBufferStats(CVPixelBufferRef pb, const char *label)
{
    long w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    uint8_t *base = CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    long minb = 255, maxb = 0, ming = 255, maxg = 0, minr = 255, maxr = 0;
    double sb = 0, sg = 0, sr = 0;
    for (long y = 0; y < h; y++) {
        uint8_t *row = base + y * stride;
        for (long x = 0; x < w; x++) {
            uint8_t *p = row + x * 4;
            if (p[0] < minb) minb = p[0];
            if (p[0] > maxb) maxb = p[0];
            if (p[1] < ming) ming = p[1];
            if (p[1] > maxg) maxg = p[1];
            if (p[2] < minr) minr = p[2];
            if (p[2] > maxr) maxr = p[2];
            sb += p[0]; sg += p[1]; sr += p[2];
        }
    }
    double n = (double)w * h;
    printf("        %s %ldx%ld  B[min %ld max %ld mean %.1f] G[min %ld max %ld mean %.1f] "
           "R[min %ld max %ld mean %.1f]\n",
           label, w, h, minb, maxb, sb / n, ming, maxg, sg / n, minr, maxr, sr / n);
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: modelprobe <model.mlmodel|.mlpackage> [--sizes a,b,c] "
                            "[--runs n] [--units all|cpu] [--pattern gray|red]\n");
            return 2;
        }
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        NSMutableArray<NSNumber *> *sizes = [@[ @2048, @512 ] mutableCopy];
        int runs = 3;
        BOOL cpuOnly = NO;
        int pattern = 1;
        for (int i = 2; i + 1 < argc; i += 2) {
            NSString *k = [NSString stringWithUTF8String:argv[i]];
            NSString *v = [NSString stringWithUTF8String:argv[i + 1]];
            if ([k isEqualToString:@"--sizes"]) {
                [sizes removeAllObjects];
                for (NSString *s in [v componentsSeparatedByString:@","])
                    [sizes addObject:@([s integerValue])];
            } else if ([k isEqualToString:@"--runs"]) {
                runs = (int)v.integerValue;
            } else if ([k isEqualToString:@"--units"]) {
                cpuOnly = [v isEqualToString:@"cpu"];
            } else if ([k isEqualToString:@"--pattern"]) {
                pattern = [v isEqualToString:@"gray"] ? 0 : 1;
            }
        }

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            fprintf(stderr, "no such model: %s\n", path.UTF8String);
            return 1;
        }
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        printf("model: %s (%llu bytes)\n", path.lastPathComponent.UTF8String,
               [attrs fileSize]);

        double mem0 = physFootprintMB();
        printf("phys_footprint before compile: %.0f MB\n", mem0);

        NSError *err = nil;
        NSDate *t0 = [NSDate date];
        NSURL *compiled = [MLModel compileModelAtURL:[NSURL fileURLWithPath:path] error:&err];
        printf("compileModelAtURL: %.1f s -> %s\n", -[t0 timeIntervalSinceNow],
               compiled ? compiled.path.UTF8String : "FAILED");
        if (!compiled) {
            fprintf(stderr, "compile failed: %s\n", err.description.UTF8String);
            return 1;
        }

        MLModelConfiguration *cfg = [MLModelConfiguration new];
        cfg.computeUnits = cpuOnly ? MLComputeUnitsCPUOnly : MLComputeUnitsAll;
        t0 = [NSDate date];
        MLModel *model = [MLModel modelWithContentsOfURL:compiled configuration:cfg error:&err];
        printf("load: %.1f s -> %s\n", -[t0 timeIntervalSinceNow], model ? "ok" : "FAILED");
        if (!model) {
            fprintf(stderr, "load failed: %s\n", err.description.UTF8String);
            return 1;
        }
        printf("phys_footprint after load: %.0f MB\n", physFootprintMB());

        MLModelDescription *desc = model.modelDescription;
        printf("inputs (%lu):\n", (unsigned long)desc.inputDescriptionsByName.count);
        for (NSString *n in desc.inputDescriptionsByName)
            dumpFeature(desc.inputDescriptionsByName[n], YES);
        printf("outputs (%lu):\n", (unsigned long)desc.outputDescriptionsByName.count);
        for (NSString *n in desc.outputDescriptionsByName)
            dumpFeature(desc.outputDescriptionsByName[n], NO);
        printf("metadata: %s\n", desc.metadata.description.UTF8String ?: "-");

        NSString *inName = desc.inputDescriptionsByName.allKeys.firstObject;
        MLFeatureDescription *inDesc = desc.inputDescriptionsByName[inName];
        MLImageConstraint *ic = inDesc.imageConstraint;
        if (!ic) {
            printf("input is not an image; no pixel probe\n");
            return 0;
        }

        for (NSNumber *sz in sizes) {
            long side = sz.longValue;
            printf("\n--- probe %ldx%ld (model expects %ldx%ld) ---\n", side, side,
                   (long)ic.pixelsWide, (long)ic.pixelsHigh);
            CVPixelBufferRef pb = makePattern(side, side, pattern);
            if (!pb) {
                printf("  could not create %ldx%ld buffer\n", side, side);
                continue;
            }
            double memBefore = physFootprintMB();
            double best = 0, worst = 0;
            CVPixelBufferRef outBuf = NULL;
            NSDictionary<NSString *, MLFeatureValue *> *out = nil;
            for (int r = 0; r < runs; r++) {
                @autoreleasepool {
                    NSError *perr = nil;
                    NSDate *s = [NSDate date];
                    MLDictionaryFeatureProvider *prov =
                        [[MLDictionaryFeatureProvider alloc]
                            initWithDictionary:@{inName : [MLFeatureValue featureValueWithPixelBuffer:pb]}
                                         error:&perr];
                    id<MLFeatureProvider> res = [model predictionFromFeatures:prov error:&perr];
                    double dt = -[s timeIntervalSinceNow];
                    if (!res) {
                        printf("  run %d FAILED: %s\n", r, perr.description.UTF8String);
                        break;
                    }
                    if (r == 0 || dt < best) best = dt;
                    if (dt > worst) worst = dt;
                    if (r == runs - 1) {
                        NSMutableDictionary *m = [NSMutableDictionary dictionary];
                        for (NSString *n in desc.outputDescriptionsByName)
                            m[n] = [res featureValueForName:n];
                        out = m;
                    }
                }
            }
            double peak = physFootprintMB();
            printf("  time: best %.3f s, worst %.3f s over %d run(s)\n", best, worst, runs);
            printf("  phys_footprint: %.0f MB before, %.0f MB peak (delta %.0f MB)\n",
                   memBefore, peak, peak - memBefore);
            if (out) {
                for (NSString *n in out) {
                    MLFeatureValue *v = out[n];
                    printf("  output '%s' type=%s\n", n.UTF8String, typeName(v.type));
                    if (v.type == MLFeatureTypeImage && v.imageBufferValue) {
                        outBuf = CVPixelBufferRetain(v.imageBufferValue);
                        dumpBufferStats(outBuf, "output image");
                        CVPixelBufferRelease(outBuf);
                    } else if (v.type == MLFeatureTypeMultiArray && v.multiArrayValue) {
                        MLMultiArray *a = v.multiArrayValue;
                        NSMutableString *s = [NSMutableString string];
                        for (NSNumber *nn in a.shape) [s appendFormat:@"%@ ", nn];
                        printf("  multiArray shape=[%s] dataType=%s count=%ld\n", s.UTF8String,
                               dataTypeName(a.dataType), (long)a.count);
                        double mn = 1e9, mx = -1e9, sum = 0;
                        long limit = a.count < 200000 ? a.count : 200000;
                        for (long i = 0; i < limit; i++) {
                            double x = a[i].doubleValue;
                            if (x < mn) mn = x;
                            if (x > mx) mx = x;
                            sum += x;
                        }
                        printf("  values: min %.4f max %.4f mean %.4f\n", mn, mx,
                               sum / (double)limit);
                    }
                }
            }
            CVPixelBufferRelease(pb);
        }
        printf("\nphys_footprint at exit: %.0f MB\n", physFootprintMB());
        return 0;
    }
}
