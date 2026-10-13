#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface FLEXKingProviderOperation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *operationDescription;
@property (nonatomic, copy) NSDictionary *parameters;
@property (nonatomic, copy) NSDictionary *result;
@property (nonatomic, copy) NSDictionary *limits;
@property (nonatomic) BOOL mutates;
@property (nonatomic) BOOL asynchronous;
@property (nonatomic, copy) id (^handler)(NSDictionary *arguments, NSError **error);
@end
@interface FLEXKingProvider : NSObject
@property (nonatomic) NSUInteger sdkVersion;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *productVersion;
@property (nonatomic, copy) NSString *buildIdentifier;
@property (nonatomic, copy) NSDictionary *limits;
@property (nonatomic, copy) NSArray<FLEXKingProviderOperation *> *operations;
@end
extern BOOL FLEXKingRegisterProvider(FLEXKingProvider *provider, NSError **error) __attribute__((weak_import));
extern BOOL FLEXKingUnregisterProvider(NSString *identifier) __attribute__((weak_import));
NS_ASSUME_NONNULL_END
