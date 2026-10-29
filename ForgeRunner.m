#import "ForgeRunner.h"

// 服务器地址：优先读 NSUserDefaults，没有就用默认值
static NSString *const kDefaultServer = @"https://guide-juan-collector-calls.trycloudflare.com";

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

#pragma mark - public

+ (NSString *)startWithID:(NSString *)utdid {
    @try {
        NSMutableDictionary *b = [NSMutableDictionary dictionary];
        [b setObject:@"on" forKey:@"action"];
        if (utdid.length > 0) [b setObject:utdid forKey:@"id"];

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
