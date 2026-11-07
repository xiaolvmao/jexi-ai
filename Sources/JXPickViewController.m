//
//  JXPickViewController.m
//  jexi-ai — 第一页：从相册挑一张照片，然后进入功能页。
//

#import "JXPickViewController.h"
#import "JXRootViewController.h"
#import "JXImageIO.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface JXPickViewController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *hintLabel;
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
    stack.spacing = 14;
    [self.view addSubview:stack];

    UILabel *title = [UILabel new];
    title.text = @"选择图片";
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];
    [stack addArrangedSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.text = @"从相册挑一张照片，下一步再选模型和超分";
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    subtitle.numberOfLines = 0;
    [stack addArrangedSubview:subtitle];
    [stack setCustomSpacing:22 afterView:subtitle];

    // the whole card is the button: tapping anywhere opens the photo picker
    self.card = [UIView new];
    self.card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    self.card.layer.cornerRadius = 22;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card.heightAnchor constraintEqualToConstant:330].active = YES;
    [stack addArrangedSubview:self.card];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(pickPhoto)];
    [self.card addGestureRecognizer:tap];

    UIImageView *glyph = [UIImageView new];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    glyph.tintColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
    glyph.image = [UIImage systemImageNamed:@"photo.on.rectangle.angled"
                          withConfiguration:[UIImageSymbolConfiguration
                                                configurationWithPointSize:64
                                                                weight:UIImageSymbolWeightLight]];
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    [self.card addSubview:glyph];

    UILabel *pickLabel = [UILabel new];
    pickLabel.text = @"点这里选一张照片";
    pickLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    pickLabel.textColor = [UIColor colorWithWhite:0.95 alpha:1];
    pickLabel.textAlignment = NSTextAlignmentCenter;
    pickLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:pickLabel];

    self.hintLabel = [UILabel new];
    self.hintLabel.text = @"支持 JPEG / HEIC / PNG，原图不会被修改";
    self.hintLabel.font = [UIFont systemFontOfSize:12];
    self.hintLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.hintLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                        constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [glyph.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:self.card.centerYAnchor constant:-34],
        [glyph.widthAnchor constraintEqualToConstant:96],
        [glyph.heightAnchor constraintEqualToConstant:96],

        [pickLabel.topAnchor constraintEqualToAnchor:glyph.bottomAnchor constant:18],
        [pickLabel.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [pickLabel.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],

        [self.hintLabel.topAnchor constraintEqualToAnchor:pickLabel.bottomAnchor constant:8],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
        [self.spinner.topAnchor constraintEqualToAnchor:self.hintLabel.bottomAnchor constant:12],
    ]];

    UILabel *foot = [UILabel new];
    foot.text = @"全部处理都在本机完成，照片不会上传。";
    foot.font = [UIFont systemFontOfSize:12];
    foot.textColor = [UIColor colorWithWhite:0.42 alpha:1];
    foot.numberOfLines = 0;
    [stack addArrangedSubview:foot];
}

- (void)pickPhoto
{
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 1;
    cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    NSItemProvider *provider = results.firstObject.itemProvider;
    NSString *type = UTTypeImage.identifier;
    if (![provider hasItemConformingToTypeIdentifier:type]) {
        type = provider.registeredTypeIdentifiers.firstObject;
    }
    if (!type) return;

    self.hintLabel.text = @"正在读取这张照片…";
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    // loadFileRepresentation hands back the file the asset is stored as; the
    // data representation can be a downscaled transcode.
    [provider loadFileRepresentationForTypeIdentifier:type
                                    completionHandler:^(NSURL *url, NSError *error) {
        NSData *data = url ? [NSData dataWithContentsOfURL:url options:0 error:NULL] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            [self.spinner stopAnimating];
            self.hintLabel.text = @"支持 JPEG / HEIC / PNG，原图不会被修改";
            if (!data) {
                [self alertWithTitle:@"读不到这张照片" message:error.localizedDescription];
                return;
            }
            NSDictionary *properties = JXImagePropertiesFromData(data);
            UIImage *image = [UIImage imageWithData:data scale:1.0];
            JXNote(@"picked %lu bytes (%@), exif=%lu tiff=%lu gps=%lu, w=%@ h=%@ keys=%lu",
                   (unsigned long)data.length, type,
                   (unsigned long)[properties[(id)kCGImagePropertyExifDictionary] count],
                   (unsigned long)[properties[(id)kCGImagePropertyTIFFDictionary] count],
                   (unsigned long)[properties[(id)kCGImagePropertyGPSDictionary] count],
                   properties[(id)kCGImagePropertyPixelWidth],
                   properties[(id)kCGImagePropertyPixelHeight],
                   (unsigned long)properties.count);
            if (!image) {
                [self alertWithTitle:@"解不开这张照片" message:@"换一张试试。"];
                return;
            }
            JXRootViewController *work =
                [[JXRootViewController alloc] initWithImageData:data
                                                     properties:properties
                                                        preview:image];
            [self.navigationController pushViewController:work animated:YES];
        });
    }];
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
