#import "ForgeRunner.h"

// 电脑端 forge 服务（同一 WiFi 下）
static NSString *const kServer = @"http://192.168.5.25:8050";

@implementation ForgeRunner

/// 同步 HTTP POST JSON
+ (NSDictionary *)postJSON:(NSString *)path body:(NSDictionary *)body {
    NSString *urlStr = [kServer stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return @{@"ok": @NO, @"error": @"bad url"};

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.timeoutInterval = 45;

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
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_SEC)));

    if (respErr) return @{@"ok": @NO, @"error": respErr.localizedDescription};
    if (!respData) return @{@"ok": @NO, @"error": @"no response"};

    NSError *jerr = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:respData options:0 error:&jerr];
    if (jerr || ![obj isKindOfClass:[NSDictionary class]]) {
        NSString *s = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
        return @{@"ok": @NO, @"error": s ?: @"bad json"};
    }
    return (NSDictionary *)obj;
}

+ (NSDictionary *)getJSON:(NSString *)path {
    NSString *urlStr = [kServer stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return @{@"ok": @NO};

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 10;

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
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)));

    if (respErr || !respData) return @{@"ok": @NO};
    id obj = [NSJSONSerialization JSONObjectWithData:respData options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{@"ok": @NO};
}

+ (NSString *)startWithID:(NSString *)utdid {
    NSMutableDictionary *b = [@{@"action": @"on"} mutableCopy];
    if (utdid.length > 0) b[@"id"] = utdid;
    NSDictionary *r = [self postJSON:@"/api/forge" body:b];
    if ([r[@"ok"] boolValue]) {
        return [NSString stringWithFormat:@"OK: injected\nUTDID: %@",
                r[@"utdid"] ?: @"?"];
    }
    return [NSString stringWithFormat:@"FAIL: %@\n%@",
            r[@"error"] ?: @"unknown",
            r[@"log"] ?: @""];
}

+ (NSString *)stop {
    NSDictionary *r = [self postJSON:@"/api/forge" body:@{@"action": @"off"}];
    return [r[@"ok"] boolValue] ? @"stopped" : @"FAIL";
}

+ (NSString *)status {
    NSDictionary *r = [self getJSON:@"/api/forge/status"];
    if (![r[@"ok"] boolValue]) return @"server unreachable";
    BOOL running = [r[@"running"] boolValue];
    return [NSString stringWithFormat:@"state: %@\nutdid: %@\nserved: %@",
            running ? @"running" : @"idle",
            r[@"utdid"] ?: @"-",
            r[@"served"] ?: @"0"];
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
    NSDictionary *r = [self getJSON:@"/api/forge/status"];
    return [r[@"running"] boolValue];
}

+ (NSString *)currentID {
    NSDictionary *r = [self getJSON:@"/api/forge/status"];
    id v = r[@"utdid"];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

+ (NSInteger)servedCount {
    NSDictionary *r = [self getJSON:@"/api/forge/status"];
    id v = r[@"served"];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

@end
