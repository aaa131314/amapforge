#import "ForgeRunner.h"
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

static NSString *const kForgeBin = @"/var/jb/usr/bin/amap-forge";
static NSString *const kForgeLog = @"/var/jb/var/log/amap-forge.log";

@implementation ForgeRunner

/// 用 posix_spawn 执行 shell 命令（iOS 上没有 NSTask）
+ (NSString *)runShell:(NSString *)cmd {
    NSMutableData *out = [NSMutableData data];
    int fds[2];
    if (pipe(fds) != 0) return @"pipe failed";

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    posix_spawn_file_actions_addclose(&actions, fds[1]);

    const char *bash = "/var/jb/usr/bin/bash";
    const char *cflag = "-lc";
    const char *cstr = [cmd UTF8String];
    char *argv[] = {(char *)bash, (char *)cflag, (char *)cstr, NULL};

    pid_t pid = 0;
    int rc = posix_spawn(&pid, bash, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(fds[1]);

    if (rc != 0) {
        close(fds[0]);
        return [NSString stringWithFormat:@"posix_spawn err=%d (%s)", rc, strerror(rc)];
    }

    char buf[4096];
    ssize_t n;
    while ((n = read(fds[0], buf, sizeof(buf))) > 0) {
        [out appendBytes:buf length:(NSUInteger)n];
    }
    close(fds[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    NSString *s = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    return s ?: @"";
}

+ (NSString *)startWithID:(NSString *)utdid {
    NSString *arg = utdid.length > 0 ? [NSString stringWithFormat:@" %@", utdid] : @"";
    return [self runShell:[NSString stringWithFormat:@"%@ on%@", kForgeBin, arg]];
}

+ (NSString *)stop {
    return [self runShell:[NSString stringWithFormat:@"%@ off", kForgeBin]];
}

+ (NSString *)status {
    return [self runShell:[NSString stringWithFormat:@"%@ status", kForgeBin]];
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
    NSString *out = [self runShell:@"pgrep -x frida >/dev/null 2>&1 && echo YES || echo NO"];
    return [out containsString:@"YES"];
}

+ (NSString *)currentID {
    NSString *log = [NSString stringWithContentsOfFile:kForgeLog
                                             encoding:NSUTF8StringEncoding
                                                error:nil];
    if (!log) return nil;
    NSRange r = [log rangeOfString:@"forged UTDID="];
    if (r.location == NSNotFound) return nil;
    NSString *tail = [log substringFromIndex:r.location + r.length];
    NSCharacterSet *stop = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSRange end = [tail rangeOfCharacterFromSet:stop];
    if (end.location == NSNotFound) return tail;
    return [tail substringToIndex:end.location];
}

+ (NSInteger)servedCount {
    NSString *log = [NSString stringWithContentsOfFile:kForgeLog
                                             encoding:NSUTF8StringEncoding
                                                error:nil];
    if (!log) return 0;
    NSInteger n = 0;
    NSUInteger pos = 0;
    while (pos < log.length) {
        NSRange r = [log rangeOfString:@"'kind': 'served'" options:0
                                 range:NSMakeRange(pos, log.length - pos)];
        if (r.location == NSNotFound) break;
        n++;
        pos = r.location + r.length;
    }
    return n;
}

@end
