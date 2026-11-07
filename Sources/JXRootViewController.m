//
//  JXRootViewController.m
//  jexi-ai — 选照片、选模型、跑超分、看进度。
//

#import "JXRootViewController.h"
#import "JXPreviewViewController.h"
#import "JXUpscaler.h"
#import "JXModelCatalog.h"
#import "JXImageIO.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const long long kMaxOutputEdge = 4096;

@interface JXRootViewController () <PHPickerViewControllerDelegate,
                                    UIDocumentPickerDelegate>
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UIButton *pickButton;
@property (nonatomic, strong) UISegmentedControl *modelControl;
@property (nonatomic, strong) UILabel *modelDetailLabel;
@property (nonatomic, strong) UILabel *capNoticeLabel;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIStackView *progressStack;

@property (nonatomic, strong) NSData *sourceData;
@property (nonatomic, strong) NSDictionary *sourceProperties;
@property (nonatomic, strong) UIImage *sourcePreview;
@property (nonatomic, assign) JXModelKind kind;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL cancelRequested;
@end

@implementation JXRootViewController

#pragma mark - lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"jexi-ai";
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1];
    self.navigationController.navigationBar.translucent = YES;
    [self buildUI];
    [self refreshModelDetail];
    [self setRunningUI:NO];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

#pragma mark - UI

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font colour:(UIColor *)colour
{
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = font;
    l.textColor = colour;
    l.numberOfLines = 0;
    return l;
}

- (void)buildUI
{
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.layoutMargins = UIEdgeInsetsMake(18, 20, 28, 20);
    stack.layoutMarginsRelativeArrangement = YES;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];

    UILabel *title = [self labelWithText:@"jexi-ai"
                                    font:[UIFont systemFontOfSize:34 weight:UIFontWeightBold]
                                  colour:[UIColor whiteColor]];
    [stack addArrangedSubview:title];

    UILabel *subtitle = [self labelWithText:@"把一张照片放大 4 倍 · 全部在本机完成，不上传"
                                       font:[UIFont systemFontOfSize:13]
                                     colour:[UIColor colorWithWhite:0.62 alpha:1]];
    [stack addArrangedSubview:subtitle];
    [stack setCustomSpacing:20 afterView:subtitle];

    // photo card
    UIView *card = [UIView new];
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    card.layer.cornerRadius = 16;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card.heightAnchor constraintEqualToConstant:230].active = YES;
    [stack addArrangedSubview:card];

    self.photoView = [UIImageView new];
    self.photoView.translatesAutoresizingMaskIntoConstraints = NO;
    self.photoView.contentMode = UIViewContentModeScaleAspectFill;
    self.photoView.clipsToBounds = YES;
    [card addSubview:self.photoView];
    self.placeholderLabel = [self labelWithText:@"还没有选照片"
                                           font:[UIFont systemFontOfSize:15]
                                         colour:[UIColor colorWithWhite:0.5 alpha:1]];
    self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:self.placeholderLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.photoView.topAnchor constraintEqualToAnchor:card.topAnchor],
        [self.photoView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [self.photoView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.photoView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [self.placeholderLabel.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [self.placeholderLabel.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];

    self.pickButton = [self pillButtonWithTitle:@"选择照片" filled:NO];
    [self.pickButton addTarget:self action:@selector(pickPhoto) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.pickButton];

    UILabel *modelTitle = [self labelWithText:@"模型"
                                         font:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]
                                       colour:[UIColor colorWithWhite:0.62 alpha:1]];
    [stack addArrangedSubview:modelTitle];

    self.modelControl = [[UISegmentedControl alloc] initWithItems:@[
        [JXModelCatalog titleForKind:JXModelKindRealESRGAN],
        [JXModelCatalog titleForKind:JXModelKindFastSRGAN],
        [JXModelCatalog titleForKind:JXModelKindUser],
    ]];
    self.modelControl.selectedSegmentIndex = 0;
    self.modelControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelControl addTarget:self action:@selector(modelChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.modelControl];

    self.modelDetailLabel = [self labelWithText:@""
                                           font:[UIFont systemFontOfSize:12]
                                         colour:[UIColor colorWithWhite:0.62 alpha:1]];
    [stack addArrangedSubview:self.modelDetailLabel];

    self.capNoticeLabel = [self labelWithText:
        @"输出长边上限 4096 像素。原图更大时会先高质量降采样再超分。"
                                          font:[UIFont systemFontOfSize:12]
                                        colour:[UIColor colorWithWhite:0.45 alpha:1]];
    [stack addArrangedSubview:self.capNoticeLabel];
    [stack setCustomSpacing:20 afterView:self.capNoticeLabel];

    self.runButton = [self pillButtonWithTitle:@"开始超分" filled:YES];
    [self.runButton addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.runButton];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [UIColor colorWithRed:0.35 green:0.78 blue:1 alpha:1];
    self.progressLabel = [self labelWithText:@""
                                       font:[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular]
                                     colour:[UIColor colorWithWhite:0.75 alpha:1]];
    self.cancelButton = [self pillButtonWithTitle:@"取消" filled:NO];
    [self.cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];

    self.progressStack = [UIStackView new];
    [self.progressStack addArrangedSubview:self.progressView];
    [self.progressStack addArrangedSubview:self.progressLabel];
    [self.progressStack addArrangedSubview:self.cancelButton];
    self.progressStack.axis = UILayoutConstraintAxisVertical;
    self.progressStack.spacing = 8;
    [stack addArrangedSubview:self.progressStack];

    UIButton *about = [self pillButtonWithTitle:@"模型来源与许可证" filled:NO];
    about.titleLabel.font = [UIFont systemFontOfSize:13];
    [about addTarget:self action:@selector(showLicences) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:about];
}

- (UIButton *)pillButtonWithTitle:(NSString *)title filled:(BOOL)filled
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.heightAnchor constraintEqualToConstant:46].active = YES;
    b.layer.cornerRadius = 23;
    if (filled) {
        b.backgroundColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        [b setTitleColor:[UIColor colorWithWhite:0.95 alpha:1] forState:UIControlStateNormal];
    }
    return b;
}

#pragma mark - state

- (void)refreshModelDetail
{
    JXModelKind kind = (self.modelControl.selectedSegmentIndex == 0)
        ? JXModelKindRealESRGAN
        : (self.modelControl.selectedSegmentIndex == 1 ? JXModelKindFastSRGAN : JXModelKindUser);
    self.kind = kind;
    NSString *detail = [JXModelCatalog oneLineForKind:kind];
    if (kind == JXModelKindUser) {
        NSURL *u = [JXModelCatalog shared].userModelURL;
        detail = u ? [NSString stringWithFormat:@"已导入：%@", u.lastPathComponent]
                   : @"点这里导入一个 .mlmodel / .mlpackage";
    }
    self.modelDetailLabel.text = detail;
    [self updateRunButton];
}

- (void)updateRunButton
{
    BOOL ready = self.sourceData != nil && !self.running;
    if (self.kind == JXModelKindUser && ![JXModelCatalog shared].userModelURL) ready = NO;
    self.runButton.enabled = ready;
    self.runButton.alpha = ready ? 1.0 : 0.4;
    self.pickButton.enabled = !self.running;
}

- (void)setRunningUI:(BOOL)running
{
    self.running = running;
    self.progressStack.hidden = !running;
    self.modelControl.enabled = !running;
    self.pickButton.enabled = !running;
    [self updateRunButton];
}

- (void)updateStatusText:(NSString *)text fraction:(double)fraction
{
    self.progressLabel.text = text ?: @"";
    if (fraction >= 0) [self.progressView setProgress:(float)fraction animated:NO];
}

- (void)modelChanged
{
    [self refreshModelDetail];
    if (self.kind == JXModelKindUser && ![JXModelCatalog shared].userModelURL) {
        [self importUserModel];
    }
}

#pragma mark - picking

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
    __weak typeof(self) weakSelf = self;
    [provider loadDataRepresentationForTypeIdentifier:type
                                   completionHandler:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            if (!data) {
                [self alertWithTitle:@"读不到这张照片" message:error.localizedDescription];
                return;
            }
            self.sourceData = data;
            self.sourceProperties = JXImagePropertiesFromData(data);
            UIImage *image = [UIImage imageWithData:data scale:1.0];
            self.sourcePreview = image;
            self.photoView.image = image;
            self.placeholderLabel.hidden = YES;
            [self showSourceSummary];
            [self updateRunButton];
        });
    }];
}

- (void)showSourceSummary
{
    CGSize size = self.sourcePreview.size;
    NSNumber *w = self.sourceProperties[(id)kCGImagePropertyPixelWidth];
    NSNumber *h = self.sourceProperties[(id)kCGImagePropertyPixelHeight];
    long long pw = w ? w.longLongValue : (long long)size.width;
    long long ph = h ? h.longLongValue : (long long)size.height;
    long long outW = pw * 4, outH = ph * 4;
    long long longest = MAX(outW, outH);
    NSString *cap = @"";
    if (longest > kMaxOutputEdge) {
        double f = (double)kMaxOutputEdge / (double)longest;
        cap = [NSString stringWithFormat:@"　原图过大，将按上限处理（约 %lld×%lld）",
                                         (long long)llround(outW * f),
                                         (long long)llround(outH * f)];
    }
    self.capNoticeLabel.text =
        [NSString stringWithFormat:@"原图 %lld×%lld → 输出 %lld×%lld。%@",
                                   pw, ph, outW, outH, cap];
    self.capNoticeLabel.textColor = longest > kMaxOutputEdge
        ? [UIColor colorWithRed:1 green:0.78 blue:0.35 alpha:1]
        : [UIColor colorWithWhite:0.45 alpha:1];
}

- (void)importUserModel
{
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeItem ]
                                                                   asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSError *error = nil;
    if (![[JXModelCatalog shared] importUserModelFromURL:url error:&error]) {
        [self alertWithTitle:@"导入失败" message:error.localizedDescription];
        [self.modelControl setSelectedSegmentIndex:0];
        [self refreshModelDetail];
        return;
    }
    [self refreshModelDetail];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    if (self.kind == JXModelKindUser && ![JXModelCatalog shared].userModelURL) {
        [self.modelControl setSelectedSegmentIndex:0];
        [self refreshModelDetail];
    }
}

#pragma mark - running

- (void)startTapped
{
    if (self.running || !self.sourceData) return;
    NSData *data = self.sourceData;
    JXModelKind kind = self.kind;
    self.cancelRequested = NO;
    [self setRunningUI:YES];
    [self updateStatusText:@"准备中…" fraction:0];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        NSError *error = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateStatusText:@"加载模型…" fraction:0];
        });
        JXSRModel *model = [[JXModelCatalog shared] modelForKind:kind error:&error];
        if (!model) {
            [self finishWithError:error];
            return;
        }
        CVPixelBufferRef source = JXCreatePixelBufferFromImageData(data, NULL, &error);
        if (!source) {
            [self finishWithError:error];
            return;
        }
        JXUpscaler *upscaler = [[JXUpscaler alloc] initWithModel:model];
        upscaler.maxOutputEdge = kMaxOutputEdge;
        __block BOOL canceled = NO;
        NSDate *started = [NSDate date];
        CVPixelBufferRef output = [upscaler upscalePixelBuffer:source
            progress:^(NSInteger done, NSInteger total, double perTile) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    double elapsed = -[started timeIntervalSinceNow];
                    NSInteger left = total - done;
                    NSString *text = [NSString stringWithFormat:
                        @"第 %ld/%ld 块 · 已用 %.0f 秒 · 预计还剩 %.0f 秒",
                        (long)done, (long)total, elapsed, left * perTile];
                    [self updateStatusText:text fraction:(double)done / (double)MAX(total, 1)];
                });
            }
            canceled:^BOOL {
                return self.cancelRequested;
            }
            error:&error];
        CVPixelBufferRelease(source);
        if (!output) {
            canceled = (error.code == JXUpscalerErrorCanceled);
            [self finishWithError:error canceled:canceled];
            return;
        }
        UIImage *result = JXImageFromPixelBuffer(output);
        BOOL prescaled = upscaler.didPrescale;
        CVPixelBufferRelease(output);
        if (!result) {
            [self finishWithError:[NSError errorWithDomain:@"jexi-ai" code:1 userInfo:@{
                NSLocalizedDescriptionKey : @"结果图创建失败"
            }]];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setRunningUI:NO];
            [self updateStatusText:@"" fraction:0];
            JXPreviewViewController *vc =
                [[JXPreviewViewController alloc] initWithResultImage:result
                                                       originalImage:self.sourcePreview
                                                          properties:self.sourceProperties
                                                           prescaled:prescaled];
            [self.navigationController pushViewController:vc animated:YES];
        });
    });
}

- (void)cancelTapped
{
    self.cancelRequested = YES;
    [self updateStatusText:@"正在取消（当前块算完就停）…" fraction:-1];
    self.cancelButton.enabled = NO;
}

- (void)finishWithError:(NSError *)error
{
    [self finishWithError:error canceled:(error.code == JXUpscalerErrorCanceled)];
}

- (void)finishWithError:(NSError *)error canceled:(BOOL)canceled
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setRunningUI:NO];
        self.cancelButton.enabled = YES;
        [self updateStatusText:@"" fraction:0];
        if (canceled) {
            [self alertWithTitle:@"已取消" message:@"没有生成新照片。"];
        } else {
            [self alertWithTitle:@"超分失败" message:error.localizedDescription ?: @"未知错误"];
        }
    });
}

#pragma mark - misc

- (void)showLicences
{
    NSString *text = [NSString stringWithContentsOfFile:
                          [[NSBundle mainBundle] pathForResource:@"LICENSES" ofType:@"txt"]
                                             encoding:NSUTF8StringEncoding
                                                error:NULL];
    UIViewController *vc = [UIViewController new];
    vc.title = @"模型来源与许可证";
    vc.view.backgroundColor = self.view.backgroundColor;
    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.backgroundColor = [UIColor clearColor];
    tv.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    tv.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    tv.text = text ?: @"缺少 LICENSES.txt";
    tv.editable = NO;
    [vc.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:16],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-16],
        [tv.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
    [self.navigationController pushViewController:vc animated:YES];
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
