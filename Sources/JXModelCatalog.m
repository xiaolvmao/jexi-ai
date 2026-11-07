//
//  JXModelCatalog.m
//  jexi-ai
//

#import "JXModelCatalog.h"

@interface JXModelCatalog ()
@property (nonatomic, strong, nullable) JXSRModel *loadedModel;
@property (nonatomic, assign) JXModelKind loadedKind;
@end

@implementation JXModelCatalog

+ (instancetype)shared
{
    static JXModelCatalog *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [JXModelCatalog new]; });
    return shared;
}

+ (NSString *)titleForKind:(JXModelKind)kind
{
    switch (kind) {
        case JXModelKindRealESRGAN: return @"Real-ESRGAN 4×";
        case JXModelKindFastSRGAN: return @"快速";
        case JXModelKindUser: return @"自备模型";
    }
    return @"?";
}

+ (NSString *)oneLineForKind:(JXModelKind)kind
{
    switch (kind) {
        case JXModelKindRealESRGAN:
            return @"高质量 · 每块约 2.4 秒 · 一张约 15 秒";
        case JXModelKindFastSRGAN:
            return @"快速 · 每块约 0.06 秒 · 一张约 1 秒";
        case JXModelKindUser:
            return @"你导入的 .mlmodel / .mlpackage";
    }
    return @"";
}

- (NSURL *)userModelURL
{
    if (_userModelURL && [[NSFileManager defaultManager] fileExistsAtPath:_userModelURL.path])
        return _userModelURL;
    NSURL *dir = [[self documentsDirectory] URLByAppendingPathComponent:@"UserModels"];
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:dir
                                                  includingPropertiesForKeys:nil
                                                                     options:0
                                                                       error:NULL];
    for (NSURL *u in items) {
        NSString *ext = u.pathExtension;
        if ([ext isEqualToString:@"mlmodel"] || [ext isEqualToString:@"mlpackage"]) {
            _userModelURL = u;
            return u;
        }
    }
    return nil;
}

- (NSURL *)documentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                  inDomains:NSUserDomainMask] firstObject];
}

- (NSURL *)cacheDirectory
{
    NSURL *caches = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory
                                                            inDomains:NSUserDomainMask] firstObject];
    return [caches URLByAppendingPathComponent:@"compiled"];
}

- (nullable NSURL *)bundledModelURLForKind:(JXModelKind)kind
{
    NSString *name = (kind == JXModelKindRealESRGAN) ? @"RealESRGAN4x" : @"FastSRGAN";
    NSURL *u = [[NSBundle mainBundle] URLForResource:name withExtension:@"mlmodel"];
    if (!u) {
        u = [[NSBundle mainBundle] URLForResource:name withExtension:@"mlmodel"
                                         subdirectory:@"Models"];
    }
    return u;
}

- (nullable JXSRModel *)modelForKind:(JXModelKind)kind error:(NSError **)error
{
    if (self.loadedModel && self.loadedKind == kind) return self.loadedModel;

    NSURL *url = (kind == JXModelKindUser) ? self.userModelURL
                                           : [self bundledModelURLForKind:kind];
    if (!url) {
        if (error)
            *error = [NSError errorWithDomain:@"JXModelCatalog"
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             (kind == JXModelKindUser
                                                  ? @"还没有导入自备模型"
                                                  : @"App 内缺少模型文件（打包时漏了）")
                                     }];
        return nil;
    }
    JXSRModel *model = [JXSRModel modelWithContentsOfURL:url
                                          cacheDirectory:[self cacheDirectory]
                                                   error:error];
    if (!model) return nil;
    self.loadedModel = model;
    self.loadedKind = kind;
    return model;
}

- (void)releaseModels
{
    if (self.busy) return;   // 批处理进行中，模型不能收走
    self.loadedModel = nil;
}

- (BOOL)importUserModelFromURL:(NSURL *)url error:(NSError **)error
{
    NSString *ext = url.pathExtension;
    if (![ext isEqualToString:@"mlmodel"] && ![ext isEqualToString:@"mlpackage"]) {
        if (error)
            *error = [NSError errorWithDomain:@"JXModelCatalog"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey :
                                                    @"只支持 .mlmodel 或 .mlpackage"}];
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *dir = [[self documentsDirectory] URLByAppendingPathComponent:@"UserModels"];
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    NSURL *dst = [dir URLByAppendingPathComponent:url.lastPathComponent];
    [fm removeItemAtURL:dst error:NULL];
    // A picked file must be copied while its security scope is open.
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *copyError = nil;
    BOOL ok = [fm copyItemAtURL:url toURL:dst error:&copyError];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!ok) {
        if (error) *error = copyError;
        return NO;
    }
    // Only one user model at a time: drop the compiled copy of the old one.
    for (NSURL *old in [fm contentsOfDirectoryAtURL:dir
                         includingPropertiesForKeys:nil
                                            options:0
                                              error:NULL]) {
        if (![old.lastPathComponent isEqualToString:dst.lastPathComponent])
            [fm removeItemAtURL:old error:NULL];
    }
    [[NSFileManager defaultManager] removeItemAtURL:self.cacheDirectory error:NULL];
    self.userModelURL = dst;
    self.loadedModel = nil;
    return YES;
}

@end
