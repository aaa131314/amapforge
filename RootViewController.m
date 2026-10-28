#import "RootViewController.h"
#import "ForgeRunner.h"

@interface RootViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *idLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIButton *forgeBtn;
@property (nonatomic, strong) UIButton *stopBtn;
@property (nonatomic, strong) UIButton *refreshBtn;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设备身份";
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.059 blue:0.078 alpha:1.0];

    [self buildUI];
    [self refresh];
}

- (void)buildUI {
    CGFloat y = 8;
    CGFloat w = self.view.bounds.size.width - 32;

    // 状态卡片
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, y + 8, w, 150)];
    card.backgroundColor = [UIColor colorWithRed:0.082 green:0.106 blue:0.137 alpha:1.0];
    card.layer.cornerRadius = 14;
    [self.view addSubview:card];

    UILabel *t1 = [self smallLabel:@"当前状态"];
    t1.frame = CGRectMake(16, 12, w - 32, 16);
    [card addSubview:t1];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 30, w - 32, 26)];
    self.statusLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.text = @"读取中…";
    [card addSubview:self.statusLabel];

    UILabel *t2 = [self smallLabel:@"设备 ID (UTDID)"];
    t2.frame = CGRectMake(16, 62, w - 32, 16);
    [card addSubview:t2];

    self.idLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 80, w - 32, 22)];
    self.idLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
    self.idLabel.textColor = [UIColor colorWithRed:0.18 green:0.51 blue:0.97 alpha:1.0];
    self.idLabel.text = @"—";
    self.idLabel.adjustsFontSizeToFitWidth = YES;
    [card addSubview:self.idLabel];

    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 108, w - 32, 18)];
    self.countLabel.font = [UIFont systemFontOfSize:12];
    self.countLabel.textColor = [UIColor grayColor];
    self.countLabel.text = @"已服务 0 次读取";
    [card addSubview:self.countLabel];

    y = CGRectGetMaxY(card.frame);

    // 主按钮
    self.forgeBtn = [self button:@"换一个新设备身份" color:[UIColor colorWithRed:0.18 green:0.51 blue:0.97 alpha:1.0]];
    self.forgeBtn.frame = CGRectMake(16, y + 16, w, 54);
    [self.forgeBtn addTarget:self action:@selector(onForge) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.forgeBtn];

    // 次级按钮
    self.stopBtn = [self button:@"停止（恢复真实身份）" color:[UIColor colorWithRed:0.25 green:0.27 blue:0.31 alpha:1.0]];
    self.stopBtn.frame = CGRectMake(16, y + 80, w, 46);
    [self.stopBtn addTarget:self action:@selector(onStop) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopBtn];

    self.refreshBtn = [self button:@"刷新状态" color:[UIColor colorWithRed:0.25 green:0.27 blue:0.31 alpha:1.0]];
    self.refreshBtn.frame = CGRectMake(16, y + 136, w, 46);
    [self.refreshBtn addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.refreshBtn];

    // 日志
    CGFloat logY = y + 194;
    CGFloat logH = self.view.bounds.size.height - logY - 20;
    if (logH < 80) logH = 80;
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(16, logY, w, logH)];
    self.logView.backgroundColor = [UIColor colorWithRed:0.055 green:0.071 blue:0.094 alpha:1.0];
    self.logView.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"就绪";
    [self.view addSubview:self.logView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.center = CGPointMake(self.view.bounds.size.width / 2, y + 43);
    [self.view addSubview:self.spinner];
}

- (UILabel *)smallLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    return l;
}

- (UIButton *)button:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    b.backgroundColor = color;
    b.layer.cornerRadius = 12;
    return b;
}

- (void)refresh {
    BOOL running = [ForgeRunner isRunning];
    self.statusLabel.text = running ? @"🟢 正在伪造设备身份" : @"⚪️ 使用真实设备身份";
    self.statusLabel.textColor = running
        ? [UIColor colorWithRed:0.25 green:0.73 blue:0.31 alpha:1.0]
        : [UIColor colorWithWhite:0.6 alpha:1.0];

    NSString *id_ = [ForgeRunner currentID];
    self.idLabel.text = running ? (id_ ?: @"—") : @"（真实 ID，未伪造）";
    self.countLabel.text = [NSString stringWithFormat:@"已服务 %ld 次读取", (long)[ForgeRunner servedCount]];
}

- (void)setBusy:(BOOL)busy {
    self.forgeBtn.enabled = !busy;
    self.stopBtn.enabled = !busy;
    self.refreshBtn.enabled = !busy;
    self.forgeBtn.alpha = busy ? 0.5 : 1.0;
    if (busy) [self.spinner startAnimating]; else [self.spinner stopAnimating];
}

- (void)onForge {
    [self setBusy:YES];
    self.logView.text = @"正在生成新身份并重启高德…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [ForgeRunner startWithID:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = out;
            [self setBusy:NO];
            [self refresh];
        });
    });
}

- (void)onStop {
    [self setBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [ForgeRunner stop];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = out;
            [self setBusy:NO];
            [self refresh];
        });
    });
}

- (void)onRefresh {
    [self refresh];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *out = [ForgeRunner status];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = out;
        });
    });
}

@end
