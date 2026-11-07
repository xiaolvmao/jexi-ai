//
//  JXPickViewController.m
//  jexi-ai — 第一页：选图。两条入口，AI 超分（单张）和元数据与增强（批量）。
//

#import "JXPickViewController.h"
#import "JXMetaViewController.h"
#import "JXImageIO.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, JXEntryMode) {
    JXEntryModeAI = 0,
    JXEntryModeMetadata = 1,
};

@interface JXPickViewController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, assign) JXEntryMode mode;
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
    subtitle.text = @"先选照片，再决定 AI 超分还是改元数据";
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    subtitle.numberOfLines = 0;
    [stack addArrangedSubview:subtitle];
    [stack setCustomSpacing:20 afterView:subtitle];

    [stack addArrangedSubview:[self cardWithIcon:@"wand.and.stars"
                                           title:@"选择图片"
                                          detail:@"选好照片后，可以 AI 超分，也可以只改元数据"
                                            mode:JXEntryModeMetadata]];

    self.hintLabel = [UILabel new];
    self.hintLabel.text = @"全部处理都在本机完成，照片不会上传。";
    self.hintLabel.font = [UIFont systemFontOfSize:12];
    self.hintLabel.textColor = [UIColor colorWithWhite:0.42 alpha:1];
    self.hintLabel.numberOfLines = 0;
    [stack addArrangedSubview:self.hintLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [stack addArrangedSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

- (UIView *)cardWithIcon:(NSString *)icon title:(NSString *)title detail:(NSString *)detail
                    mode:(JXEntryMode)mode
{
    UIView *card = [UIView new];
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    card.layer.cornerRadius = 20;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *glyph = [UIImageView new];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    glyph.tintColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
    glyph.image = [UIImage systemImageNamed:icon
                          withConfiguration:[UIImageSymbolConfiguration
                                                configurationWithPointSize:26
                                                                weight:UIImageSymbolWeightRegular]];
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:glyph];

    UILabel *name = [UILabel new];
    name.text = title;
    name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    name.textColor = [UIColor whiteColor];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:name];

    UILabel *sub = [UILabel new];
    sub.text = detail;
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    sub.numberOfLines = 0;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sub];

    UIImageView *chevron = [UIImageView new];
    chevron.image = [UIImage systemImageNamed:@"chevron.right"];
    chevron.tintColor = [UIColor colorWithWhite:0.4 alpha:1];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:92],
        [glyph.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [glyph.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [glyph.widthAnchor constraintEqualToConstant:32],
        [glyph.heightAnchor constraintEqualToConstant:32],
        [name.leadingAnchor constraintEqualToAnchor:glyph.trailingAnchor constant:14],
        [name.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],
        [name.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],
        [sub.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
        [sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    [card addGestureRecognizer:tap];
    card.tag = mode;
    return card;
}

- (void)cardTapped:(UITapGestureRecognizer *)tap
{
    self.mode = JXEntryModeMetadata;
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 0;   // 0 = unlimited; 选几张都行
    cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - picking

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;
    self.hintLabel.text = @"正在读取照片…";
    [self.spinner startAnimating];
    [self loadBatch:results];
}

- (NSString *)typeIdentifierFor:(NSItemProvider *)provider
{
    NSString *type = UTTypeImage.identifier;
    if (![provider hasItemConformingToTypeIdentifier:type]) {
        type = provider.registeredTypeIdentifiers.firstObject;
    }
    return type;
}


- (void)loadBatch:(NSArray<PHPickerResult *> *)results
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *dir = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"picked"]];
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];

    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSURL *> *copies = [NSMutableArray array];
    NSLock *lock = [NSLock new];

    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        NSString *type = [self typeIdentifierFor:provider];
        if (!type) continue;
        dispatch_group_enter(group);
        [provider loadFileRepresentationForTypeIdentifier:type
                                        completionHandler:^(NSURL *url, NSError *error) {
            if (url) {
                NSString *name = [NSString stringWithFormat:@"%@-%@", [[NSUUID UUID] UUIDString],
                                                            url.lastPathComponent];
                NSURL *dst = [dir URLByAppendingPathComponent:name];
                if ([fm copyItemAtURL:url toURL:dst error:NULL]) {
                    [lock lock];
                    [copies addObject:dst];
                    [lock unlock];
                }
            }
            dispatch_group_leave(group);
        }];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        [self.spinner stopAnimating];
        self.hintLabel.text = @"全部处理都在本机完成，照片不会上传。";
        if (copies.count == 0) {
            [self alertWithTitle:@"没有读到照片" message:@"重新选一次试试。"];
            return;
        }
        JXMetaViewController *vc = [[JXMetaViewController alloc] initWithFileURLs:copies];
        [self.navigationController pushViewController:vc animated:YES];
    });
}

- (void)finishWithMessage:(NSString *)message
{
    [self.spinner stopAnimating];
    self.hintLabel.text = @"全部处理都在本机完成，照片不会上传。";
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
