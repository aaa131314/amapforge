#import "ForgeRunner.h"

// 直连本机 frida-server（完全离线）
#include "frida-core.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <netdb.h>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

static NSString *const kAppBundle = @"com.autonavi.amap";
static NSString *const kRemoteAddr = @"127.0.0.1:27042";

// ---- GLib 主循环（收 send() 消息）----
@implementation ForgeRunner

#pragma mark - socket 预检

+ (NSString *)tcpProbe:(NSString *)host port:(int)port timeoutMs:(int)ms {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%d", port);
    int gai = getaddrinfo(host.UTF8String, portStr, &hints, &res);
    if (gai != 0 || !res) {
        return [NSString stringWithFormat:@"getaddrinfo 失败 gai=%d", gai];
    }

    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(res);
        return [NSString stringWithFormat:@"socket() 失败 errno=%d", errno];
    }

    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    int rc = connect(fd, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    if (rc < 0 && errno != EINPROGRESS) {
        int e = errno; close(fd);
        return [NSString stringWithFormat:@"connect 立即失败 errno=%d (%s)", e, strerror(e)];
    }
    if (rc == 0) { close(fd); return [NSString stringWithFormat:@"TCP OK %@:%d（直连成功）", host, port]; }

    fd_set wfds; FD_ZERO(&wfds); FD_SET(fd, &wfds);
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    rc = select(fd + 1, NULL, &wfds, NULL, &tv);
    if (rc == 0) { close(fd); return [NSString stringWithFormat:@"connect 超时 %dms", ms]; }
    if (rc < 0) { int e = errno; close(fd); return [NSString stringWithFormat:@"select 失败 errno=%d", e]; }

    int soerr = 0; socklen_t slen = sizeof(soerr);
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen);
    close(fd);
    if (soerr != 0) {
        return [NSString stringWithFormat:@"SO_ERROR=%d (%s)", soerr, strerror(soerr)];
    }
    return [NSString stringWithFormat:@"TCP OK %@:%d", host, port];
}

#pragma mark - helpers

+ (NSString *)jsSourceNamed:(NSString *)name {
    NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"js"];
    if (!p) return nil;
    return [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
}

+ (void)runOnFridaThread:(void (^)(void))block {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("amapforge.frida", DISPATCH_QUEUE_SERIAL);
        frida_init();
    });
    dispatch_async(q, ^{
        @try {
            block();
        } @catch (NSException *e) {
            NSLog(@"[amapforge] 异常: %@ %@", e.name, e.reason);
        } @catch (...) {
            NSLog(@"[amapforge] 未知异常");
        }
    });
}

+ (NSString *)errStr:(GError *)e {
    if (!e) return @"";
    NSString *s = [NSString stringWithFormat:@"%s", e->message];
    g_error_free(e);
    return s;
}

#pragma mark - 注入 UTDID

+ (NSString *)injectSync {
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:3000];
    if (![tcp hasPrefix:@"TCP OK"]) return [NSString stringWithFormat:@"FAIL: 端口不通\n%@", tcp];

    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: frida 连接失败\n%@", e];
    }

    FridaProcess *old = frida_device_get_process_by_name_sync(
        dev, kAppBundle.UTF8String, NULL, NULL, NULL);
    if (old) {
        frida_device_kill_sync(dev, frida_process_get_pid(old), NULL, &err);
        if (err) { g_error_free(err); err = NULL; }
        g_object_unref(old);
        [NSThread sleepForTimeInterval:1.0];
    }

    guint pid = frida_device_spawn_sync(dev, kAppBundle.UTF8String, NULL, NULL, &err);
    if (pid == 0) {
        NSString *e = [self errStr:err];
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: spawn 失败\n%@", e];
    }

    FridaSession *session = frida_device_attach_sync(dev, pid, NULL, NULL, &err);
    if (!session) {
        NSString *e = [self errStr:err];
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: attach 失败 (pid %u)\n%@", pid, e];
    }

    NSString *js = [self jsSourceNamed:@"forge_utdid"];
    if (!js) {
        g_object_unref(session); g_object_unref(dev); g_object_unref(mgr);
        return @"FAIL: 包内缺少 forge_utdid.js";
    }

    FridaScriptOptions *opts = frida_script_options_new();
    frida_script_options_set_name(opts, "forge");
    frida_script_options_set_runtime(opts, FRIDA_SCRIPT_RUNTIME_QJS);

    FridaScript *script = frida_session_create_script_sync(
        session, js.UTF8String, opts, NULL, &err);
    if (!script) {
        NSString *e = [self errStr:err];
        g_object_unref(opts); g_object_unref(session);
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 创建脚本失败\n%@", e];
    }

    frida_script_load_sync(script, NULL, &err);
    if (err) {
        NSString *e = [self errStr:err];
        g_object_unref(script); g_object_unref(opts); g_object_unref(session);
        g_object_unref(dev); g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 加载脚本失败\n%@", e];
    }

    frida_device_resume_sync(dev, pid, NULL, &err);
    if (err) { g_error_free(err); err = NULL; }
    [NSThread sleepForTimeInterval:2.0];

    g_object_unref(script); g_object_unref(opts); g_object_unref(session);
    g_object_unref(dev); g_object_unref(mgr);

    // 记录注入状态（供状态显示用，不依赖高德进程是否存活）
    NSString *forged = [self currentForgedID];
    if (!forged) {
        forged = [self randomID];
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:@"amapforge_injected"];
    [ud setObject:forged forKey:@"amapforge_utdid"];
    [ud setObject:[NSDate date] forKey:@"amapforge_inject_time"];
    [ud synchronize];

    return [NSString stringWithFormat:@"OK: 已注入 %@ (pid %u)\n设备 ID: %@", kAppBundle, pid, forged];
}

+ (NSString *)detachSync {
    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: 连接失败\n%@", e];
    }
    FridaProcess *p = frida_device_get_process_by_name_sync(
        dev, kAppBundle.UTF8String, NULL, NULL, NULL);
    if (p) {
        frida_device_kill_sync(dev, frida_process_get_pid(p), NULL, &err);
        if (err) { g_error_free(err); err = NULL; }
        g_object_unref(p);
        g_object_unref(dev); g_object_unref(mgr);
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:NO forKey:@"amapforge_injected"];
        [ud removeObjectForKey:@"amapforge_utdid"];
        [ud synchronize];
        return @"OK: 高德已停止，恢复真实身份";
    }
    g_object_unref(dev); g_object_unref(mgr);
    return @"OK: 高德未运行";
}

+ (NSString *)probeSync {
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:3000];
    if (![tcp hasPrefix:@"TCP OK"]) return [NSString stringWithFormat:@"FAIL: 端口不通\n%@", tcp];

    GError *err = NULL;
    FridaDeviceManager *mgr = frida_device_manager_new();
    FridaDevice *dev = frida_device_manager_add_remote_device_sync(
        mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
    if (!dev) {
        NSString *e = [self errStr:err];
        g_object_unref(mgr);
        return [NSString stringWithFormat:@"FAIL: frida 库连不上\nTCP: %@\nfrida: %@", tcp, e];
    }
    FridaProcess *p = frida_device_get_process_by_name_sync(
        dev, kAppBundle.UTF8String, NULL, NULL, NULL);
    NSString *s;
    if (p) {
        s = [NSString stringWithFormat:@"running pid %u | %@", frida_process_get_pid(p), tcp];
        g_object_unref(p);
    } else {
        s = [NSString stringWithFormat:@"idle | %@", tcp];
    }
    g_object_unref(dev); g_object_unref(mgr);
    return s;
}

#pragma mark - public

+ (NSString *)startWithID:(NSString *)utdid {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{ r = [self injectSync]; dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)));
    return r;
}

+ (NSString *)stop {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{ r = [self detachSync]; dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));
    return r;
}

+ (NSString *)status {
    __block NSString *r = @"timeout";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self runOnFridaThread:^{ r = [self probeSync]; dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    return r;
}

+ (NSDictionary *)statusDict {
    @try {
    // 1) 注入标记（本地记录，不依赖高德进程）
    BOOL injected = [self isInjected];
    NSString *forged = [self currentForgedID];

    // 2) frida 连通性（轻量）
    NSString *tcp = [self tcpProbe:@"127.0.0.1" port:27042 timeoutMs:2000];
    BOOL ok = [tcp hasPrefix:@"TCP OK"];

    // 3) 高德进程状态（附带的）
    NSString *proc = @"";
    if (ok) {
        GError *err = NULL;
        FridaDeviceManager *mgr = frida_device_manager_new();
        FridaDevice *dev = frida_device_manager_add_remote_device_sync(
            mgr, kRemoteAddr.UTF8String, NULL, NULL, &err);
        if (dev) {
            FridaProcess *p = frida_device_get_process_by_name_sync(
                dev, kAppBundle.UTF8String, NULL, NULL, NULL);
            if (p) {
                proc = [NSString stringWithFormat:@"pid %u", frida_process_get_pid(p)];
                g_object_unref(p);
            }
            g_object_unref(dev);
        } else if (err) {
            g_error_free(err);
        }
        g_object_unref(mgr);
    }

    return @{@"ok": @(ok),
             @"running": @(injected),
             @"utdid": forged ?: @"",
             @"proc": proc ?: @"",
             @"tcp": tcp ?: @""};
    } @catch (NSException *e) {
        return @{@"ok": @NO, @"running": @NO, @"utdid": @"",
                 @"proc": @"", @"tcp": [NSString stringWithFormat:@"异常: %@", e.name]};
    }
}

+ (NSString *)shellOut:(NSString *)cmd timeoutSec:(int)timeoutSec {
    int fds[2];
    if (pipe(fds) != 0) return @"pipe 失败";
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    posix_spawn_file_actions_addclose(&actions, fds[1]);

    const char *bash = "/var/jb/usr/bin/bash";
    // 关键：把 cmd 拷到 C 缓冲，避免 autorelease 导致悬空指针
    size_t cmdLen = strlen([cmd UTF8String]) + 1;
    char *cmdBuf = (char *)malloc(cmdLen);
    if (!cmdBuf) { close(fds[0]); return @"内存不足"; }
    memcpy(cmdBuf, [cmd UTF8String], cmdLen);
    char *argv[] = {(char *)bash, (char *)"-lc", cmdBuf, NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, bash, &actions, NULL, argv, environ);
    free(cmdBuf);
    posix_spawn_file_actions_destroy(&actions);
    close(fds[1]);
    if (rc != 0) { close(fds[0]); return [NSString stringWithFormat:@"posix_spawn err=%d (%s)", rc, strerror(rc)]; }

    fcntl(fds[0], F_SETFL, O_NONBLOCK);
    NSMutableData *out = [NSMutableData data];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSec];
    char buf[4096];
    while ([deadline timeIntervalSinceNow] > 0) {
        ssize_t n = read(fds[0], buf, sizeof(buf));
        if (n > 0) { [out appendBytes:buf length:(NSUInteger)n]; }
        else if (n == 0) { break; }
        else { [NSThread sleepForTimeInterval:0.1]; }
    }
    close(fds[0]);
    int status = 0;
    waitpid(pid, &status, WNOHANG);
    NSString *s = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    return s ?: @"（无输出）";
}

+ (NSString *)wipeData:(BOOL)deep {
    @try {
    NSString *cmd = deep ? @"/var/jb/usr/bin/amap-wipe run --deep"
                         : @"/var/jb/usr/bin/amap-wipe run";
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/amap-wipe"]) {
        return @"FAIL: 未安装 amap-wipe\n请先装 com.local.amappoi >= 1.2.2";
    }
    NSString *r = [self shellOut:cmd timeoutSec:120];
    return r.length ? r : @"FAIL: 无输出";
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"FAIL: %@ %@", e.name, e.reason];
    }
}

+ (NSString *)dataSizeText {
    @try {
        if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/amap-wipe"]) {
            return @"FAIL: 未安装 amap-wipe";
        }
        return [self shellOut:@"/var/jb/usr/bin/amap-wipe size" timeoutSec:90];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"FAIL: %@ %@", e.name, e.reason];
    }
}

+ (NSString *)dataSize {
    NSString *r = [self dataSizeText];
    NSRange hr = [r rangeOfString:@"'human': '"];
    if (hr.location == NSNotFound) return r;
    NSString *tail = [r substringFromIndex:hr.location + hr.length];
    NSRange end = [tail rangeOfString:@"'"];
    if (end.location == NSNotFound) return r;
    return [NSString stringWithFormat:@"数据体积：%@",
            [tail substringToIndex:end.location]];
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
