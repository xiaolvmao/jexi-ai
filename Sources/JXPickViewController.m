//
//  JXPickViewController.m
//  jexi-ai — 启动即弹相册选图；取消后停在这里，可以再点一次。
//

#import "JXPickViewController.h"
#import "JXMetaViewController.h"
#import "JXImageIO.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface JXPickViewController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIButton *pickButton;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL presenting;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL askedOnce;
@end

@implementation JXPickViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"jexi-ai";
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:stack];

    UIImageView *glyph = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"photo.on.rectangle.angled"
                withConfiguration:[UIImageSymbolConfiguration
                                      configurationWithPointSize:56
                                                      weight:UIImageSymbolWeightLight]]];
    glyph.tintColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    [glyph.widthAnchor constraintEqualToConstant:80].active = YES;
    [glyph.heightAnchor constraintEqualToConstant:80].active = YES;
    [stack addArrangedSubview:glyph];

    self.hintLabel = [UILabel new];
    self.hintLabel.text = @"选一张照片";
    self.hintLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.hintLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.numberOfLines = 0;
    [stack addArrangedSubview:self.hintLabel];

    self.pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pickButton setTitle:@"选择图片" forState:UIControlStateNormal];
    [self.pickButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pickButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.pickButton.backgroundColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
    self.pickButton.layer.cornerRadius = 23;
    [self.pickButton addTarget:self action:@selector(openPicker) forControlEvents:UIControlEventTouchUpInside];
    self.pickButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pickButton.widthAnchor constraintEqualToConstant:180].active = YES;
    [self.pickButton.heightAnchor constraintEqualToConstant:46].active = YES;
    [stack addArrangedSubview:self.pickButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [stack addArrangedSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    // 进软件直接选图：第一次进来、或者从处理页返回，都自动弹相册
    if (self.presenting || self.cancelled) return;
    if (self.navigationController.viewControllers.count > 1) return;
    if (self.presentedViewController) return;
    [self openPicker];
}

- (void)openPicker
{
    self.cancelled = NO;
    self.presenting = YES;
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 1;
    cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - picking

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    self.presenting = NO;
    self.askedOnce = YES;
    if (results.count == 0) {
        self.cancelled = YES;
        self.hintLabel.text = @"还没有选照片";
        return;
    }
    self.hintLabel.text = @"正在读取照片…";
    [self.spinner startAnimating];
    self.pickButton.enabled = NO;

    NSItemProvider *provider = results.firstObject.itemProvider;
    NSString *type = [provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier]
        ? UTTypeImage.identifier
        : provider.registeredTypeIdentifiers.firstObject;
    if (!type) {
        [self finishWithMessage:@"读不到这张照片"];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadFileRepresentationForTypeIdentifier:type
                                    completionHandler:^(NSURL *url, NSError *error) {
        NSData *data = url ? [NSData dataWithContentsOfURL:url options:0 error:NULL] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            [self.spinner stopAnimating];
            self.pickButton.enabled = YES;
            self.hintLabel.text = @"选一张照片";
            if (!data) {
                [self alertWithTitle:@"读不到这张照片" message:error.localizedDescription];
                return;
            }
            UIImage *image = [UIImage imageWithData:data scale:1.0];
            if (!image) {
                [self alertWithTitle:@"解不开这张照片" message:@"换一张试试。"];
                return;
            }
            NSDictionary *properties = JXImagePropertiesFromData(data);
            JXNote(@"picked %lu bytes (%@), exif=%lu tiff=%lu gps=%lu, w=%@ h=%@",
                   (unsigned long)data.length, type,
                   (unsigned long)[properties[(id)kCGImagePropertyExifDictionary] count],
                   (unsigned long)[properties[(id)kCGImagePropertyTIFFDictionary] count],
                   (unsigned long)[properties[(id)kCGImagePropertyGPSDictionary] count],
                   properties[(id)kCGImagePropertyPixelWidth],
                   properties[(id)kCGImagePropertyPixelHeight]);

            // 拷一份自己的副本，选择器给的临时文件随时会被删
            NSURL *dir = [NSURL fileURLWithPath:
                [NSTemporaryDirectory() stringByAppendingPathComponent:@"picked"]];
            [[NSFileManager defaultManager] createDirectoryAtURL:dir
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:NULL];
            NSURL *copy = [dir URLByAppendingPathComponent:
                [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString],
                                           url.pathExtension.length ? url.pathExtension : @"img"]];
            NSError *writeError = nil;
            if (![data writeToURL:copy options:NSDataWritingAtomic error:&writeError]) {
                [self alertWithTitle:@"保存副本失败" message:writeError.localizedDescription];
                return;
            }
            self.cancelled = NO;
            JXMetaViewController *vc =
                [[JXMetaViewController alloc] initWithFileURLs:@[ copy ]];
            [self.navigationController pushViewController:vc animated:YES];
        });
    }];
}

- (void)finishWithMessage:(NSString *)message
{
    [self.spinner stopAnimating];
    self.pickButton.enabled = YES;
    self.hintLabel.text = @"选一张照片";
    [self alertWithTitle:@"选图失败" message:message];
}

- (void)alertWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
