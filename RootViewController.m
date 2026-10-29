#import "RootViewController.h"
#import "ForgeRunner.h"

@interface RootViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *idLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *forgeBtn;
@property (nonatomic, strong) UIButton *wipeBtn;
@property (nonatomic, strong) UIButton *deepWipeBtn;
@property (nonatomic, strong) UIButton *sizeBtn;
@property (nonatomic, strong) UIButton *stopBtn;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) BOOL busy;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设备身份";
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.059 blue:0.078 alpha:1.0];
    [self buildUI];
    // 只查轻量状态（HTTP GET，毫秒级）
    [self refreshLight];
}

- (UILabel *)smallLabel:(NSString *)t {
    UILabel *l = [[UILabel alloc] init];
    l.text = t;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    return l;
}

- (UIButton *)btn:(NSString *)title color:(UIColor *)c h:(CGFloat)h {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.backgroundColor = c;
    b.layer.cornerRadius = 10;
    b.frame = CGRectMake(14, 0, self.view.bounds.size.width - 28, h);
    return b;
}

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width - 28;
    CGFloat y = 6;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(14, y + 6, w, 152)];
    card.backgroundColor = [UIColor colorWithRed:0.082 green:0.106 blue:0.137 alpha:1.0];
    card.layer.cornerRadius = 14;
    [self.view addSubview:card];

    UILabel *t1 = [self smallLabel:@"当前状态"];
    t1.frame = CGRectMake(14, 10, w - 28, 15);
    [card addSubview:t1];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 26, w - 28, 24)];
    self.statusLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.text = @"读取中…";
    [card addSubview:self.statusLabel];

    UILabel *t2 = [self smallLabel:@"设备 ID (UTDID)"];
    t2.frame = CGRectMake(14, 54, w - 28, 15);
    [card addSubview:t2];

    self.idLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 70, w - 28, 20)];
    self.idLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.idLabel.textColor = [UIColor colorWithRed:0.18 green:0.51 blue:0.97 alpha:1.0];
    self.idLabel.adjustsFontSizeToFitWidth = YES;
    self.idLabel.text = @"—";
    [card addSubview:self.idLabel];

    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 94, w - 28, 15)];
    self.countLabel.font = [UIFont systemFontOfSize:10];
    self.countLabel.textColor = [UIColor grayColor];
    self.countLabel.text = @"已服务 0 次读取";
    [card addSubview:self.countLabel];

    self.sizeLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 113, w - 28, 15)];
    self.sizeLabel.font = [UIFont systemFontOfSize:10];
    self.sizeLabel.textColor = [UIColor grayColor];
    self.sizeLabel.text = @"数据体积：点「查体积」";
    [card addSubview:self.sizeLabel];

    UIButton *refBtn = [self btn:@"刷新状态" color:[UIColor colorWithRed:0.20 green:0.22 blue:0.26 alpha:1.0] h:30];
    refBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    refBtn.frame = CGRectMake(w - 90 + 14, 122, 90, 24);
    refBtn.layer.cornerRadius = 8;
    [refBtn addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:refBtn];

    y = CGRectGetMaxY(card.frame);

    self.forgeBtn = [self btn:@"① 换一个新设备身份" color:[UIColor colorWithRed:0.18 green:0.51 blue:0.97 alpha:1.0] h:46];
    self.forgeBtn.frame = CGRectMake(14, y + 10, w, 46);
    [self.forgeBtn addTarget:self action:@selector(onForge) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.forgeBtn];

    self.wipeBtn = [self btn:@"② 清理数据（身份+缓存+登录）" color:[UIColor colorWithRed:0.72 green:0.45 blue:0.10 alpha:1.0] h:40];
    self.wipeBtn.frame = CGRectMake(14, y + 62, w, 40);
    [self.wipeBtn addTarget:self action:@selector(onWipe) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.wipeBtn];

    self.deepWipeBtn = [self btn:@"③ 深度清理（含离线地图）" color:[UIColor colorWithRed:0.55 green:0.22 blue:0.22 alpha:1.0] h:36];
    self.deepWipeBtn.frame = CGRectMake(14, y + 108, w, 36);
    [self.deepWipeBtn addTarget:self action:@selector(onDeepWipe) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.deepWipeBtn];

    self.sizeBtn = [self btn:@"查体积" color:[UIColor colorWithRed:0.18 green:0.34 blue:0.42 alpha:1.0] h:32];
    self.sizeBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.sizeBtn.frame = CGRectMake(14, y + 150, w, 32);
    [self.sizeBtn addTarget:self action:@selector(onSize) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sizeBtn];

    self.stopBtn = [self btn:@"停止 / 恢复真实身份" color:[UIColor colorWithRed:0.25 green:0.27 blue:0.31 alpha:1.0] h:32];
    self.stopBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.stopBtn.frame = CGRectMake(14, y + 188, w, 32);
    [self.stopBtn addTarget:self action:@selector(onStop) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopBtn];

    CGFloat logY = y + 228;
    CGFloat logH = self.view.bounds.size.height - logY - 12;
    if (logH < 50) logH = 50;
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(14, logY, w, logH)];
    self.logView.backgroundColor = [UIColor colorWithRed:0.055 green:0.071 blue:0.094 alpha:1.0];
    self.logView.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.logView.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"就绪";
    [self.view addSubview:self.logView];
}

/// 轻量刷新：一次 HTTP 请求拿全部状态（不再重复请求三次）
- (void)refreshLight {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *st = [ForgeRunner statusDict];
        BOOL running = [st[@"running"] boolValue];
        id idRaw = st[@"utdid"];
        NSString *idv = [idRaw isKindOfClass:[NSString class]] ? idRaw : nil;
        NSInteger served = [st[@"served"] respondsToSelector:@selector(integerValue)]
                            ? [st[@"served"] integerValue] : 0;
        BOOL reachable = [st[@"ok"] boolValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!reachable) {
                self.statusLabel.text = @"🔴 连不上电脑服务";
                self.statusLabel.textColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
                self.idLabel.text = @"检查 8050 服务和隧道";
                self.countLabel.text = @"";
                return;
            }
            self.statusLabel.text = running ? @"🟢 正在伪造设备身份" : @"⚪️ 使用真实设备身份";
            self.statusLabel.textColor = running
                ? [UIColor colorWithRed:0.25 green:0.73 blue:0.31 alpha:1.0]
                : [UIColor colorWithWhite:0.6 alpha:1.0];
            self.idLabel.text = running ? (idv ?: @"—") : @"（真实 ID，未伪造）";
            self.countLabel.text = [NSString stringWithFormat:@"已服务 %ld 次读取", (long)served];
        });
    });
}

- (void)setBusy:(BOOL)b {
    _busy = b;   // 必须写 ivar；self.busy = b 会递归调用本方法导致栈溢出
    self.forgeBtn.enabled = !b;
    self.wipeBtn.enabled = !b;
    self.deepWipeBtn.enabled = !b;
    self.sizeBtn.enabled = !b;
    self.stopBtn.enabled = !b;
    self.forgeBtn.alpha = b ? 0.5 : 1.0;
    self.wipeBtn.alpha = b ? 0.5 : 1.0;
    self.deepWipeBtn.alpha = b ? 0.5 : 1.0;
    self.sizeBtn.alpha = b ? 0.5 : 1.0;
    if (b) {
        self.statusLabel.text = @"⏳ 处理中…";
        self.statusLabel.textColor = [UIColor colorWithRed:0.83 green:0.60 blue:0.13 alpha:1.0];
    }
}

- (void)log:(NSString *)s {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = s ?: @"";
    });
}

- (void)onRefresh {
    [self refreshLight];
    self.logView.text = @"已刷新";
}

- (void)onForge {
    if (self.busy) return;
    [self setBusy:YES];
    [self log:@"正在换新身份（会重启高德，约 15-30 秒）…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *o = [ForgeRunner startWithID:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = o;
            [self setBusy:NO];
            [self refreshLight];
        });
    });
}

- (void)onWipe {
    if (self.busy) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"清理数据"
                         message:@"删除：设备标识(diu/adiu)、缓存、设置、登录状态、反馈记录。\n高德下次启动会重新生成。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *x) { [self runWipe:NO]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)onDeepWipe {
    if (self.busy) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"深度清理"
                         message:@"还会删除离线地图、收藏、历史、全部文档。\n可能几百 MB，需要重新下载地图。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"深度清理" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *x) { [self runWipe:YES]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runWipe:(BOOL)deep {
    [self setBusy:YES];
    [self log:deep ? @"正在深度清理（可能要 1-2 分钟）…" : @"正在清理（约 30-60 秒）…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *o = [ForgeRunner wipeData:deep];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = o;
            [self setBusy:NO];
            [self refreshLight];
        });
    });
}

- (void)onSize {
    if (self.busy) return;
    [self setBusy:YES];
    [self log:@"正在统计体积（会短暂启动高德，约 30-60 秒）…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *o = [ForgeRunner dataSize];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = o;
            NSRange r = [o rangeOfString:@"data: "];
            if (r.location != NSNotFound) {
                NSString *tail = [o substringFromIndex:r.location + 6];
                NSRange nl = [tail rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
                if (nl.location != NSNotFound) tail = [tail substringToIndex:nl.location];
                self.sizeLabel.text = [NSString stringWithFormat:@"数据体积：%@", tail];
            }
            [self setBusy:NO];
            [self refreshLight];
        });
    });
}

- (void)onStop {
    if (self.busy) return;
    [self setBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *o = [ForgeRunner stop];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = o;
            [self setBusy:NO];
            [self refreshLight];
        });
    });
}

@end
