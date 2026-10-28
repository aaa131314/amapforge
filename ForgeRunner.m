#import "ForgeRunner.h"

// 电脑端 forge 服务（同一 WiFi 下）
static NSString *const kServer = @"http://192.168.5.25:8050";

@implementation ForgeRunner

+ (NSDictionary *)postJSON:(NSString *)path body:(NSDictionary *)body timeout:(NSTimeInterval)t {
    NSString *urlStr = [kServer stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return @{@"ok": @NO, @"error": @"bad url"};

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.timeoutInterval = t;

    NSError *err = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body ?: @{}
                                                     options:0
                                                       error:&err];
    if (err) return @{@"ok": @NO, @"error": err.localizedDescription};
    req.HTTPBody = payload;

    __block NSData *respData = nil;
    __block NSError *respErr = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:req
                                       completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            respData = d;
            respErr = e;
            dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((t + 5) * NSEC_PER_SEC)));

    if (respErr) return @{@"ok": @NO, @"error": respErr.localizedDescription};
    if (!respData) return @{@"ok": @NO, @"error": @"no response"};

    id obj = [NSJSONSerialization JSONObjectWithData:respData options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        NSString *s = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
        return @{@"ok": @NO, @"error": s ?: @"bad json"};
    }
    return (NSDictionary *)obj;
}

+ (NSDictionary *)postJSON:(NSString *)path body:(NSDictionary *)body {
    return [self postJSON:path body:body timeout:45];
}

+ (NSDictionary *)getJSON:(NSString *)path {
    NSString *urlStr = [kServer stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return @{@"ok": @NO};

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 15;

    __block NSData *respData = nil;
    __block NSError *respErr = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:req
                                       completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            respData = d;
            respErr = e;
            dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));

    if (respErr || !respData) return @{@"ok": @NO};
    id obj = [NSJSONSerialization JSONObjectWithData:respData options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{@"ok": @NO};
}

+ (NSString *)startWithID:(NSString *)utdid {
    NSMutableDictionary *b = [@{@"action": @"on"} mutableCopy];
    if (utdid.length > 0) b[@"id"] = utdid;
    NSDictionary *r = [self postJSON:@"/api/forge" body:b];
    if ([r[@"ok"] boolValue]) {
        return [NSString stringWithFormat:@"OK: injected\nUTDID: %@", r[@"utdid"] ?: @"?"];
    }
    return [NSString stringWithFormat:@"FAIL: %@\n%@", r[@"error"] ?: @"unknown", r[@"log"] ?: @""];
}

+ (NSString *)stop {
    NSDictionary *r = [self postJSON:@"/api/forge" body:@{@"action": @"off"}];
    return [r[@"ok"] boolValue] ? @"stopped" : @"FAIL";
}

+ (NSString *)status {
    NSDictionary *r = [self getJSON:@"/api/forge/status"];
    if (![r[@"ok"] boolValue]) return @"server unreachable";
    return [NSString stringWithFormat:@"state: %@\nutdid: %@\nserved: %@",
            [r[@"running"] boolValue] ? @"running" : @"idle",
            r[@"utdid"] ?: @"-", r[@"served"] ?: @"0"];
}

/// 清理高德数据（deep=YES 连离线地图一起删）
+ (NSString *)wipeData:(BOOL)deep {
    NSDictionary *r = [self postJSON:@"/api/wipe" body:@{@"deep": @(deep)} timeout:90];
    if ([r[@"ok"] boolValue]) {
        return [NSString stringWithFormat:@"OK: cleaned %@KB\n%@",
                r[@"kb"] ?: @"0", r[@"detail"] ?: @""];
    }
    return [NSString stringWithFormat:@"FAIL: %@\n%@", r[@"error"] ?: @"unknown", r[@"detail"] ?: @""];
}

/// 数据体积
+ (NSString *)dataSize {
    NSDictionary *r = [self getJSON:@"/api/wipe/size"];
    if (![r[@"ok"] boolValue]) return @"server unreachable";
    return [NSString stringWithFormat:@"data: %@\ncontainer: %@",
            r[@"human"] ?: @"?", r[@"path"] ?: @"?"];
}

+ (NSString *)randomID {
    NSString *cs = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:22];
    for (int i = 0; i < 22; i++) {
        [s appendFormat:@"%C", [cs characterAtIndex:arc4random_uniform((uint32_t)cs.length)]];
    }
    return s;
}

+ (BOOL)isRunning {
    return [[self getJSON:@"/api/forge/status"] [@"running"] boolValue];
}

+ (NSString *)currentID {
    id v = [self getJSON:@"/api/forge/status"][@"utdid"];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

+ (NSInteger)servedCount {
    id v = [self getJSON:@"/api/forge/status"][@"served"];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

@end
