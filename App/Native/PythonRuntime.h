#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PythonRuntime : NSObject
+ (void)prepareOperation;
+ (void)cancel;
+ (NSString *)runRequest:(NSString *)request
               progress:(void (^)(NSString *event))progress
    NS_SWIFT_NAME(run(request:progress:));
@end

NS_ASSUME_NONNULL_END
