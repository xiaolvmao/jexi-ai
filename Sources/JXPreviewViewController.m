//
//  JXPreviewViewController.m
//  jexi-ai — 结果预览、与原图对比、保存到相册。
//

#import "JXPreviewViewController.h"
#import "JXImageIO.h"

@interface JXPreviewViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *resultImage;
@property (nonatomic, strong) UIImage *originalImage;
@property (nonatomic, strong) NSDictionary *properties;
@property (nonatomic, assign) BOOL prescaled;
@property (nonatomic, assign) BOOL alreadySaved;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UISegmentedControl *compareControl;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, assign) BOOL showingOriginal;
@end

@implementation JXPreviewViewController

- (instancetype)initWithResultImage:(UIImage *)result
                      originalImage:(UIImage *)original
                         properties:(NSDictionary *)properties
                          prescaled:(BOOL)prescaled
{
    return [self initWithResultImage:result
                       originalImage:original
                          properties:properties
                           prescaled:prescaled
                               saved:NO];
}

- (instancetype)initWithResultImage:(UIImage *)result
                      originalImage:(UIImage *)original
                         properties:(NSDictionary *)properties
                          prescaled:(BOOL)prescaled
                              saved:(BOOL)saved
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _resultImage = result;
        _originalImage = original;
        _properties = properties;
        _prescaled = prescaled;
        _alreadySaved = saved;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"超分结果";
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1];

    self.compareControl = [[UISegmentedControl alloc] initWithItems:@[ @"超分后", @"原图" ]];
    self.compareControl.selectedSegmentIndex = 0;
    self.compareControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.compareControl addTarget:self action:@selector(compareChanged)
                  forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.compareControl];

    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 6.0;
    self.scrollView.backgroundColor = [UIColor blackColor];
    self.scrollView.layer.cornerRadius = 12;
    self.scrollView.clipsToBounds = YES;
    [self.view addSubview:self.scrollView];

    self.imageView = [UIImageView new];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.image = self.resultImage;
    [self.scrollView addSubview:self.imageView];

    self.infoLabel = [UILabel new];
    self.infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.infoLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.infoLabel.numberOfLines = 0;
    self.infoLabel.textColor = self.prescaled
        ? [UIColor colorWithRed:1 green:0.78 blue:0.35 alpha:1]
        : [UIColor colorWithWhite:0.62 alpha:1];
    [self.view addSubview:self.infoLabel];

    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.saveButton setTitle:@"保存到相册" forState:UIControlStateNormal];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.saveButton.backgroundColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
    self.saveButton.layer.cornerRadius = 23;
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.saveButton addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.saveButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.compareControl.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.compareControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.compareControl.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-40],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.compareControl.bottomAnchor constant:12],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.infoLabel.topAnchor constant:-10],

        [self.infoLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.infoLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.infoLabel.bottomAnchor constraintEqualToAnchor:self.saveButton.topAnchor constant:-12],

        [self.saveButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.saveButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.saveButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-14],
        [self.saveButton.heightAnchor constraintEqualToConstant:46],
    ]];

    [self updateInfo];

    if (self.alreadySaved) {
        self.saveButton.enabled = NO;
        self.saveButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        [self.saveButton setTitle:@"已保存到相册" forState:UIControlStateNormal];
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.imageView.frame = self.scrollView.bounds;
    self.scrollView.contentSize = self.scrollView.bounds.size;
    self.scrollView.zoomScale = 1.0;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    CGSize size = scrollView.bounds.size;
    CGFloat x = MAX((size.width - scrollView.contentSize.width) / 2.0, 0.0);
    CGFloat y = MAX((size.height - scrollView.contentSize.height) / 2.0, 0.0);
    scrollView.contentInset = UIEdgeInsetsMake(y, x, y, x);
}

- (void)compareChanged
{
    self.showingOriginal = (self.compareControl.selectedSegmentIndex == 1);
    self.imageView.image = self.showingOriginal ? self.originalImage : self.resultImage;
    self.scrollView.zoomScale = 1.0;
    [self updateInfo];
}

- (void)updateInfo
{
    CGSize result = self.resultImage.size;
    CGSize original = self.originalImage.size;
    NSMutableString *text = [NSMutableString stringWithFormat:@"输出 %.0f×%.0f · 原图 %.0f×%.0f",
                                                                 result.width, result.height,
                                                                 original.width, original.height];
    if (self.showingOriginal) {
        [text appendString:@" · 正在看原图"];
    }
    if (self.prescaled) {
        [text appendString:@"\n原图过大，已按 4096 长边上限处理"];
    }
    self.infoLabel.text = text;
}

- (void)saveTapped
{
    self.saveButton.enabled = NO;
    [self.saveButton setTitle:@"保存中…" forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    JXSaveImageToPhotoLibrary(self.resultImage, self.properties, ^(BOOL ok, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        self.saveButton.enabled = YES;
        [self.saveButton setTitle:@"保存到相册" forState:UIControlStateNormal];
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:ok ? @"已保存" : @"保存失败"
                             message:ok ? @"新照片已加入相册，原图没有改动。"
                                        : error.localizedDescription
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    });
}

@end
