#import "ForgeRunner.h"

// 服务器地址：优先读 NSUserDefaults，没有就用默认值
static NSString *const kDefaultServer = @"https://euphemism-rentable-defendant.ngrok-free.dev";

static NSString *serverURL(void) {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:@"amapforge_server"];
    if (s.length > 8) return s;
    return kDefaultServer;
}

static NSURLSession *_sharedSession(void) {
    static NSURLSession *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30;
        cfg.timeoutIntervalForResource = 150;
        cfg.HTTPMaximumConnectionsPerHost = 4;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        s = [NSURLSession sessionWithConfiguration:cfg];
    });
    return s;
}

@implementation ForgeRunner


/// 当前服务器地址
+ (NSString *)serverAddr {
    return serverURL();
}

/// 设置服务器地址（持久化）
+ (BOOL)setServerAddr:(NSString *)addr {
    if (addr.length < 8) return NO;
    if (![addr hasPrefix:@"http://"] && ![addr hasPrefix:@"https://"]) return NO;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:addr forKey:@"amapforge_server"];
    [ud synchronize];
    return YES;
}

#pragma mark - HTTP

+ (NSDictionary *)postJSON:(NSString *)path body:(NSDictionary *)body timeout:(NSTimeInterval)t {
    @try {
        NSURL *url = [NSURL URLWithString:[serverURL() stringByAppendingString:path]];
        if (!url) return @{@"ok": @NO, @"error": @"URL 无效"};

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setValue:@"1" forHTTPHeaderField:@"ngrok-skip-browser-warning"];
        req.timeoutInterval = t;

        NSError *err = nil;
        NSData *payload = [NSJSONSerialization dataWithJSONObject:body ?: @{}
                                                         options:0 error:&err];
        if (err) return @{@"ok": @NO, @"error": err.localizedDescription};
        req.HTTPBody = payload;

        __block NSData *respData = nil;
        __block NSError *respErr = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [[_sharedSession() dataTaskWithRequest:req
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                respData = d; respErr = e;
                dispatch_semaphore_signal(sem);
            }] resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((t + 15) * NSEC_PER_SEC)));

        if (respErr) return @{@"ok": @NO, @"error": respErr.localizedDescription ?: @"网络错误"};
        if (!respData) return @{@"ok": @NO, @"error": @"超时"};

        id obj = [NSJSONSerialization JSONObjectWithData:respData options:0 error:nil];
        return [obj isKindOfClass:[NSDictionary class]] ? obj : @{@"ok": @NO, @"error": @"格式错误"};
    } @catch (NSException *e) {
        return @{@"ok": @NO, @"error": e.reason ?: e.name ?: @"异常"};
    }
}

+ (NSDictionary *)getJSON:(NSString *)path {
    @try {
        NSURL *url = [NSURL URLWithString:[serverURL() stringByAppendingString:path]];
        if (!url) return @{@"ok": @NO};

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"GET";
        req.timeoutInterval = 30;
        [req setValue:@"1" forHTTPHeaderField:@"ngrok-skip-browser-warning"];

        __block NSData *respData = nil;
        __block NSError *respErr = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [[_sharedSession() dataTaskWithRequest:req
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                respData = d; respErr = e;
                dispatch_semaphore_signal(sem);
            }] resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)));

        if (respErr || !respData) {
            return @{@"ok": @NO, @"error": respErr.localizedDescription ?: @"超时"};
        }
        id obj = [NSJSONSerialization JSONObjectWithData:respData options:0 error:nil];
        return [obj isKindOfClass:[NSDictionary class]] ? obj : @{@"ok": @NO};
    } @catch (NSException *e) {
        return @{@"ok": @NO};
    }
}

+ (NSString *)str:(id)v def:(NSString *)d {
    return [v isKindOfClass:[NSString class]] ? v : d;
}


/// 读取伪装参数
+ (NSDictionary *)spoofConfig {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return @{
        @"model": [ud stringForKey:@"amapforge_model"] ?: @"iPhone15,2",
        @"ios": [ud stringForKey:@"amapforge_ios"] ?: @"17.5.1",
        @"ios_n": [ud objectForKey:@"amapforge_ios_n"] ?: @170501,
        @"lat": [ud objectForKey:@"amapforge_lat"] ?: @39.9042,
        @"lng": [ud objectForKey:@"amapforge_lng"] ?: @116.4074,
        @"adcode": [ud stringForKey:@"amapforge_adcode"] ?: @"110000"
    };
}

/// 保存伪装参数
+ (void)setSpoofConfig:(NSDictionary *)cfg {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (cfg[@"model"]) [ud setObject:cfg[@"model"] forKey:@"amapforge_model"];
    if (cfg[@"ios"]) [ud setObject:cfg[@"ios"] forKey:@"amapforge_ios"];
    if (cfg[@"ios_n"]) [ud setObject:cfg[@"ios_n"] forKey:@"amapforge_ios_n"];
    if (cfg[@"lat"]) [ud setObject:cfg[@"lat"] forKey:@"amapforge_lat"];
    if (cfg[@"lng"]) [ud setObject:cfg[@"lng"] forKey:@"amapforge_lng"];
    if (cfg[@"adcode"]) [ud setObject:cfg[@"adcode"] forKey:@"amapforge_adcode"];
    [ud synchronize];
}


#pragma mark - POI submit

/// 提交一条新增地点
+ (NSDictionary *)submitPOI:(NSDictionary *)poi {
    @try {
        NSMutableDictionary *b = [NSMutableDictionary dictionary];
        [b setObject:@"on" forKey:@"action"];  // 占位，实际不用
        [b removeObjectForKey:@"action"];

        [b setObject:(poi[@"name"] ?: @"") forKey:@"name"];
        [b setObject:(poi[@"addr"] ?: @"") forKey:@"addr"];
        [b setObject:(poi[@"tel"] ?: @"") forKey:@"tel"];
        [b setObject:(poi[@"hours"] ?: @"") forKey:@"hours"];
        [b setObject:(poi[@"cat"] ?: @"050000") forKey:@"cat"];
        if (poi[@"lat"]) [b setObject:poi[@"lat"] forKey:@"lat"];
        if (poi[@"lng"]) [b setObject:poi[@"lng"] forKey:@"lng"];

        NSDictionary *r = [self postJSON:@"/api/submit" body:b timeout:60];
        return r ?: @{@"ok": @NO, @"error": @"无响应"};
    } @catch (NSException *e) {
        return @{@"ok": @NO, @"error": (e.reason ?: e.name ?: @"异常")};
    }
}

/// 批量提交
+ (NSDictionary *)submitBatch:(NSArray *)items {
    @try {
        NSMutableDictionary *b = [NSMutableDictionary dictionary];
        [b setObject:items forKey:@"items"];
        NSDictionary *r = [self postJSON:@"/api/batch" body:b timeout:180];
        return r ?: @{@"ok": @NO, @"error": @"无响应"};
    } @catch (NSException *e) {
        return @{@"ok": @NO, @"error": (e.reason ?: e.name ?: @"异常")};
    }
}

#pragma mark - public

+ (NSString *)startWithID:(NSString *)utdid {
    @try {
        NSMutableDictionary *b = [NSMutableDictionary dictionary];
        [b setObject:@"on" forKey:@"action"];
        if (utdid.length > 0) [b setObject:utdid forKey:@"id"];

        // 附上用户配置的伪装参数
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSString *model = [ud stringForKey:@"amapforge_model"];
        if (model.length > 0) [b setObject:model forKey:@"model"];

        NSString *ios = [ud stringForKey:@"amapforge_ios"];
        if (ios.length > 0) [b setObject:ios forKey:@"ios"];

        NSNumber *iosN = [ud objectForKey:@"amapforge_ios_n"];
        if (iosN) [b setObject:iosN forKey:@"ios_n"];

        NSNumber *lat = [ud objectForKey:@"amapforge_lat"];
        if (lat) [b setObject:lat forKey:@"lat"];

        NSNumber *lng = [ud objectForKey:@"amapforge_lng"];
        if (lng) [b setObject:lng forKey:@"lng"];

        NSString *adcode = [ud stringForKey:@"amapforge_adcode"];
        if (adcode.length > 0) [b setObject:adcode forKey:@"adcode"];

        NSDictionary *r = [self postJSON:@"/api/forge" body:b timeout:90];
        if ([r[@"ok"] boolValue]) {
            NSString *u = [self str:r[@"utdid"] def:@""];
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            [ud setBool:YES forKey:@"amapforge_injected"];
            if (u.length) [ud setObject:u forKey:@"amapforge_utdid"];
            [ud synchronize];
            return [NSString stringWithFormat:@"OK: 已注入\nUTDID: %@", u.length ? u : @"?"];
        }
        return [NSString stringWithFormat:@"FAIL: %@\n%@",
                [self str:r[@"error"] def:@"unknown"],
                [self str:r[@"log"] def:@""]];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"FAIL: %@", e.reason ?: e.name];
    }
}

+ (NSString *)stop {
    @try {
        NSDictionary *r = [self postJSON:@"/api/forge" body:@{@"action": @"off"} timeout:30];
        if ([r[@"ok"] boolValue]) {
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            [ud setBool:NO forKey:@"amapforge_injected"];
            [ud removeObjectForKey:@"amapforge_utdid"];
            [ud synchronize];
            return @"OK: 已停止，恢复真实身份";
        }
        return [NSString stringWithFormat:@"FAIL: %@", [self str:r[@"error"] def:@"unknown"]];
    } @catch (NSException *e) {
        return @"FAIL";
    }
}

+ (NSString *)status {
    @try {
        NSDictionary *r = [self getJSON:@"/api/forge/status"];
        if (![r[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"FAIL: 连不上服务器\n%@", [self str:r[@"error"] def:@""]];
        }
        BOOL running = [r[@"running"] boolValue];
        return [NSString stringWithFormat:@"state: %@\nutdid: %@\nserved: %@",
                running ? @"running" : @"idle",
                [self str:r[@"utdid"] def:@"-"],
                r[@"served"] ?: @0];
    } @catch (NSException *e) {
        return @"FAIL: 异常";
    }
}

+ (NSString *)connectTest {
    @try {
        NSDictionary *r = [self getJSON:@"/api/forge/status"];
        if (![r[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"连不上 %@\n%@",
                    serverURL(), [self str:r[@"error"] def:@"超时"]];
        }
        return [NSString stringWithFormat:@"服务器 OK\n%@", [self status]];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"异常: %@", e.reason ?: e.name];
    }
}

+ (NSDictionary *)statusDict {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        BOOL localInjected = [ud boolForKey:@"amapforge_injected"];
        NSString *localForged = [ud stringForKey:@"amapforge_utdid"];

        NSDictionary *r = [self getJSON:@"/api/forge/status"];
        BOOL reachable = [r[@"ok"] boolValue];
        BOOL serverRunning = reachable && [r[@"running"] boolValue];
        NSString *serverUtdid = [self str:r[@"utdid"] def:@""];

        NSString *shown = serverUtdid.length ? serverUtdid
                        : (localForged.length ? localForged : @"");

        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        [d setObject:@(reachable) forKey:@"ok"];
        [d setObject:@(localInjected || serverRunning) forKey:@"running"];
        [d setObject:shown forKey:@"utdid"];
        [d setObject:(reachable ? @"服务器在线" : @"连不上服务器") forKey:@"tcp"];
        return d;
    } @catch (NSException *e) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        [d setObject:@NO forKey:@"ok"];
        [d setObject:@NO forKey:@"running"];
        [d setObject:@"" forKey:@"utdid"];
        [d setObject:@"异常" forKey:@"tcp"];
        return d;
    }
}

+ (NSString *)wipeData:(BOOL)deep {
    @try {
        NSMutableDictionary *b = [NSMutableDictionary dictionary];
        [b setObject:@(deep) forKey:@"deep"];
        NSDictionary *r = [self postJSON:@"/api/wipe" body:b timeout:150];
        if ([r[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"OK: 清理 %@ KB\n%@",
                    r[@"kb"] ?: @0, [self str:r[@"detail"] def:@""]];
        }
        return [NSString stringWithFormat:@"FAIL: %@\n%@",
                [self str:r[@"error"] def:@"unknown"],
                [self str:r[@"detail"] def:@""]];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"FAIL: %@", e.reason ?: e.name];
    }
}

+ (NSString *)dataSizeText {
    @try {
        NSDictionary *r = [self getJSON:@"/api/wipe/size"];
        if ([r[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"%@\n%@",
                    [self str:r[@"human"] def:@"?"],
                    [self str:r[@"path"] def:@""]];
        }
        return [NSString stringWithFormat:@"FAIL: %@", [self str:r[@"error"] def:@"查询失败"]];
    } @catch (NSException *e) {
        return @"FAIL";
    }
}

+ (NSString *)dataSize {
    @try {
        NSDictionary *r = [self getJSON:@"/api/wipe/size"];
        if ([r[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"数据体积：%@", [self str:r[@"human"] def:@"?"]];
        }
        return [NSString stringWithFormat:@"查询失败：%@", [self str:r[@"error"] def:@"超时"]];
    } @catch (NSException *e) {
        return @"查询失败";
    }
}

+ (NSString *)currentForgedID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"amapforge_utdid"];
}

+ (BOOL)isInjected {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"amapforge_injected"];
}

+ (NSString *)randomID {
    NSString *cs = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:22];
    for (int i = 0; i < 22; i++) {
        [s appendFormat:@"%C", [cs characterAtIndex:arc4random_uniform((uint32_t)cs.length)]];
    }
    return s;
}

+ (BOOL)isRunning { return [[self statusDict][@"running"] boolValue]; }
+ (NSString *)currentID { return [self statusDict][@"utdid"]; }
+ (NSInteger)servedCount { return 0; }

@end
