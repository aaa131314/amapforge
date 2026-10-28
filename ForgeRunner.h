#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ForgeRunner : NSObject

/// 执行 amap-forge on [id]，返回输出文本
+ (NSString *)startWithID:(nullable NSString *)utdid;

/// 执行 amap-forge off
+ (NSString *)stop;

/// 执行 amap-forge status
+ (NSString *)status;

/// 生成随机 22 位 ID
+ (NSString *)randomID;

/// 当前是否在运行
+ (BOOL)isRunning;

/// 从日志里读当前伪造 ID
+ (nullable NSString *)currentID;

/// 已服务次数
+ (NSInteger)servedCount;

@end

NS_ASSUME_NONNULL_END
