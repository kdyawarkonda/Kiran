//
//  GlassesWiFiHandler.h
//  QCSDKDemo
//
//  Provides a centralized way to request Wi-Fi credentials from the glasses
//  device, configure the hotspot on iOS, and validate the connection. All
//  operations are serialized internally to avoid race conditions.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GlassesWiFiHandlerState) {
    GlassesWiFiHandlerStateIdle = 0,
    GlassesWiFiHandlerStateRequestingCredentials,
    GlassesWiFiHandlerStateConfiguring,
    GlassesWiFiHandlerStateWaitingForAssociation,
    GlassesWiFiHandlerStateResolvingIP,
    GlassesWiFiHandlerStateConnected,
    GlassesWiFiHandlerStateFailed,
};

typedef void (^GlassesWiFiHandlerStatusCallback)(GlassesWiFiHandlerState state,
                                                  NSString *status,
                                                  UIImage * _Nullable previewImage);

typedef void (^GlassesWiFiHandlerCredentialsCallback)(NSString *ssid,
                                                       NSString *password,
                                                       NSError * _Nullable error);

typedef void (^GlassesWiFiHandlerConnectionCallback)(BOOL success,
                                                      NSString * _Nullable deviceIP,
                                                      NSError * _Nullable error);

@interface GlassesWiFiHandler : NSObject

+ (instancetype)sharedHandler;

- (void)requestWiFiCredentialsWithStatusCallback:(GlassesWiFiHandlerStatusCallback)statusCallback
                                      completion:(GlassesWiFiHandlerCredentialsCallback)completion;

- (void)connectToGlassesWiFi:(NSString *)ssid
                     password:(NSString *)password
               statusCallback:(GlassesWiFiHandlerStatusCallback)statusCallback
                    completion:(GlassesWiFiHandlerConnectionCallback)completion;

- (void)cancelCurrentOperation;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
