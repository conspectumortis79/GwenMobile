#import "GwenVariadicAssertionHandler.h"

#if TARGET_OS_MACCATALYST || DEBUG
#define GWEN_FORMAT_DESCRIPTION(format) \
    ({ \
        NSString *gwenFormatted = nil; \
        if ((format) != nil) { \
            va_list gwenArgs; \
            va_start(gwenArgs, format); \
            gwenFormatted = [[NSString alloc] initWithFormat:(format) arguments:gwenArgs]; \
            va_end(gwenArgs); \
        } \
        gwenFormatted; \
    })

#if DEBUG
static NSString * const GwenVariadicProbeFormat = @"offset %ld for %@";
#endif

@implementation GwenVariadicAssertionHandler

- (void)handleFailureInMethod:(SEL)selector
                       object:(id)object
                         file:(NSString *)fileName
                   lineNumber:(NSInteger)line
                  description:(nullable NSString *)format, ... {
    [self handleMethodFailure:selector
                       object:object
                         file:fileName
                   lineNumber:line
                  description:GWEN_FORMAT_DESCRIPTION(format)];
}

- (void)handleFailureInFunction:(NSString *)functionName
                           file:(NSString *)fileName
                     lineNumber:(NSInteger)line
                    description:(nullable NSString *)format, ... {
    [self handleFunctionFailure:functionName
                           file:fileName
                     lineNumber:line
                    description:GWEN_FORMAT_DESCRIPTION(format)];
}

- (void)handleMethodFailure:(SEL)selector
                     object:(nullable id)object
                       file:(nullable NSString *)fileName
                 lineNumber:(NSInteger)line
                description:(nullable NSString *)description {
}

- (void)handleFunctionFailure:(nullable NSString *)functionName
                         file:(nullable NSString *)fileName
                   lineNumber:(NSInteger)line
                  description:(nullable NSString *)description {
}

#if DEBUG
- (void)invokeVariadicMethod:(SEL)selector
                      object:(nullable id)object
                        file:(NSString *)fileName
                  lineNumber:(NSInteger)line
                       value:(NSInteger)value
                       label:(NSString *)label {
    [self handleFailureInMethod:selector object:object file:fileName lineNumber:line
                    description:GwenVariadicProbeFormat, (long)value, label];
}

- (void)invokeVariadicFunction:(NSString *)functionName
                          file:(NSString *)fileName
                    lineNumber:(NSInteger)line
                         value:(NSInteger)value
                         label:(NSString *)label {
    [self handleFailureInFunction:functionName file:fileName lineNumber:line
                      description:GwenVariadicProbeFormat, (long)value, label];
}
#endif

@end
#endif
