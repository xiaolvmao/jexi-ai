//
//  JXMetaViewController.m
//  jexi-ai
//

#import "JXMetaViewController.h"
#import "JXPreviewViewController.h"
#import "JXUpscaler.h"
#import "JXModelCatalog.h"
#import "EXDevice.h"
#import "EXMetadata.h"
#import "JXImageIO.h"
#import <CoreLocation/CoreLocation.h>
#import <CommonCrypto/CommonDigest.h>

@interface JXMetaViewController () <CLLocationManagerDelegate, UITextFieldDelegate,
                                    UIScrollViewDelegate>
@property (nonatomic, copy) NSArray<NSURL *> *urls;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;

@property (nonatomic, strong) UISegmentedControl *modelControl;
@property (nonatomic, strong) UILabel *modeNote;
@property (nonatomic, strong) UILabel *deviceLabel;
@property (nonatomic, strong) UISwitch *deviceSwitch;
@property (nonatomic, strong) UISegmentedControl *timeControl;
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, strong) UISegmentedControl *locationControl;
@property (nonatomic, strong) UISegmentedControl *radiusControl;
@property (nonatomic, strong) UITextField *radiusField;
@property (nonatomic, strong) UILabel *locationLabel;
@property (nonatomic, strong) UISegmentedControl *formatControl;
@property (nonatomic, strong) UISwitch *nameSwitch;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) UIScrollView *previewScroll;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) UILabel *previewHint;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) CLLocation *batchLocation;
@property (nonatomic, strong) UIButton *rerollButton;
@property (nonatomic, strong) CLLocationManager *manager;
@property (nonatomic, strong) CLLocation *location;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL locating;
@end

static NSString *JXHashedName(NSURL *url, NSString *ext)
{
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (data.length == 0) return [NSString stringWithFormat:@"IMG_jexi.%@", ext];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithString:@"IMG_"];
    for (int i = 0; i < 4; i++) [hex appendFormat:@"%02X", digest[i]];
    return [NSString stringWithFormat:@"%@.%@", hex, ext];
}

@implementation JXMetaViewController

- (instancetype)initWithFileURLs:(NSArray<NSURL *> *)urls
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _urls = [urls copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"超分";
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1];

    self.scroll = [UIScrollView new];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scroll];

    self.stack = [UIStackView new];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12;
    self.stack.layoutMargins = UIEdgeInsetsMake(16, 20, 28, 20);
    self.stack.layoutMarginsRelativeArrangement = YES;
    [self.scroll addSubview:self.stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor],
    ]];

    [self buildUI];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - keyboard

- (UITextField *)activeTextField
{
    if (self.nameField.isFirstResponder) return self.nameField;
    if (self.radiusField.isFirstResponder) return self.radiusField;
    return nil;
}

- (void)keyboardWillChange:(NSNotification *)notification
{
    CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect frameInView = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frameInView));
    // 收起键盘时这个通知也会来一帧，交给 keyboardWillHide 处理
    if (overlap <= 0.5) return;
    self.scroll.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.scroll.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, overlap, 0);
    [self scrollActiveFieldIntoView];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf scrollActiveFieldIntoView];
    });
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    // 收起后留出刚好够当前偏移的底部内边距，否则滚动偏移被夹回去，画面整体上移
    UIScrollView *scrollView = self.scroll;
    CGFloat offset = scrollView.contentOffset.y;
    CGFloat needed = MAX(0.0, offset + scrollView.bounds.size.height - scrollView.contentSize.height);
    scrollView.contentInset = UIEdgeInsetsMake(0, 0, needed, 0);
    scrollView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, needed, 0);
}

- (void)scrollActiveFieldIntoView
{
    UITextField *field = [self activeTextField];
    if (!field) return;
    CGRect rect = [field convertRect:field.bounds toView:self.scroll];
    rect = CGRectInset(rect, 0, -28);
    [self.scroll scrollRectToVisible:rect animated:YES];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

#pragma mark - UI helpers

- (UILabel *)caption:(NSString *)text
{
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    l.numberOfLines = 0;
    return l;
}

- (UILabel *)sectionTitle:(NSString *)text
{
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithWhite:0.66 alpha:1];
    return l;
}

- (UISegmentedControl *)segments:(NSArray<NSString *> *)items selected:(NSInteger)index
{
    UISegmentedControl *c = [[UISegmentedControl alloc] initWithItems:items];
    c.selectedSegmentIndex = index;
    c.translatesAutoresizingMaskIntoConstraints = NO;
    return c;
}

- (UIButton *)pill:(NSString *)title filled:(BOOL)filled
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

- (void)buildUI
{
    UILabel *head = [UILabel new];
    head.text = [NSString stringWithFormat:@"已选 %lu 张", (unsigned long)self.urls.count];
    head.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    head.textColor = [UIColor whiteColor];
    [self.stack addArrangedSubview:head];

    // paged preview: swipe to look through the batch, long-press to drop one
    self.previewScroll = [UIScrollView new];
    self.previewScroll.pagingEnabled = YES;
    self.previewScroll.showsHorizontalScrollIndicator = NO;
    self.previewScroll.layer.cornerRadius = 16;
    self.previewScroll.clipsToBounds = YES;
    self.previewScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewScroll.delegate = self;
    [self.stack addArrangedSubview:self.previewScroll];
    [self.previewScroll.heightAnchor constraintEqualToConstant:240].active = YES;
    [self layoutPreviewPages];
    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(deleteCurrentPhoto:)];
    [self.previewScroll addGestureRecognizer:hold];

    self.pageControl = [UIPageControl new];
    self.pageControl.numberOfPages = self.urls.count;
    self.pageControl.currentPage = 0;
    self.pageControl.currentPageIndicatorTintColor = [UIColor colorWithRed:0.29 green:0.67 blue:1 alpha:1];
    [self.pageControl addTarget:self action:@selector(pageChanged) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:self.pageControl];

    self.previewHint = [self caption:[NSString stringWithFormat:
        @"已选 %lu 张，左右滑动查看，长按可删除。", (unsigned long)self.urls.count]];
    [self.stack addArrangedSubview:self.previewHint];
    [self.stack addArrangedSubview:[self caption:@"原图不动，结果另存为新照片。"]];

    // 模型
    [self.stack addArrangedSubview:[self sectionTitle:@"模型"]];
    self.modelControl = [self segments:@[ @"Real-ESRGAN 4×", @"快速" ] selected:0];
    [self.stack addArrangedSubview:self.modelControl];
    self.modeNote = [self caption:@"输出长边上限 4096；结果按下面的设置写入元数据。"];
    [self.stack addArrangedSubview:self.modeNote];

    // 设备信息
    [self.stack addArrangedSubview:[self sectionTitle:@"写入这台设备的真实数据"]];
    self.deviceLabel = [self caption:[NSString stringWithFormat:@"%@ · %@",
                                       [EXDevice marketingName], [EXDevice systemDescription]]];
    self.deviceLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    [self.stack addArrangedSubview:self.deviceLabel];
    self.deviceSwitch = [UISwitch new];
    self.deviceSwitch.on = YES;
    [self.stack addArrangedSubview:[self labelledRow:@"机型、系统、镜头与曝光" control:self.deviceSwitch]];
    [self.stack addArrangedSubview:[self caption:@"镜头与曝光参数在区间内随机，每张都不一样"]];

    // 时间
    [self.stack addArrangedSubview:[self sectionTitle:@"时间"]];
    self.timeControl = [self segments:@[ @"不改", @"现在", @"指定" ] selected:1];
    [self.stack addArrangedSubview:self.timeControl];
    self.datePicker = [UIDatePicker new];
    self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    self.datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    self.datePicker.hidden = YES;
    [self.stack addArrangedSubview:self.datePicker];
    [self.timeControl addTarget:self action:@selector(timeModeChanged) forControlEvents:UIControlEventValueChanged];

    // 位置
    [self.stack addArrangedSubview:[self sectionTitle:@"位置"]];
    self.locationControl = [self segments:@[ @"不改（抹掉）", @"当前定位", @"附近随机" ] selected:1];
    [self.stack addArrangedSubview:self.locationControl];
    self.radiusControl = [self segments:@[ @"100 m", @"500 m", @"1 km", @"自定义" ] selected:1];
    self.radiusControl.hidden = YES;
    [self.radiusControl addTarget:self action:@selector(radiusChanged) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:self.radiusControl];

    self.radiusField = [UITextField new];
    self.radiusField.placeholder = @"半径（米），留空按 500";
    self.radiusField.keyboardType = UIKeyboardTypeNumberPad;
    self.radiusField.textColor = [UIColor whiteColor];
    self.radiusField.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    self.radiusField.borderStyle = UITextBorderStyleRoundedRect;
    self.radiusField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.radiusField.hidden = YES;
    self.radiusField.delegate = self;
    self.radiusField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.radiusField.heightAnchor constraintEqualToConstant:40].active = YES;
    [self.radiusField addTarget:self action:@selector(radiusTextChanged) forControlEvents:UIControlEventEditingChanged];
    [self.stack addArrangedSubview:self.radiusField];
    self.locationLabel = [self caption:@"点「当前定位」授权后读取一次位置"];
    [self.stack addArrangedSubview:self.locationLabel];
    self.rerollButton = [self pill:@"换一个位置" filled:NO];
    self.rerollButton.hidden = YES;
    [self.rerollButton addTarget:self action:@selector(rerollLocation) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.rerollButton];
    [self.locationControl addTarget:self action:@selector(locationModeChanged) forControlEvents:UIControlEventValueChanged];

    // 原图信息
    [self.stack addArrangedSubview:[self sectionTitle:@"原图信息"]];
    self.summaryLabel = [self caption:[self summaryText]];
    [self.stack addArrangedSubview:self.summaryLabel];

    // 输出格式
    [self.stack addArrangedSubview:[self sectionTitle:@"输出格式"]];
    self.formatControl = [self segments:@[ @"原格式", @"JPEG", @"HEIF" ] selected:0];
    [self.stack addArrangedSubview:self.formatControl];
    [self.stack addArrangedSubview:[self caption:@"HEIF 体积更小；换格式会重新编码"]];

    // 文件名
    [self.stack addArrangedSubview:[self sectionTitle:@"文件名"]];
    self.nameSwitch = [UISwitch new];
    self.nameSwitch.on = YES;              // 自定义文件名默认打开
    [self.stack addArrangedSubview:[self labelledRow:@"自定义文件名" control:self.nameSwitch]];
    self.nameField = [UITextField new];
    self.nameField.placeholder = @"留空则 IMG_ + 图片 hash";
    self.nameField.textColor = [UIColor whiteColor];
    self.nameField.font = [UIFont systemFontOfSize:15];
    self.nameField.borderStyle = UITextBorderStyleRoundedRect;
    self.nameField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.nameField.delegate = self;
    self.nameField.hidden = NO;
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nameField.heightAnchor constraintEqualToConstant:40].active = YES;
    [self.nameField addTarget:self action:@selector(dismissKeyboard) forControlEvents:UIControlEventEditingDidEndOnExit];
    [self.stack addArrangedSubview:self.nameField];
    [self.nameSwitch addTarget:self action:@selector(nameSwitchChanged) forControlEvents:UIControlEventValueChanged];

    // 运行
    self.runButton = [self pill:@"超分并保存到相册" filled:YES];
    [self.runButton addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.runButton];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.hidden = YES;
    self.progressView.progressTintColor = [UIColor colorWithRed:0.35 green:0.78 blue:1 alpha:1];
    [self.stack addArrangedSubview:self.progressView];

    self.statusLabel = [self caption:@""];
    [self.stack addArrangedSubview:self.statusLabel];

    if ([CLLocationManager locationServicesEnabled] == NO) {
        self.locationLabel.text = @"系统定位服务已关闭";
    }
}

- (UIView *)labelledRow:(NSString *)title control:(UIView *)control
{
    UILabel *l = [UILabel new];
    l.text = title;
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ l, control ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionEqualSpacing;
    return row;
}

- (void)layoutPreviewPages
{
    for (UIView *v in [self.previewScroll.subviews copy]) [v removeFromSuperview];
    CGRect bounds = CGRectMake(0, 0, self.view.bounds.size.width - 40, 240);
    for (NSUInteger i = 0; i < self.urls.count; i++) {
        UIImageView *iv = [UIImageView new];
        iv.image = [UIImage imageWithContentsOfFile:self.urls[i].path];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.frame = CGRectOffset(bounds, bounds.size.width * i, 0);
        [self.previewScroll addSubview:iv];
    }
    self.previewScroll.contentSize = CGSizeMake(bounds.size.width * self.urls.count, 240);
    self.pageControl.numberOfPages = self.urls.count;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = self.previewScroll.bounds.size.width;
    if (width < 1) return;
    for (NSUInteger i = 0; i < self.previewScroll.subviews.count; i++) {
        UIView *v = self.previewScroll.subviews[i];
        v.frame = CGRectMake(width * i, 0, width, self.previewScroll.bounds.size.height);
    }
    self.previewScroll.contentSize = CGSizeMake(width * self.urls.count,
                                                self.previewScroll.bounds.size.height);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat width = scrollView.bounds.size.width;
    if (width < 1) return;
    NSInteger page = (NSInteger)lround(scrollView.contentOffset.x / width);
    self.pageControl.currentPage = MAX(0, MIN(page, (NSInteger)self.urls.count - 1));
}

- (void)pageChanged
{
    CGFloat width = self.previewScroll.bounds.size.width;
    [self.previewScroll setContentOffset:CGPointMake(width * self.pageControl.currentPage, 0)
                                animated:YES];
}

- (void)deleteCurrentPhoto:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    if (self.urls.count == 0) return;
    NSInteger index = self.pageControl.currentPage;
    if (index < 0 || index >= (NSInteger)self.urls.count) return;
    NSMutableArray *remaining = [self.urls mutableCopy];
    [remaining removeObjectAtIndex:index];
    self.urls = remaining;
    [self layoutPreviewPages];
    self.previewHint.text = self.urls.count
        ? [NSString stringWithFormat:@"已删除，剩 %lu 张。左右滑动查看，长按可删除。",
                                     (unsigned long)self.urls.count]
        : @"照片已全部移除，返回上一页重新选。";
    self.runButton.enabled = self.urls.count > 0;
}

#pragma mark - options

- (void)timeModeChanged
{
    self.datePicker.hidden = (self.timeControl.selectedSegmentIndex != 2);
}

- (void)nameSwitchChanged
{
    self.nameField.hidden = !self.nameSwitch.isOn;
}

- (void)dismissKeyboard
{
    [self.nameField resignFirstResponder];
}

- (NSString *)summaryText
{
    NSURL *first = self.urls.firstObject;
    NSData *data = first ? [NSData dataWithContentsOfURL:first options:0 error:NULL] : nil;
    if (!data) return @"读不到原图信息";
    NSDictionary *properties = JXImagePropertiesFromData(data);
    NSArray<NSDictionary *> *rows = [EXMetadata summaryRowsFromProperties:properties];
    if (rows.count == 0) return @"这张照片没有可读的拍摄信息";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        if (parts.count >= 6) break;
        NSString *key = row[@"key"];
        NSString *value = row[@"value"];
        if (key.length && value.length) [parts addObject:[NSString stringWithFormat:@"%@ %@", key, value]];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (void)rerollLocation
{
    self.batchLocation = nil;
    (void)[self effectiveLocation];
}

- (void)locationModeChanged
{
    BOOL nearby = (self.locationControl.selectedSegmentIndex == 2);
    self.radiusControl.hidden = !nearby;
    self.rerollButton.hidden = !nearby;
    self.batchLocation = nil;
    if (self.locationControl.selectedSegmentIndex == 0) {
        self.locationLabel.text = @"不写入位置，并抹掉原照片里的 GPS";
        self.location = nil;
        return;
    }
    self.locationLabel.text = @"正在定位…";
    [self startLocating];
}

- (void)radiusChanged
{
    self.radiusField.hidden = (self.radiusControl.selectedSegmentIndex != 3);
    if (!self.radiusField.hidden) [self.radiusField becomeFirstResponder];
    self.batchLocation = nil;
    [self updateLocationLabel];
}

- (void)radiusTextChanged
{
    self.batchLocation = nil;
    [self updateLocationLabel];
}

- (void)startLocating
{
    if (!self.manager) {
        self.manager = [CLLocationManager new];
        self.manager.delegate = self;
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    }
    [self.manager requestWhenInUseAuthorization];
    [self.manager requestLocation];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    if (manager.authorizationStatus == kCLAuthorizationStatusAuthorizedWhenInUse ||
        manager.authorizationStatus == kCLAuthorizationStatusAuthorizedAlways) {
        [manager requestLocation];
    } else if (manager.authorizationStatus != kCLAuthorizationStatusNotDetermined) {
        self.locationLabel.text = @"未授权定位（在设置里允许后可写入真实位置）";
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *loc = locations.lastObject;
    if (!loc) return;
    self.location = loc;
    [self updateLocationLabel];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    self.locationLabel.text = [NSString stringWithFormat:@"定位失败：%@", error.localizedDescription];
}

- (void)updateLocationLabel
{
    if (!self.location) return;
    if (self.locationControl.selectedSegmentIndex == 2) {
        double radius = [self radiusMeters];
        self.locationLabel.text = [NSString stringWithFormat:@"附近随机：每批在 %.0f 米内取一个点", radius];
    } else {
        self.locationLabel.text = [NSString stringWithFormat:@"当前定位：%.6f, %.6f",
                                                             self.location.coordinate.latitude,
                                                             self.location.coordinate.longitude];
    }
}

- (double)radiusMeters
{
    switch (self.radiusControl.selectedSegmentIndex) {
        case 0: return 100;
        case 1: return 500;
        case 2: return 1000;
        default: {
            // 自定义：手输米数，留空或非法时按 500
            double typed = self.radiusField.text.doubleValue;
            if (!(typed > 0)) return 500;
            return MIN(MAX(typed, 10.0), 50000.0);
        }
    }
}

- (CLLocation *)effectiveLocation
{
    NSInteger mode = self.locationControl.selectedSegmentIndex;
    if (mode == 0) return nil;
    if (!self.location) return nil;
    if (mode == 1) return self.location;
    if (self.batchLocation) return self.batchLocation;
    // random point within the radius
    double radius = [self radiusMeters];
    double distance = radius * sqrt((double)arc4random() / (double)UINT32_MAX);
    double bearing = ((double)arc4random() / (double)UINT32_MAX) * 2.0 * M_PI;
    double lat = self.location.coordinate.latitude;
    double lon = self.location.coordinate.longitude;
    double dLat = (distance * cos(bearing)) / 111320.0;
    double dLon = (distance * sin(bearing)) / (111320.0 * cos(lat * M_PI / 180.0));
    CLLocation *point = [[CLLocation alloc] initWithLatitude:lat + dLat longitude:lon + dLon];
    self.batchLocation = point;
    self.locationLabel.text = [NSString stringWithFormat:@"本批位置：%.6f, %.6f（约 %.0f 米外）",
                                                         point.coordinate.latitude,
                                                         point.coordinate.longitude, distance];
    return point;
}

- (EXWriteOptions)writeOptions
{
    EXWriteOptions options = EXWriteNone;
    if (self.deviceSwitch.isOn) options |= EXWriteDevice;
    if (self.timeControl.selectedSegmentIndex != 0) options |= EXWriteTime;
    if (self.locationControl.selectedSegmentIndex != 0) options |= EXWriteLocation;
    return options;
}

- (EXOutputFormat)format
{
    switch (self.formatControl.selectedSegmentIndex) {
        case 1: return EXOutputFormatJPEG;
        case 2: return EXOutputFormatHEIF;
        default: return EXOutputFormatKeep;
    }
}

#pragma mark - run

- (void)runTapped
{
    if (self.running || self.urls.count == 0) return;
    if (self.locationControl.selectedSegmentIndex != 0 && !self.location) {
        [self alert:@"还没有定位" message:@"先允许定位，或者把位置改成「不改」。"];
        return;
    }
    [self runAI];
}

#pragma mark - AI 超分

- (void)runAI
{
    NSArray<NSURL *> *urls = self.urls;
    if (urls.count == 0) return;
    self.running = YES;
    self.runButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressView.progress = 0;
    self.statusLabel.text = @"加载模型…";

    JXModelKind kind = (self.modelControl.selectedSegmentIndex == 0) ? JXModelKindRealESRGAN
                                                                   : JXModelKindFastSRGAN;
    EXWriteOptions options = [self writeOptions];
    EXOutputFormat format = [self format];
    CLLocation *location = [self effectiveLocation];
    NSDate *baseDate = self.timeControl.selectedSegmentIndex == 2 ? self.datePicker.date
                                                                  : [NSDate date];
    BOOL customName = self.nameSwitch.isOn;
    NSString *baseName = [self.nameField.text stringByTrimmingCharactersInSet:
                                                    [NSCharacterSet whitespaceCharacterSet]];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        NSError *error = nil;
        JXSRModel *model = [[JXModelCatalog shared] modelForKind:kind error:&error];
        if (!model) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishAIWithError:error saved:NO];
            });
            return;
        }
        NSUInteger total = urls.count;
        NSUInteger saved = 0, failed = 0;
        UIImage *lastImage = nil, *lastOriginal = nil;
        NSDictionary *lastProperties = nil;
        BOOL lastPrescaled = NO;

        for (NSUInteger i = 0; i < total; i++) {
            @autoreleasepool {
                NSURL *src = urls[i];
                NSData *data = [NSData dataWithContentsOfURL:src
                                                     options:NSDataReadingMappedIfSafe
                                                       error:NULL];
                if (data.length == 0) {
                    failed++;
                    continue;
                }
                UIImage *original = [UIImage imageWithData:data scale:1.0];
                CVPixelBufferRef input = JXCreatePixelBufferFromImageData(data, NULL, &error);
                if (!input) {
                    failed++;
                    continue;
                }
                JXUpscaler *upscaler = [[JXUpscaler alloc] initWithModel:model];
                upscaler.maxOutputEdge = 4096;
                NSUInteger index = i;
                CVPixelBufferRef output = [upscaler upscalePixelBuffer:input
                    progress:^(NSInteger done, NSInteger tileTotal, double perTile) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            double frac = ((double)index + (double)done / (double)MAX(tileTotal, 1))
                                          / (double)total;
                            self.progressView.progress = (float)frac;
                            self.statusLabel.text = (total > 1)
                                ? [NSString stringWithFormat:@"第 %lu/%lu 张 · 第 %ld/%ld 块",
                                                             (unsigned long)(index + 1),
                                                             (unsigned long)total,
                                                             (long)done, (long)tileTotal]
                                : [NSString stringWithFormat:@"第 %ld/%ld 块 · 预计还剩 %.0f 秒",
                                                             (long)done, (long)tileTotal,
                                                             (tileTotal - done) * perTile];
                        });
                    }
                    canceled:^BOOL { return NO; }
                    error:&error];
                CVPixelBufferRelease(input);
                if (!output) {
                    failed++;
                    continue;
                }
                UIImage *result = JXImageFromPixelBuffer(output);
                BOOL prescaled = upscaler.didPrescale;
                CVPixelBufferRelease(output);
                if (!result) {
                    failed++;
                    continue;
                }

                NSString *ext = format == EXOutputFormatHEIF ? @"heic"
                              : (format == EXOutputFormatJPEG ? @"jpg" : src.pathExtension);
                NSString *filename = nil;
                if (customName && baseName.length) {
                    filename = (total > 1)
                        ? [NSString stringWithFormat:@"%@-%lu.%@", baseName,
                                                     (unsigned long)(index + 1), ext]
                        : [NSString stringWithFormat:@"%@.%@", baseName, ext];
                } else {
                    filename = JXHashedName(src, ext);
                }

                // 像素先落成临时文件，再让 EXMetadata 按选项写元数据与格式
                NSString *token = [[NSUUID UUID] UUIDString];
                NSString *tmp = NSTemporaryDirectory();
                NSURL *raw = [NSURL fileURLWithPath:
                    [tmp stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"ai-%@.jpg", token]]];
                NSURL *final = [NSURL fileURLWithPath:
                    [tmp stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"out-%@.%@", token, ext]]];
                NSDate *date = [baseDate dateByAddingTimeInterval:(NSTimeInterval)index];
                BOOL wrote = [UIImageJPEGRepresentation(result, 0.95) writeToURL:raw
                                                                         options:NSDataWritingAtomic
                                                                           error:NULL];
                BOOL ok = wrote && [EXMetadata writeSourceURL:raw
                                                toDestination:final
                                                      options:options
                                                     location:location
                                                         date:date
                                                       format:format
                                                        error:&error];
                [[NSFileManager defaultManager] removeItemAtURL:raw error:NULL];
                if (!ok) {
                    [[NSFileManager defaultManager] removeItemAtURL:final error:NULL];
                    failed++;
                    continue;
                }
                NSData *finalData = [NSData dataWithContentsOfURL:final];
                UIImage *finalImage = finalData ? [UIImage imageWithData:finalData scale:1.0] : nil;
                if (!finalImage) {
                    [[NSFileManager defaultManager] removeItemAtURL:final error:NULL];
                    failed++;
                    continue;
                }
                dispatch_semaphore_t gate = dispatch_semaphore_create(0);
                __block BOOL success = NO;
                JXSaveFileToPhotoLibrary(final, filename, ^(BOOL ok2, NSError *saveError) {
                    success = ok2;
                    dispatch_semaphore_signal(gate);
                });
                dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));
                [[NSFileManager defaultManager] removeItemAtURL:final error:NULL];
                if (success) {
                    saved++;
                    lastImage = finalImage;
                    lastOriginal = original;
                    lastProperties = JXImagePropertiesFromData(finalData);
                    lastPrescaled = prescaled;
                } else {
                    failed++;
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            self.running = NO;
            self.runButton.enabled = self.urls.count > 0;
            self.progressView.hidden = YES;
            if (failed == 0) {
                self.statusLabel.text = (saved == 1)
                    ? @"已保存 1 张新照片"
                    : [NSString stringWithFormat:@"已保存 %lu 张新照片", (unsigned long)saved];
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"完成 %lu 张，失败 %lu 张",
                                                                   (unsigned long)saved,
                                                                   (unsigned long)failed];
            }
            if (saved == 1 && lastImage) {
                JXPreviewViewController *vc =
                    [[JXPreviewViewController alloc] initWithResultImage:lastImage
                                                           originalImage:lastOriginal
                                                              properties:lastProperties
                                                               prescaled:lastPrescaled
                                                                   saved:YES];
                [self.navigationController pushViewController:vc animated:YES];
            } else if (saved > 1) {
                [self alert:@"完成" message:[NSString stringWithFormat:
                    @"已保存 %lu 张新照片到相册，原图未改动。", (unsigned long)saved]];
            }
        });
    });
}

- (void)finishAIWithError:(NSError *)error saved:(BOOL)saved
{
    self.running = NO;
    self.runButton.enabled = self.urls.count > 0;
    self.progressView.hidden = YES;
    self.statusLabel.text = @"";
    [self alert:@"超分失败" message:error.localizedDescription ?: @"未知错误"];
}

- (void)alert:(NSString *)title message:(NSString *)message
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
