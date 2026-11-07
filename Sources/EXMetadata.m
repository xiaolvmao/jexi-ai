#import "EXMetadata.h"
#import "EXDevice.h"
#import <ImageIO/ImageIO.h>

static double EXRandomDouble(double minimum, double maximum) {
    if (maximum <= minimum) {
        return minimum;
    }
    return minimum + ((double)arc4random() / (double)UINT32_MAX) * (maximum - minimum);
}

static NSInteger EXRandomInteger(NSInteger minimum, NSInteger maximum) {
    if (maximum <= minimum) {
        return minimum;
    }
    return minimum + (NSInteger)arc4random_uniform((uint32_t)(maximum - minimum + 1));
}

static NSString *EXDateFormat(NSDate *date, NSTimeZone *timeZone) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = timeZone;
    formatter.dateFormat = @"yyyy:MM:dd HH:mm:ss";
    return [formatter stringFromDate:date];
}

static NSString *EXStringFromValue(id value) {
    if (value == nil) {
        return @"";
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            [parts addObject:EXStringFromValue(item)];
        }
        return [parts componentsJoinedByString:@", "];
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"<data %lu bytes>", (unsigned long)[(NSData *)value length]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        double number = [(NSNumber *)value doubleValue];
        if (number == (double)(long long)number) {
            return [NSString stringWithFormat:@"%lld", (long long)number];
        }
        return [NSString stringWithFormat:@"%.4f", number];
    }
    return [value description];
}

static BOOL EXReplaceFile(NSURL *target, NSURL *replacement) {
    NSError *replaceError = nil;
    BOOL ok = [[NSFileManager defaultManager] replaceItemAtURL:target
                                                withItemAtURL:replacement
                                               backupItemName:nil
                                                      options:0
                                             resultingItemURL:NULL
                                                        error:&replaceError];
    if (!ok) {
        [[NSFileManager defaultManager] removeItemAtURL:replacement error:NULL];
    }
    return ok;
}

@implementation EXMetadata

+ (NSDictionary *)propertiesAtURL:(NSURL *)url {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return nil;
    }
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    CFRelease(source);
    if (properties == NULL) {
        return nil;
    }
    return (__bridge_transfer NSDictionary *)properties;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)rowsFromProperties:(NSDictionary *)properties {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *rows = [NSMutableArray array];
    if (properties == nil) {
        return rows;
    }
    NSMutableDictionary *image = [NSMutableDictionary dictionary];
    for (NSString *key in @[(NSString *)kCGImagePropertyPixelWidth,
                            (NSString *)kCGImagePropertyPixelHeight,
                            (NSString *)kCGImagePropertyOrientation,
                            (NSString *)kCGImagePropertyColorModel,
                            (NSString *)kCGImagePropertyDepth,
                            (NSString *)kCGImagePropertyProfileName]) {
        if (properties[key] != nil) {
            image[key] = properties[key];
        }
    }
    NSDictionary *groups = @{
        @"Image": image,
        @"TIFF": properties[(NSString *)kCGImagePropertyTIFFDictionary] ?: @{},
        @"EXIF": properties[(NSString *)kCGImagePropertyExifDictionary] ?: @{},
        @"GPS": properties[(NSString *)kCGImagePropertyGPSDictionary] ?: @{},
    };
    for (NSString *section in @[@"Image", @"TIFF", @"EXIF", @"GPS"]) {
        NSDictionary *dict = groups[section];
        if (![dict isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSArray<NSString *> *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *key in keys) {
            id value = dict[key];
            if ([value isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            [rows addObject:@{@"section": section, @"key": key, @"value": EXStringFromValue(value)}];
        }
    }
    return rows;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)summaryRowsFromProperties:(NSDictionary *)properties {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *rows = [NSMutableArray array];
    if (properties == nil) {
        return rows;
    }
    NSDictionary *tiff = properties[(NSString *)kCGImagePropertyTIFFDictionary];
    NSDictionary *exif = properties[(NSString *)kCGImagePropertyExifDictionary];
    NSDictionary *gps = properties[(NSString *)kCGImagePropertyGPSDictionary];

    void (^add)(NSString *, NSString *) = ^(NSString *key, NSString *value) {
        if (value.length > 0) {
            [rows addObject:@{@"key": key, @"value": value}];
        }
    };

    NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
    NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];
    if (width != nil && height != nil) {
        add(@"尺寸", [NSString stringWithFormat:@"%@ × %@", width, height]);
    }

    NSString *date = exif[(NSString *)kCGImagePropertyExifDateTimeOriginal];
    if (date.length == 0) {
        date = tiff[(NSString *)kCGImagePropertyTIFFDateTime];
    }
    add(@"拍摄时间", date);
    if ([date length] > 0) {
        NSString *offset = exif[(NSString *)kCGImagePropertyExifOffsetTimeOriginal];
        if (offset.length > 0) {
            add(@"时区偏移", offset);
        }
    }

    NSString *make = tiff[(NSString *)kCGImagePropertyTIFFMake];
    NSString *model = tiff[(NSString *)kCGImagePropertyTIFFModel];
    if (make.length > 0 || model.length > 0) {
        add(@"设备", [[@[make ?: @"", model ?: @""] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "]);
    }

    NSString *software = tiff[(NSString *)kCGImagePropertyTIFFSoftware];
    add(@"系统", software);

    NSString *lens = exif[(NSString *)kCGImagePropertyExifLensModel];
    add(@"镜头", lens);

    NSNumber *focal = exif[(NSString *)kCGImagePropertyExifFocalLength];
    NSNumber *focal35 = exif[(NSString *)kCGImagePropertyExifFocalLenIn35mmFilm];
    NSNumber *fnumber = exif[(NSString *)kCGImagePropertyExifFNumber];
    if (focal != nil || fnumber != nil) {
        NSMutableArray *parts = [NSMutableArray array];
        if (focal != nil) {
            [parts addObject:[NSString stringWithFormat:@"%@ mm", focal]];
        }
        if (focal35 != nil) {
            [parts addObject:[NSString stringWithFormat:@"等效 %@ mm", focal35]];
        }
        if (fnumber != nil) {
            [parts addObject:[NSString stringWithFormat:@"f/%@", fnumber]];
        }
        add(@"焦距光圈", [parts componentsJoinedByString:@" · "]);
    }

    id isoValue = exif[(NSString *)kCGImagePropertyExifISOSpeedRatings];
    if ([isoValue isKindOfClass:[NSArray class]] && [isoValue count] > 0) {
        isoValue = [isoValue firstObject];
    }
    NSNumber *exposureTime = exif[(NSString *)kCGImagePropertyExifExposureTime];
    if (isoValue != nil || exposureTime != nil) {
        NSMutableArray *parts = [NSMutableArray array];
        if (isoValue != nil) {
            [parts addObject:[NSString stringWithFormat:@"ISO %@", isoValue]];
        }
        double seconds = exposureTime.doubleValue;
        if (seconds > 0) {
            if (seconds < 1.0) {
                [parts addObject:[NSString stringWithFormat:@"1/%.0f s", round(1.0 / seconds)]];
            } else {
                [parts addObject:[NSString stringWithFormat:@"%.1f s", seconds]];
            }
        }
        add(@"曝光", [parts componentsJoinedByString:@" · "]);
    }

    if ([gps isKindOfClass:[NSDictionary class]] && gps.count > 0) {
        NSNumber *latitude = gps[(NSString *)kCGImagePropertyGPSLatitude];
        NSNumber *longitude = gps[(NSString *)kCGImagePropertyGPSLongitude];
        NSString *latRef = gps[(NSString *)kCGImagePropertyGPSLatitudeRef];
        NSString *lonRef = gps[(NSString *)kCGImagePropertyGPSLongitudeRef];
        if (latitude != nil && longitude != nil) {
            double lat = latitude.doubleValue * ([latRef isEqualToString:@"S"] ? -1 : 1);
            double lon = longitude.doubleValue * ([lonRef isEqualToString:@"W"] ? -1 : 1);
            add(@"位置", [NSString stringWithFormat:@"%.6f, %.6f", lat, lon]);
        } else {
            add(@"位置", @"有 GPS 信息");
        }
    } else {
        add(@"位置", @"无");
    }

    NSString *orientation = EXStringFromValue(properties[(NSString *)kCGImagePropertyOrientation]);
    add(@"方向", orientation);
    return rows;
}

+ (BOOL)writeSourceURL:(NSURL *)src
          toDestination:(NSURL *)dst
                options:(EXWriteOptions)options
               location:(CLLocation *)location
                   date:(NSDate *)date
                 format:(EXOutputFormat)format
                  error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)src, NULL);
    if (source == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"EXMetadata" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"读不出这张照片，格式可能不受支持"}];
        }
        return NO;
    }
    CFStringRef type = CGImageSourceGetType(source);
    CFDictionaryRef copied = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    NSMutableDictionary *properties = copied ? [(__bridge_transfer NSDictionary *)copied mutableCopy]
                                             : [NSMutableDictionary dictionary];
    if (type == NULL || properties == nil) {
        CFRelease(source);
        if (error) {
            *error = [NSError errorWithDomain:@"EXMetadata" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"读不出这张照片的属性"}];
        }
        return NO;
    }

    NSMutableDictionary *tiff = [properties[(NSString *)kCGImagePropertyTIFFDictionary] mutableCopy]
                                ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *exif = [properties[(NSString *)kCGImagePropertyExifDictionary] mutableCopy]
                                ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *gps = [properties[(NSString *)kCGImagePropertyGPSDictionary] mutableCopy]
                               ?: [NSMutableDictionary dictionary];
    BOOL stripGPS = NO;

    CFStringRef outputType = type;
    if (format == EXOutputFormatJPEG) {
        outputType = CFSTR("public.jpeg");
    } else if (format == EXOutputFormatHEIF) {
        outputType = CFSTR("public.heic");
    }
    BOOL converting = (type != NULL && !CFEqual(type, outputType));
    if (converting) {
        properties[(NSString *)kCGImageDestinationLossyCompressionQuality] = @0.95;
    }

    NSDate *now = date ?: [NSDate date];

    if (options & EXWriteDevice) {
        NSString *make = @"Apple";
        NSString *model = [EXDevice marketingName];

        // 镜头与曝光参数在合理区间内随机，每张照片不同
        double focal = round(EXRandomDouble(2.0, 9.0) * 1000.0) / 1000.0;
        double fnumber = round(EXRandomDouble(1.5, 2.8) * 100.0) / 100.0;
        NSInteger isoChoices[] = {25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640};
        NSInteger shutterChoices[] = {30, 60, 120, 250, 500, 1000};
        NSInteger iso = isoChoices[EXRandomInteger(0, (NSInteger)(sizeof(isoChoices) / sizeof(isoChoices[0])) - 1)];
        NSInteger shutter = shutterChoices[EXRandomInteger(0, (NSInteger)(sizeof(shutterChoices) / sizeof(shutterChoices[0])) - 1)];
        NSInteger focal35 = EXRandomInteger(13, 77);
        double exposureSeconds = 1.0 / (double)shutter;

        tiff[(NSString *)kCGImagePropertyTIFFMake] = make;
        tiff[(NSString *)kCGImagePropertyTIFFModel] = model;
        tiff[(NSString *)kCGImagePropertyTIFFSoftware] = [EXDevice systemDescription];
        tiff[(NSString *)kCGImagePropertyTIFFArtist] = make;
        tiff[(NSString *)kCGImagePropertyTIFFXResolution] = @72;
        tiff[(NSString *)kCGImagePropertyTIFFYResolution] = @72;
        tiff[(NSString *)kCGImagePropertyTIFFResolutionUnit] = @2;

        exif[(NSString *)kCGImagePropertyExifLensMake] = make;
        exif[(NSString *)kCGImagePropertyExifLensModel] = [NSString stringWithFormat:@"%@ back camera %.3fmm f/%.2f",
                                                           model, focal, fnumber];
        exif[(NSString *)kCGImagePropertyExifLensSpecification] = @[@(focal), @(focal), @(fnumber), @(fnumber)];
        exif[(NSString *)kCGImagePropertyExifFocalLength] = @(focal);
        exif[(NSString *)kCGImagePropertyExifFocalLenIn35mmFilm] = @(focal35);
        exif[(NSString *)kCGImagePropertyExifFNumber] = @(fnumber);
        exif[(NSString *)kCGImagePropertyExifApertureValue] = @(2.0 * log2(fnumber));
        exif[(NSString *)kCGImagePropertyExifMaxApertureValue] = @(2.0 * log2(fnumber));
        exif[(NSString *)kCGImagePropertyExifExposureTime] = @(exposureSeconds);
        exif[(NSString *)kCGImagePropertyExifShutterSpeedValue] = @(log2((double)shutter));
        exif[(NSString *)kCGImagePropertyExifBrightnessValue] = @(EXRandomDouble(-1.0, 8.0));
        exif[(NSString *)kCGImagePropertyExifExposureBiasValue] = @0;
        exif[(NSString *)kCGImagePropertyExifExposureProgram] = @2;
        exif[(NSString *)kCGImagePropertyExifExposureMode] = @0;
        exif[(NSString *)kCGImagePropertyExifISOSpeedRatings] = @[@(iso)];
        exif[(NSString *)kCGImagePropertyExifMeteringMode] = @5;
        exif[(NSString *)kCGImagePropertyExifFlash] = @16;
        exif[(NSString *)kCGImagePropertyExifWhiteBalance] = @0;
        exif[(NSString *)kCGImagePropertyExifColorSpace] = @1;
        exif[(NSString *)kCGImagePropertyExifSensingMethod] = @2;
        exif[(NSString *)kCGImagePropertyExifSceneType] = @1;
        exif[(NSString *)kCGImagePropertyExifSceneCaptureType] = @0;
        exif[(NSString *)kCGImagePropertyExifDigitalZoomRatio] = @1;
    }

    if (options & EXWriteTime) {
        NSTimeZone *timeZone = [NSTimeZone localTimeZone];
        NSString *dateString = EXDateFormat(now, timeZone);
        NSString *offset = [EXDevice offsetStringForDate:now];
        NSTimeInterval interval = [now timeIntervalSince1970];
        NSString *subsec = [NSString stringWithFormat:@"%03d", (int)((interval - floor(interval)) * 1000.0)];

        tiff[(NSString *)kCGImagePropertyTIFFDateTime] = dateString;
        exif[(NSString *)kCGImagePropertyExifDateTimeOriginal] = dateString;
        exif[(NSString *)kCGImagePropertyExifDateTimeDigitized] = dateString;
        exif[(NSString *)kCGImagePropertyExifOffsetTime] = offset;
        exif[(NSString *)kCGImagePropertyExifOffsetTimeOriginal] = offset;
        exif[(NSString *)kCGImagePropertyExifOffsetTimeDigitized] = offset;
        exif[(NSString *)kCGImagePropertyExifSubsecTimeOriginal] = subsec;
    }

    if ((options & EXWriteLocation) && location != nil) {
        double latitude = location.coordinate.latitude;
        double longitude = location.coordinate.longitude;
        NSCalendar *utcCalendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        utcCalendar.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        NSDateComponents *utc = [utcCalendar components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                                         NSCalendarUnitDay | NSCalendarUnitHour |
                                                         NSCalendarUnitMinute | NSCalendarUnitSecond)
                                               fromDate:now];

        gps[(NSString *)kCGImagePropertyGPSLatitude] = @(fabs(latitude));
        gps[(NSString *)kCGImagePropertyGPSLatitudeRef] = latitude >= 0 ? @"N" : @"S";
        gps[(NSString *)kCGImagePropertyGPSLongitude] = @(fabs(longitude));
        gps[(NSString *)kCGImagePropertyGPSLongitudeRef] = longitude >= 0 ? @"E" : @"W";
        gps[(NSString *)kCGImagePropertyGPSAltitude] = @(fabs(location.altitude));
        gps[(NSString *)kCGImagePropertyGPSAltitudeRef] = location.altitude >= 0 ? @0 : @1;
        gps[(NSString *)kCGImagePropertyGPSDateStamp] = [NSString stringWithFormat:@"%04ld:%02ld:%02ld",
                                                          (long)utc.year, (long)utc.month, (long)utc.day];
        gps[(NSString *)kCGImagePropertyGPSMapDatum] = @"WGS-84";
        gps[(NSString *)kCGImagePropertyGPSProcessingMethod] = @"GPS";
        if (location.speed >= 0) {
            gps[(NSString *)kCGImagePropertyGPSSpeed] = @(location.speed);
            gps[(NSString *)kCGImagePropertyGPSSpeedRef] = @"K";
        }
        if (location.course >= 0) {
            gps[(NSString *)kCGImagePropertyGPSImgDirection] = @(location.course);
            gps[(NSString *)kCGImagePropertyGPSImgDirectionRef] = @"T";
        }
        if (location.horizontalAccuracy > 0) {
            gps[(NSString *)kCGImagePropertyGPSDOP] = @(MAX(1.0, location.horizontalAccuracy / 5.0));
        }
        if (location.horizontalAccuracy >= 0) {
            gps[(NSString *)kCGImagePropertyGPSHPositioningError] = @(location.horizontalAccuracy);
        }
        properties[(NSString *)kCGImagePropertyGPSDictionary] = gps;
    } else {
        // AddImageFromSource 会以源照片的属性为底稿，删键不会清掉源里的 GPS：
        // 这里先不写 GPS，写完后再用 CopyImageSource 的 ExcludeGPS 选项无损剥掉。
        stripGPS = (properties[(NSString *)kCGImagePropertyGPSDictionary] != nil);
        [properties removeObjectForKey:(NSString *)kCGImagePropertyGPSDictionary];
    }

    // 说明类字段一律清空：AddImageFromSource 是合并语义，只有显式写空值才盖得掉源里的说明。
    tiff[(NSString *)kCGImagePropertyTIFFImageDescription] = @"";
    exif[(NSString *)kCGImagePropertyExifUserComment] = @"";
    NSMutableDictionary *iptc = [properties[(NSString *)kCGImagePropertyIPTCDictionary] mutableCopy];
    if (iptc == nil) {
        iptc = [NSMutableDictionary dictionary];
    }
    iptc[(NSString *)kCGImagePropertyIPTCCaptionAbstract] = @"";
    iptc[(NSString *)kCGImagePropertyIPTCHeadline] = @"";
    iptc[(NSString *)kCGImagePropertyIPTCObjectName] = @"";
    properties[(NSString *)kCGImagePropertyIPTCDictionary] = iptc;

    properties[(NSString *)kCGImagePropertyTIFFDictionary] = tiff;
    properties[(NSString *)kCGImagePropertyExifDictionary] = exif;

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)dst, outputType, 1, NULL);
    if (destination == NULL) {
        CFRelease(source);
        if (error) {
            *error = [NSError errorWithDomain:@"EXMetadata" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法写出结果文件"}];
        }
        return NO;
    }
    CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)properties);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CFRelease(source);

    if (ok && stripGPS) {
        NSURL *stripped = [dst URLByAppendingPathExtension:@"strip"];
        BOOL cleared = NO;

        if ([self stripGPSFromURL:dst toURL:stripped error:NULL]) {
            NSDictionary *check = [self propertiesAtURL:stripped];
            if (check[(NSString *)kCGImagePropertyGPSDictionary] == nil &&
                check[(NSString *)kCGImagePropertyPixelWidth] != nil) {
                cleared = EXReplaceFile(dst, stripped);
            } else {
                [[NSFileManager defaultManager] removeItemAtURL:stripped error:NULL];
            }
        } else {
            [[NSFileManager defaultManager] removeItemAtURL:stripped error:NULL];
        }

        if (!cleared) {
            // HEIF 等容器上 CopyImageSource 不执行 ExcludeGPS：改为解码后按给定属性重编码。
            NSURL *rebuilt = [dst URLByAppendingPathExtension:@"rebuild"];
            NSMutableDictionary *rebuiltProperties = [properties mutableCopy];
            rebuiltProperties[(NSString *)kCGImageDestinationLossyCompressionQuality] = @0.95;
            if ([self rewriteDecodedFromURL:dst toURL:rebuilt properties:rebuiltProperties
                                       type:outputType error:NULL]) {
                cleared = EXReplaceFile(dst, rebuilt);
            }
        }

        if (!cleared) {
            if (error) {
                *error = [NSError errorWithDomain:@"EXMetadata" code:5
                                         userInfo:@{NSLocalizedDescriptionKey: @"无法清除照片原有的位置信息"}];
            }
            return NO;
        }
    }

    if (ok) {
        NSDictionary *finalProperties = [self propertiesAtURL:dst];
        if (finalProperties[(NSString *)kCGImagePropertyPixelWidth] == nil) {
            ok = NO;
            if (error) {
                *error = [NSError errorWithDomain:@"EXMetadata" code:7
                                         userInfo:@{NSLocalizedDescriptionKey: @"写出的图片读不回来"}];
            }
        }
    }

    if (!ok && error) {
        *error = [NSError errorWithDomain:@"EXMetadata" code:4
                                 userInfo:@{NSLocalizedDescriptionKey: @"写入元数据失败"}];
    }
    return ok;
}

+ (BOOL)rewriteDecodedFromURL:(NSURL *)input toURL:(NSURL *)output
                   properties:(NSDictionary *)properties type:(CFStringRef)type error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)input, NULL);
    if (source == NULL) {
        return NO;
    }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (image == NULL) {
        return NO;
    }
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)output, type, 1, NULL);
    if (destination == NULL) {
        CGImageRelease(image);
        return NO;
    }
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)properties);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);
    if (!ok && error != NULL) {
        *error = [NSError errorWithDomain:@"EXMetadata" code:6
                                 userInfo:@{NSLocalizedDescriptionKey: @"重新编码失败"}];
    }
    return ok;
}

+ (BOOL)stripGPSFromURL:(NSURL *)input toURL:(NSURL *)output error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)input, NULL);
    if (source == NULL) {
        return NO;
    }
    CFStringRef type = CGImageSourceGetType(source);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)output, type, 1, NULL);
    if (destination == NULL) {
        CFRelease(source);
        return NO;
    }
    NSDictionary *options = @{(__bridge NSString *)kCGImageMetadataShouldExcludeGPS: @YES};
    CFErrorRef cfError = NULL;
    BOOL ok = CGImageDestinationCopyImageSource(destination, source,
                                                (__bridge CFDictionaryRef)options, &cfError);
    CFRelease(destination);
    CFRelease(source);

    if (!ok && error != NULL) {
        NSString *reason = @"无法清除照片原有的位置信息";
        if (cfError != NULL) {
            NSError *converted = (__bridge_transfer NSError *)cfError;
            if (converted.localizedDescription.length > 0) {
                reason = converted.localizedDescription;
            }
        } else {
            cfError = NULL;
        }
        *error = [NSError errorWithDomain:@"EXMetadata" code:5
                                 userInfo:@{NSLocalizedDescriptionKey: reason}];
    } else if (cfError != NULL) {
        CFRelease(cfError);
    }
    return ok;
}

@end
