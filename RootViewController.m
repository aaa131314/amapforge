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
@property (nonatomic, strong) UIButton *stopBtn;
@property (nonatomic, strong) UITextView *logView;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设备身份";
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.059 blue:0.078 alpha:1.0];
    [self buildUI];
    [self refresh];
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
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.backgroundColor = c;
    b.layer.cornerRadius = 11;
    b.frame = CGRectMake(16, 0, self.view.bounds.size.width - 32, h);
    return b;
}

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width - 32;
    CGFloat y = 8;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, y + 8, w, 158)];
    card.backgroundColor = [UIColor colorWithRed:0.082 green:0.106 blue:0.137 alpha:1.0];
    card.layer.cornerRadius = 14;
    [self.view addSubview:card];

    UILabel *t1 = [self smallLabel:@"当前状态"];
    t1.frame = CGRectMake(16, 12, w - 32, 16);
    [card addSubview:t1];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 30, w - 32, 26)];
    self.statusLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.text = @"读取中…";
    [card addSubview:self.statusLabel];

    UILabel *t2 = [self smallLabel:@"设备 ID (UTDID)"];
    t2.frame = CGRectMake(16, 60, w - 32, 16);
    [card addSubview:t2];

    self.idLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 77, w - 32, 22)];
    self.idLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
    self.idLabel.textColor = [UIColor colorWithRed:0.18 green:0.51 blue:0.97 alpha:1.0];
    self.idLabel.adjustsFontSizeToFitWidth = YES;
    self.idLabel.text = @"—";
    [card addSubview:self.idLabel];

    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 103, w - 32, 16)];
    self.countLabel.font = [UIFont systemFontOfSize:11];
    self.countLabel.textColor = [UIColor grayColor];
    self.countLabel.text = @"已服务 0 次读取";
    [card addSubview:self.countLabel];

    self.sizeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 123, w - 32, 16)];
    self.sizeLabel.font = [UIFont systemFontOfSize:11];
    self.sizeLabel.textColor = [UIColor grayColor];
    self.sizeLabel.text = @"数据体积：读取中…";
    [card addSubview:self.sizeLabel];

    y = CGRectGetMaxY(card.frame);

    self.forgeBtn = [self btn:@"① 换一个新设备身份" color:[UIColor colorWithRed:0.18 green:0.51 blue:0.97 alpha:1.0] h:50];
    self.forgeBtn.frame = CGRectMake(16, y + 12, w, 50);
    [self.forgeBtn addTarget:self action:@selector(onForge) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.forgeBtn];

    self.wipeBtn = [self btn:@"② 清理数据（身份+缓存+登录）" color:[UIColor colorWithRed:0.72 green:0.45 blue:0.10 alpha:1.0] h:44];
    self.wipeBtn.frame = CGRectMake(16, y + 70, w, 44);
    [self.wipeBtn addTarget:self action:@selector(onWipe) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.wipeBtn];

    self.deepWipeBtn = [self btn:@"③ 深度清理（含离线地图）" color:[UIColor colorWithRed:0.55 green:0.22 blue:0.22 alpha:1.0] h:40];
    self.deepWipeBtn.frame = CGRectMake(16, y + 120, w, 40);
    [self.deepWipeBtn addTarget:self action:@selector(onDeepWipe) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.deepWipeBtn];

    self.stopBtn = [self btn:@"停止 / 恢复真实身份" color:[UIColor colorWithRed:0.25 green:0.27 blue:0.31 alpha:1.0] h:38];
    self.stopBtn.frame = CGRectMake(16, y + 166, w, 38);
    [self.stopBtn addTarget:self action:@selector(onStop) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopBtn];

    CGFloat logY = y + 212;
    CGFloat logH = self.view.bounds.size.height - logY - 16;
    if (logH < 60) logH = 60;
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(16, logY, w, logH)];
    self.logView.backgroundColor = [UIColor colorWithRed:0.055 green:0.071 blue:0.094 alpha:1.0];
    self.logView.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.logView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"就绪";
    [self.view addSubview:self.logView];
}

- (void)refresh {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        BOOL running = [ForgeRunner isRunning];
        NSString *idv = running ? [ForgeRunner currentID] : nil;
        NSInteger served = [ForgeRunner servedCount];
        NSString *sz = [ForgeRunner dataSize];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = running ? @"🟢 正在伪造设备身份" : @"⚪️ 使用真实设备身份";
            self.statusLabel.textColor = running
                ? [UIColor colorWithRed:0.25 green:0.73 blue:0.31 alpha:1.0]
                : [UIColor colorWithWhite:0.6 alpha:1.0];
            self.idLabel.text = running ? (idv ?: @"—") : @"（真实 ID，未伪造）";
            self.countLabel.text = [NSString stringWithFormat:@"已服务 %ld 次读取", (long)served];
            NSRange r = [sz rangeOfString:@"data: "];
            if (r.location != NSNotFound) {
                NSString *tail = [sz substringFromIndex:r.location + 6];
                NSRange nl = [tail rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
                if (nl.location != NSNotFound) tail = [tail substringToIndex:nl.location];
                self.sizeLabel.text = [NSString stringWithFormat:@"数据体积：%@", tail];
            } else {
                self.sizeLabel.text = @"数据体积：不可用";
            }
        });
    });
}

- (void)setBusy:(BOOL)b {
    self.forgeBtn.enabled = !b;
    self.wipeBtn.enabled = !b;
    self.deepWipeBtn.enabled = !b;
    self.stopBtn.enabled = !b;
    self.forgeBtn.alpha = b ? 0.5 : 1.0;
}

- (void)onForge {
    [self setBusy:YES];
    self.logView.text = @"正在换新身份（会重启高德）…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *o = [ForgeRunner startWithID:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = o;
            [self setBusy:NO];
            [self refresh];
        });
    });
}

- (void)onWipe {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"清理数据"
                         message:@"将删除：设备标识(diu/adiu)、缓存、设置、登录状态、反馈记录。\n高德下次启动会重新生成。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *x) { [self runWipe:NO]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)onDeepWipe {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"深度清理"
                         message:@"除标准清理外，还会删除离线地图、收藏、历史记录、全部文档。\n体积可能很大，且需要重新下载地图。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"深度清理" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *x) { [self runWipe:YES]; }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runWipe:(BOOL)deep {
    [self setBusy:YES];
    self.logView.text = deep ? @"正在深度清理…" : @"正在清理…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *o = [ForgeRunner wipeData:deep];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = o;
            [self setBusy:NO];
            [self refresh];
        });
    });
}

- (void)onStop {
    [self setBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *o = [ForgeRunner stop];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = o;
            [self setBusy:NO];
            [self refresh];
        });
    });
}

@end
