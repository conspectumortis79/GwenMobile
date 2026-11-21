#import <Foundation/Foundation.h>

#if TARGET_OS_MACCATALYST || DEBUG
NS_ASSUME_NONNULL_BEGIN

@interface GwenVariadicAssertionHandler : NSAssertionHandler

- (void)handleMethodFailure:(SEL)selector
                     object:(nullable id)object
                       file:(nullable NSString *)fileName
                 lineNumber:(NSInteger)line
                description:(nullable NSString *)description;

- (void)handleFunctionFailure:(nullable NSString *)functionName
                         file:(nullable NSString *)fileName
                   lineNumber:(NSInteger)line
                  description:(nullable NSString *)description
    NS_SWIFT_NAME(handleFunctionFailure(function:file:lineNumber:description:));

#if DEBUG
- (void)invokeVariadicMethod:(SEL)selector
                      object:(nullable id)object
                        file:(NSString *)fileName
                  lineNumber:(NSInteger)line
                       value:(NSInteger)value
                       label:(NSString *)label;

- (void)invokeVariadicFunction:(NSString *)functionName
                          file:(NSString *)fileName
                    lineNumber:(NSInteger)line
                         value:(NSInteger)value
                         label:(NSString *)label;
#endif

@end

NS_ASSUME_NONNULL_END
#endif
