#import "RootViewController.h"
#import <WebKit/WebKit.h>
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
@property (nonatomic, strong) UILabel *serverLabel;
@property (nonatomic, assign) BOOL busy;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设备身份";
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.059 blue:0.078 alpha:1.0];
    [self buildUI];
    // 启动时不做任何 frida 调用（同步 API 可能长时间阻塞）
    // 用户点「刷新状态」才连 frida-server
    self.logView.text = [NSString stringWithFormat:
        @"就绪\n服务器：%@\n\n点「刷新状态」测试连通\n长按顶部状态文字可修改服务器地址",
        [ForgeRunner serverAddr]];
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
    self.statusLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(onConfigServer)];
    [self.statusLabel addGestureRecognizer:tap];
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
    {
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                                            initWithTarget:self action:@selector(onSpoofConfig)];
        lp.minimumPressDuration = 0.6;
        [self.forgeBtn addGestureRecognizer:lp];
    }
    [self.view addSubview:self.forgeBtn];

    UIButton *mapBtn = [self btn:@"🗺 地图选点（拖动/搜索）" color:[UIColor colorWithRed:0.10 green:0.55 blue:0.45 alpha:1.0] h:32];
    mapBtn.frame = CGRectMake(14, y + 186, w, 34);
    [mapBtn addTarget:self action:@selector(onMapPick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:mapBtn];

    UIButton *poiBtn = [self btn:@"📤 提交新增地点" color:[UIColor colorWithRed:0.62 green:0.24 blue:0.68 alpha:1.0] h:34];
    poiBtn.frame = CGRectMake(14, y + 226, w, 34);
    [poiBtn addTarget:self action:@selector(onSubmitPOI) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:poiBtn];
    
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
    self.stopBtn.frame = CGRectMake(14, y + 268, w, 32);
    [self.stopBtn addTarget:self action:@selector(onStop) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopBtn];

    CGFloat logY = y + 308;
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
        BOOL injected = [st[@"running"] boolValue];
        BOOL reachable = [st[@"ok"] boolValue];
        id idRaw = st[@"utdid"];
        NSString *idv = [idRaw isKindOfClass:[NSString class]] ? idRaw : nil;
        id procRaw = st[@"proc"];
        NSString *proc = [procRaw isKindOfClass:[NSString class]] ? procRaw : @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!reachable) {
                self.statusLabel.text = @"🔴 frida-server 不可达";
                self.statusLabel.textColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
                id tcpRaw = st[@"tcp"];
                self.idLabel.text = [tcpRaw isKindOfClass:[NSString class]] ? tcpRaw : @"TCP 探针失败";
                self.countLabel.text = @"检查 frida-server 是否在跑";
                return;
            }
            if (injected) {
                self.statusLabel.text = @"🟢 已伪装设备身份";
                self.statusLabel.textColor = [UIColor colorWithRed:0.25 green:0.73 blue:0.31 alpha:1.0];
                self.idLabel.text = idv ?: @"—";
                self.countLabel.text = proc.length
                    ? [NSString stringWithFormat:@"高德运行中 (%@)", proc]
                    : @"高德未启动";
            } else {
                self.statusLabel.text = @"⚪️ 使用真实设备身份";
                self.statusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
                self.idLabel.text = @"（真实 ID，未伪造）";
                self.countLabel.text = proc.length
                    ? [NSString stringWithFormat:@"高德运行中 (%@)", proc]
                    : @"点「① 换一个新设备身份」开始";
            }
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


- (void)onConfigServer {
    NSString *cur = [ForgeRunner serverAddr];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"服务器地址"
                         message:[NSString stringWithFormat:@"当前：\n%@\n\nCloudflare 隧道重启后 URL 会变，在这里更新。", cur]
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cur;
        tf.placeholder = @"https://xxx.trycloudflare.com";
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *x) {
        NSString *v = a.textFields.firstObject.text;
        v = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!v.length) return;
        if (![v hasSuffix:@"/"]) {
            // 去掉末尾斜杠
        } else {
            v = [v substringToIndex:v.length - 1];
        }
        if ([ForgeRunner setServerAddr:v]) {
            self.logView.text = [NSString stringWithFormat:@"服务器已更新：\n%@\n\n点「刷新状态」测试", v];
        } else {
            self.logView.text = @"地址无效，需要 http:// 或 https:// 开头";
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}


- (void)onSpoofConfig {
    NSDictionary *cur = [ForgeRunner spoofConfig];
    NSString *msg = [NSString stringWithFormat:
        @"机型: %@\niOS: %@\n纬度: %@\n经度: %@\n行政区: %@\n\n"
        @"输入城市名快速切换位置：\n北京 上海 广州 深圳 成都 杭州 武汉 西安 重庆 南京",
        cur[@"model"], cur[@"ios"], cur[@"lat"], cur[@"lng"], cur[@"adcode"]];

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"伪装参数"
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"城市名（留空保持不变）";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *x) {
        NSString *v = a.textFields.firstObject.text ?: @"";
        v = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self applyCity:v];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)applyCity:(NSString *)name {
    if (name.length == 0) {
        self.logView.text = @"未输入城市，保持当前配置";
        return;
    }
    NSDictionary *cities = @{
        @"北京": @[@"39.9042", @"116.4074", @"110000"],
        @"上海": @[@"31.2304", @"121.4737", @"310000"],
        @"广州": @[@"23.1291", @"113.2644", @"440100"],
        @"深圳": @[@"22.5431", @"114.0579", @"440300"],
        @"成都": @[@"30.5728", @"104.0668", @"510100"],
        @"杭州": @[@"30.2741", @"120.1551", @"330100"],
        @"武汉": @[@"30.5928", @"114.3055", @"420100"],
        @"西安": @[@"34.3416", @"108.9398", @"610100"],
        @"重庆": @[@"29.5630", @"106.5516", @"500000"],
        @"南京": @[@"32.0603", @"118.7969", @"320100"]
    };
    NSArray *c = cities[name];
    if (!c) {
        self.logView.text = [NSString stringWithFormat:@"未知城市: %@", name];
        return;
    }
    NSMutableDictionary *cfg = [[ForgeRunner spoofConfig] mutableCopy];
    cfg[@"lat"] = @([c[0] doubleValue]);
    cfg[@"lng"] = @([c[1] doubleValue]);
    cfg[@"adcode"] = c[2];
    [ForgeRunner setSpoofConfig:cfg];

    self.logView.text = [NSString stringWithFormat:
        @"已设置伪装位置\n城市: %@\n坐标: %@, %@\n行政区: %@\n\n下次换身份生效",
        name, c[0], c[1], c[2]];
}


#pragma mark - 地图选点

- (void)onMapPick {
    @try {
        NSString *base = [ForgeRunner serverAddr];
        NSURL *url = [NSURL URLWithString:base];
        if (!url) { self.logView.text = @"服务器地址无效"; return; }

        WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
        WKUserContentController *uc = [[WKUserContentController alloc] init];
        [uc addScriptMessageHandler:nil name:@"setpos"];   // 占位，真实处理用 delegate
        cfg.userContentController = uc;

        WKWebView *wv = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
        wv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        wv.navigationDelegate = (id<WKNavigationDelegate>)self;
        wv.tag = 9001;

        [self.view addSubview:wv];
        [wv loadRequest:[NSURLRequest requestWithURL:url]];

        // 关闭按钮
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(12, 44, 60, 36);
        close.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
        [close setTitle:@"关闭" forState:UIControlStateNormal];
        [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        close.layer.cornerRadius = 8;
        close.tag = 9002;
        [close addTarget:self action:@selector(closeMap) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:close];

        self.logView.text = [NSString stringWithFormat:
            @"地图已打开\n%@\n\n拖动地图或搜索地址，点「使用这个位置」", base];
    } @catch (NSException *e) {
        self.logView.text = [NSString stringWithFormat:@"地图打开失败: %@", e.reason];
    }
}

- (void)closeMap {
    [[self.view viewWithTag:9001] removeFromSuperview];
    [[self.view viewWithTag:9002] removeFromSuperview];
}

// 拦截 amapforge://setpos?lat=..&lng=..
- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)action
                    decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSURL *u = action.request.URL;
    if (u && [u.scheme isEqualToString:@"amapforge"]) {
        handler(WKNavigationActionPolicyCancel);
        NSString *qs = u.query ?: @"";
        NSMutableDictionary *kv = [NSMutableDictionary dictionary];
        for (NSString *pair in [qs componentsSeparatedByString:@"&"]) {
            NSArray *p2 = [pair componentsSeparatedByString:@"="];
            if (p2.count == 2) kv[p2[0]] = p2[1];
        }
        double lat = [kv[@"lat"] doubleValue];
        double lng = [kv[@"lng"] doubleValue];
        if (lat != 0 && lng != 0) {
            NSMutableDictionary *cfg = [[ForgeRunner spoofConfig] mutableCopy];
            cfg[@"lat"] = @(lat);
            cfg[@"lng"] = @(lng);
            [ForgeRunner setSpoofConfig:cfg];
            [self closeMap];
            self.logView.text = [NSString stringWithFormat:
                @"位置已设置\n坐标: %.6f, %.6f\n\n下次点「① 换一个新设备身份」生效",
                lat, lng];
        }
        return;
    }
    handler(WKNavigationActionPolicyAllow);
}

#pragma mark - 地图选点结束


#pragma mark - POI submit

- (void)onSubmitPOI {
    NSDictionary *cfg = [ForgeRunner spoofConfig];
    NSNumber *lat = cfg[@"lat"] ?: @39.9042;
    NSNumber *lng = cfg[@"lng"] ?: @116.4074;

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"新增地点"
                         message:[NSString stringWithFormat:
                                  @"坐标：%.6f, %.6f\n（用「🗺 地图选点」可改）",
                                  [lat doubleValue], [lng doubleValue]]
                  preferredStyle:UIAlertControllerStyleAlert];

    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"地点名称（必填）";
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"详细地址";
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"电话（可选）";
        tf.keyboardType = UIKeyboardTypePhonePad;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"营业时间（可选，如 09:00-22:00）";
    }];

    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"提交" style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *x) {
        NSString *name = a.textFields[0].text ?: @"";
        NSString *addr = a.textFields[1].text ?: @"";
        NSString *tel = a.textFields[2].text ?: @"";
        NSString *hours = a.textFields[3].text ?: @"";
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0) {
            self.logView.text = @"地点名称必填";
            return;
        }
        [self doSubmitPOI:name addr:addr tel:tel hours:hours lat:lat lng:lng];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)doSubmitPOI:(NSString *)name addr:(NSString *)addr
                tel:(NSString *)tel hours:(NSString *)hours
                lat:(NSNumber *)lat lng:(NSNumber *)lng {
    [self setBusy:YES];
    self.logView.text = [NSString stringWithFormat:
        @"正在提交…\n名称: %@\n地址: %@\n坐标: %.6f, %.6f",
        name, addr, [lat doubleValue], [lng doubleValue]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *r = [ForgeRunner submitPOI:@{
            @"name": name, @"addr": addr, @"tel": tel ?: @"",
            @"hours": hours ?: @"", @"lat": lat ?: @0,
            @"lng": lng ?: @0, @"cat": @"050000"
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            if ([r[@"ok"] boolValue]) {
                id rid = r[@"record_id"];
                id tid = r[@"tid"];
                self.logView.text = [NSString stringWithFormat:
                    @"✅ 提交成功\nrecord_id: %@\ntid: %@\n\n名称: %@",
                    rid ?: @"?", tid ?: @"?", name];
            } else {
                id e = r[@"error"];
                id c = r[@"code"];
                id m = r[@"message"];
                self.logView.text = [NSString stringWithFormat:
                    @"❌ 提交失败\n%@\ncode: %@  msg: %@",
                    e ?: @"?", c ?: @"-", m ?: @"-"];
            }
        });
    });
}

#pragma mark - POI submit end

- (void)onRefresh {
    if (self.busy) return;
    [self setBusy:YES];
    [self log:@"正在测试连通性…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *t = [ForgeRunner connectTest];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = t;
            [self setBusy:NO];
            [self refreshLight];
        });
    });
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
