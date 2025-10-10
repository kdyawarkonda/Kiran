//
//  GlassesWiFiHandler.m
//  QCSDKDemo
//
//  Implements a serialized workflow for enabling Wi-Fi transfer on the
//  glasses. The handler requests credentials via BLE, configures the
//  NEHotspotConfiguration, waits for association, and probes the network to
//  determine the device IP without relying on hardcoded values.
//

#import "GlassesWiFiHandler.h"

#import <NetworkExtension/NetworkExtension.h>
#import <SystemConfiguration/CaptiveNetwork.h>

#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

#import <QCSDK/QCSDKCmdCreator.h>

static NSString * const GlassesWiFiHandlerErrorDomain = @"GlassesWiFiHandlerError";
static NSTimeInterval const kAssociationPollInterval = 1.0;
static NSUInteger const kAssociationMaxAttempts = 10;
static NSTimeInterval const kProbeTimeout = 1.5;
static NSUInteger const kManualJoinMaxAttempts = 8;
static NSTimeInterval const kManualJoinRetryDelay = 3.0;

@interface GlassesWiFiHandler ()

@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, assign) GlassesWiFiHandlerState state;
@property (nonatomic, copy) NSString *glassesSSID;
@property (nonatomic, copy) NSString *glassesPassword;
@property (nonatomic, copy) GlassesWiFiHandlerStatusCallback statusCallback;
@property (nonatomic, copy) GlassesWiFiHandlerCredentialsCallback credentialsCallback;
@property (nonatomic, copy) GlassesWiFiHandlerConnectionCallback connectionCallback;
@property (nonatomic, strong) NSURLSession *probeSession;
@property (nonatomic, assign) BOOL usingManualJoinFallback;
@property (nonatomic, assign) NSUInteger manualJoinAttempts;
@property (nonatomic, copy) NSString *manualJoinInstructions;
@property (nonatomic, assign) NSUInteger hotspotConfigurationRetryCount;

@end

@implementation GlassesWiFiHandler

+ (instancetype)sharedHandler {
    static GlassesWiFiHandler *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GlassesWiFiHandler alloc] initPrivate];
    });
    return sharedInstance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INITIATED,
                                                                             0);
        _workQueue = dispatch_queue_create("com.heyycyan.qcsdk.glasseswifi", attr);
        _state = GlassesWiFiHandlerStateIdle;

        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.allowsCellularAccess = NO;
        configuration.connectionProxyDictionary = @{};
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.timeoutIntervalForRequest = kProbeTimeout;
        configuration.timeoutIntervalForResource = kProbeTimeout;
        if (@available(iOS 11.0, *)) {
            configuration.waitsForConnectivity = NO;
        }
        if (@available(iOS 13.0, *)) {
            configuration.allowsExpensiveNetworkAccess = NO;
            configuration.allowsConstrainedNetworkAccess = NO;
        }
        _probeSession = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (instancetype)init {
    [NSException raise:NSInternalInconsistencyException format:@"Use sharedHandler instead of init"];
    return nil;
}

#pragma mark - Public API

- (void)requestWiFiCredentialsWithStatusCallback:(GlassesWiFiHandlerStatusCallback)statusCallback
                                      completion:(GlassesWiFiHandlerCredentialsCallback)completion {
    dispatch_async(self.workQueue, ^{
        if (self.state != GlassesWiFiHandlerStateIdle) {
            NSError *error = [self errorWithCode:-1 description:@"Wi-Fi handler busy"];
            [self deliverCredentialCompletionWithSSID:@"" password:@"" error:error];
            return;
        }

        self.state = GlassesWiFiHandlerStateRequestingCredentials;
        self.statusCallback = [statusCallback copy];
        self.credentialsCallback = [completion copy];

        [self publishStatus:@"Preparing glasses for Wi-Fi transfer..." state:self.state];

        __weak typeof(self) weakSelf = self;
        void (^requestCredentials)(void) = ^{
            [QCSDKCmdCreator openWifiWithMode:QCOperatorDeviceModeTransfer success:^(NSString *ssid, NSString *password) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) { return; }

                dispatch_async(strongSelf.workQueue, ^{
                    strongSelf.glassesSSID = ssid ?: @"";
                    // Use the provided password when available, but fall back to the
                    // known default if the device returns nothing.
                    if (password.length > 0) {
                        strongSelf.glassesPassword = password;
                    } else {
                        strongSelf.glassesPassword = @"123456789";
                    }

                    [strongSelf publishStatus:[NSString stringWithFormat:@"Received SSID %@", strongSelf.glassesSSID.length > 0 ? strongSelf.glassesSSID : @"<unknown>"]
                                        state:GlassesWiFiHandlerStateRequestingCredentials];

                    [strongSelf deliverCredentialCompletionWithSSID:strongSelf.glassesSSID
                                                            password:strongSelf.glassesPassword
                                                               error:nil];
                    strongSelf.state = GlassesWiFiHandlerStateIdle;
                    strongSelf.statusCallback = nil;
                    strongSelf.credentialsCallback = nil;
                });
            } fail:^(NSInteger code) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) { return; }

                dispatch_async(strongSelf.workQueue, ^{
                    NSError *error = [strongSelf errorWithCode:code
                                                   description:[NSString stringWithFormat:@"Failed to request Wi-Fi credentials (code %ld)", (long)code]];
                    [strongSelf publishStatus:error.localizedDescription state:GlassesWiFiHandlerStateFailed];
                    [strongSelf deliverCredentialCompletionWithSSID:@"" password:@"" error:error];
                    [strongSelf resetInternal];
                });
            }];
        };

        [QCSDKCmdCreator setDeviceMode:QCOperatorDeviceModeTransfer success:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            dispatch_async(strongSelf.workQueue, ^{
                [strongSelf publishStatus:@"Requesting Wi-Fi credentials from glasses..."
                                   state:GlassesWiFiHandlerStateRequestingCredentials];
            });
            requestCredentials();
        } fail:^(NSInteger code) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            dispatch_async(strongSelf.workQueue, ^{
                NSError *error = [strongSelf errorWithCode:code
                                               description:[NSString stringWithFormat:@"Failed to set transfer mode (code %ld)", (long)code]];
                [strongSelf publishStatus:error.localizedDescription state:GlassesWiFiHandlerStateFailed];
                [strongSelf deliverCredentialCompletionWithSSID:@"" password:@"" error:error];
                [strongSelf resetInternal];
            });
        }];
    });
}

- (void)connectToGlassesWiFi:(NSString *)ssid
                     password:(NSString *)password
               statusCallback:(GlassesWiFiHandlerStatusCallback)statusCallback
                    completion:(GlassesWiFiHandlerConnectionCallback)completion {
    dispatch_async(self.workQueue, ^{
        if (self.state != GlassesWiFiHandlerStateIdle) {
            NSError *error = [self errorWithCode:-1 description:@"Wi-Fi handler busy"];
            [self deliverConnectionCompletionWithSuccess:NO ip:nil error:error];
            return;
        }

        self.state = GlassesWiFiHandlerStateConfiguring;
        self.glassesSSID = ssid ?: @"";
        self.glassesPassword = password ?: @"";
        self.statusCallback = [statusCallback copy];
        self.connectionCallback = [completion copy];
        self.hotspotConfigurationRetryCount = 0;

        [self applyHotspotConfigurationWithJoinOnce:YES];
    });
}

- (void)cancelCurrentOperation {
    dispatch_async(self.workQueue, ^{
        [self publishStatus:@"Operation cancelled" state:GlassesWiFiHandlerStateFailed];
        [self deliverCredentialCompletionWithSSID:@"" password:@"" error:[self errorWithCode:-2 description:@"Cancelled"]];
        [self deliverConnectionCompletionWithSuccess:NO ip:nil error:[self errorWithCode:-2 description:@"Cancelled"]];
        [self resetInternal];
    });
}

- (void)applyHotspotConfigurationWithJoinOnce:(BOOL)joinOnce {
    if (self.glassesSSID.length == 0) {
        NSError *error = [self errorWithCode:-7 description:@"Missing hotspot SSID."];
        [self publishStatus:error.localizedDescription state:GlassesWiFiHandlerStateFailed];
        [self deliverConnectionCompletionWithSuccess:NO ip:nil error:error];
        [self resetInternal];
        return;
    }

    self.state = GlassesWiFiHandlerStateConfiguring;
    NSString *status = joinOnce ? @"Configuring hotspot (temporary)..." : @"Configuring hotspot (persistent)...";
    [self publishStatus:status state:self.state];

    NEHotspotConfiguration *configuration = nil;
    if (self.glassesPassword.length > 0) {
        configuration = [[NEHotspotConfiguration alloc] initWithSSID:self.glassesSSID
                                                          passphrase:self.glassesPassword
                                                              isWEP:NO];
    } else {
        configuration = [[NEHotspotConfiguration alloc] initWithSSID:self.glassesSSID];
    }
    configuration.joinOnce = joinOnce;
    if (@available(iOS 13.0, *)) {
        configuration.lifeTimeInDays = @1;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 11.0, *)) {
            [[NEHotspotConfigurationManager sharedManager] removeConfigurationForSSID:self.glassesSSID];
        }

        [[NEHotspotConfigurationManager sharedManager] applyConfiguration:configuration
                                                         completionHandler:^(NSError * _Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            dispatch_async(strongSelf.workQueue, ^{
                if (!error || error.code == NEHotspotConfigurationErrorAlreadyAssociated) {
                    [strongSelf publishStatus:@"Hotspot configured. Waiting for association..."
                                         state:GlassesWiFiHandlerStateWaitingForAssociation];
                    [strongSelf waitForAssociationAttempt:0];
                } else {
                    NSError *handlerError = [strongSelf wrapNEError:error fallbackMessage:@"Unable to configure hotspot."];
                    NSLog(@"[GlassesWiFiHandler] Hotspot configuration failed (attempt %lu): %@ (%ld)", (unsigned long)strongSelf.hotspotConfigurationRetryCount, handlerError.localizedDescription, (long)handlerError.code);

                    if ([handlerError.domain isEqualToString:NEHotspotConfigurationErrorDomain] &&
                        [strongSelf retryHotspotConfigurationAfterError:handlerError]) {
                        return;
                    }

                    if ([handlerError.domain isEqualToString:NEHotspotConfigurationErrorDomain]) {
                        [strongSelf startManualJoinFallbackWithError:handlerError];
                    } else {
                        [strongSelf publishStatus:handlerError.localizedDescription state:GlassesWiFiHandlerStateFailed];
                        [strongSelf deliverConnectionCompletionWithSuccess:NO ip:nil error:handlerError];
                        [strongSelf resetInternal];
                    }
                }
            });
        }];
    });
}

- (void)reset {
    dispatch_async(self.workQueue, ^{
        [self resetInternal];
    });
}

#pragma mark - Association & Probing

- (void)waitForAssociationAttempt:(NSUInteger)attempt {
    if (attempt >= kAssociationMaxAttempts) {
        NSError *error = [self errorWithCode:-3 description:@"Timed out waiting for hotspot association."];
        [self publishStatus:error.localizedDescription state:GlassesWiFiHandlerStateFailed];
        [self deliverConnectionCompletionWithSuccess:NO ip:nil error:error];
        [self resetInternal];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [QCSDKCmdCreator getDeviceWifiIPSuccess:^(NSString * _Nullable ipAddress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            NSString *normalizedIP = [strongSelf normalizedIPv4AddressFromString:ipAddress];
            if (normalizedIP.length > 0) {
                __weak typeof(strongSelf) weakInner = strongSelf;
                [strongSelf validatedAssociationForAttempt:attempt
                                                onFailure:nil
                                                 onSuccess:^{
                    __strong typeof(weakInner) innerStrong = weakInner;
                    if (!innerStrong) { return; }
                    [innerStrong publishStatus:[NSString stringWithFormat:@"Detected glasses IP %@. Verifying...", normalizedIP]
                                          state:GlassesWiFiHandlerStateResolvingIP];
                    [innerStrong probeCandidates:@[normalizedIP] allowFallback:NO];
                }];
            } else {
                [strongSelf scheduleAssociationRetryFromLocalInterfaceForAttempt:attempt];
            }
        });
    } failed:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            [strongSelf scheduleAssociationRetryFromLocalInterfaceForAttempt:attempt];
        });
    }];
}

- (BOOL)retryHotspotConfigurationAfterError:(NSError *)error {
    if (self.hotspotConfigurationRetryCount == 0) {
        self.hotspotConfigurationRetryCount = 1;
        NSString *message = [NSString stringWithFormat:@"Hotspot configuration failed (%@). Retrying with persistent join...",
                              error.localizedDescription ?: @"unknown error"];
        [self publishStatus:message state:GlassesWiFiHandlerStateConfiguring];

        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), self.workQueue, ^{
            [weakSelf applyHotspotConfigurationWithJoinOnce:NO];
        });
        return YES;
    }

    if (self.hotspotConfigurationRetryCount == 1) {
        self.hotspotConfigurationRetryCount = 2;
        NSString *message = [NSString stringWithFormat:@"Hotspot retry failed (%@). Trying again...",
                              error.localizedDescription ?: @"unknown error"];
        [self publishStatus:message state:GlassesWiFiHandlerStateConfiguring];

        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), self.workQueue, ^{
            [weakSelf applyHotspotConfigurationWithJoinOnce:YES];
        });
        return YES;
    }

    return NO;
}

- (void)scheduleAssociationRetryFromLocalInterfaceForAttempt:(NSUInteger)attempt {
    NSString *localAddress = [self currentWiFiInterfaceIPv4Address];
    NSString *normalizedLocal = [self normalizedIPv4AddressFromString:localAddress];

    if (normalizedLocal.length > 0) {
        __weak typeof(self) weakSelf = self;
        [self validatedAssociationForAttempt:attempt
                                    onFailure:nil
                                     onSuccess:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            [strongSelf publishStatus:@"Verifying hotspot connection..." state:GlassesWiFiHandlerStateResolvingIP];
            [strongSelf deriveDeviceIPAddressFromLocalInterface];
        }];
        return;
    }

    [self rescheduleAssociationAttempt:attempt];
}

- (void)startManualJoinFallbackWithError:(NSError *)error {
    self.usingManualJoinFallback = YES;
    self.manualJoinAttempts = 0;
    self.state = GlassesWiFiHandlerStateWaitingForAssociation;

    if (@available(iOS 11.0, *)) {
        [[NEHotspotConfigurationManager sharedManager] removeConfigurationForSSID:self.glassesSSID ?: @""];
    }

    NSMutableString *message = [NSMutableString stringWithFormat:@"Automatic Wi-Fi setup isn't available (%@).\n1. Open Settings > Wi-Fi\n2. Join %@",
                                error.localizedDescription ?: @"unknown error",
                                self.glassesSSID ?: @"the glasses hotspot"];
    if (self.glassesPassword.length > 0) {
        [message appendFormat:@"\n   Password: %@", self.glassesPassword];
    }
    [message appendString:@"\n3. Return to this app to continue"];

    self.manualJoinInstructions = message.copy;
    [self publishStatus:self.manualJoinInstructions state:self.state];
    [self scheduleManualJoinCheck];
}

- (void)scheduleManualJoinCheck {
    if (!self.usingManualJoinFallback) {
        return;
    }

    if (self.manualJoinAttempts >= kManualJoinMaxAttempts) {
        self.usingManualJoinFallback = NO;
        NSError *failure = [self errorWithCode:-6 description:@"Unable to detect glasses hotspot. Please ensure you joined it in Settings and try again."];
        [self publishStatus:failure.localizedDescription state:GlassesWiFiHandlerStateFailed];
        [self deliverConnectionCompletionWithSuccess:NO ip:nil error:failure];
        [self resetInternal];
        return;
    }

    NSTimeInterval delay = (self.manualJoinAttempts == 0) ? 4.0 : kManualJoinRetryDelay;
    self.manualJoinAttempts += 1;

    NSString *status = self.manualJoinInstructions ?: @"Waiting for glasses hotspot connection...";
    NSString *statusWithAttempt = [status stringByAppendingFormat:@"\nChecking connection... (%lu/%lu)", (unsigned long)self.manualJoinAttempts, (unsigned long)kManualJoinMaxAttempts];
    [self publishStatus:statusWithAttempt state:GlassesWiFiHandlerStateWaitingForAssociation];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.workQueue, ^{
        [self attemptManualJoinCheck];
    });
}

- (void)attemptManualJoinCheck {
    if (!self.usingManualJoinFallback) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [QCSDKCmdCreator getDeviceWifiIPSuccess:^(NSString * _Nullable ipAddress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            if (!strongSelf.usingManualJoinFallback) {
                return;
            }

            NSString *normalizedIP = [strongSelf normalizedIPv4AddressFromString:ipAddress];
            __weak typeof(strongSelf) weakInner = strongSelf;

            if (normalizedIP.length > 0) {
                [strongSelf validatedAssociationForAttempt:strongSelf.manualJoinAttempts
                                                onFailure:^{
                    __strong typeof(weakInner) innerStrong = weakInner;
                    if (!innerStrong) { return; }
                    NSString *status = innerStrong.manualJoinInstructions ?: @"Waiting for glasses hotspot connection...";
                    [innerStrong publishStatus:status state:GlassesWiFiHandlerStateWaitingForAssociation];
                    [innerStrong scheduleManualJoinCheck];
                }
                                                 onSuccess:^{
                    __strong typeof(weakInner) innerStrong = weakInner;
                    if (!innerStrong) { return; }
                    innerStrong.usingManualJoinFallback = NO;
                    [innerStrong publishStatus:[NSString stringWithFormat:@"Detected device at %@. Verifying connection...", normalizedIP]
                                           state:GlassesWiFiHandlerStateResolvingIP];
                    [innerStrong probeCandidates:@[normalizedIP] allowFallback:NO];
                }];
            } else {
                [strongSelf validatedAssociationForAttempt:strongSelf.manualJoinAttempts
                                                onFailure:^{
                    __strong typeof(weakInner) innerStrong = weakInner;
                    if (!innerStrong) { return; }
                    NSString *status = innerStrong.manualJoinInstructions ?: @"Waiting for glasses hotspot connection...";
                    [innerStrong publishStatus:status state:GlassesWiFiHandlerStateWaitingForAssociation];
                    [innerStrong scheduleManualJoinCheck];
                }
                                                 onSuccess:^{
                    __strong typeof(weakInner) innerStrong = weakInner;
                    if (!innerStrong) { return; }
                    NSString *status = innerStrong.manualJoinInstructions ?: @"Waiting for glasses hotspot connection...";
                    [innerStrong publishStatus:status state:GlassesWiFiHandlerStateWaitingForAssociation];
                    [innerStrong scheduleManualJoinCheck];
                }];
            }
        });
    } failed:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            if (!strongSelf.usingManualJoinFallback) {
                return;
            }

            __weak typeof(strongSelf) weakInner = strongSelf;
            [strongSelf validatedAssociationForAttempt:strongSelf.manualJoinAttempts
                                            onFailure:^{
                __strong typeof(weakInner) innerStrong = weakInner;
                if (!innerStrong) { return; }
                NSString *status = innerStrong.manualJoinInstructions ?: @"Waiting for glasses hotspot connection...";
                [innerStrong publishStatus:status state:GlassesWiFiHandlerStateWaitingForAssociation];
                [innerStrong scheduleManualJoinCheck];
            }
                                             onSuccess:^{
                __strong typeof(weakInner) innerStrong = weakInner;
                if (!innerStrong) { return; }
                NSString *status = innerStrong.manualJoinInstructions ?: @"Waiting for glasses hotspot connection...";
                [innerStrong publishStatus:status state:GlassesWiFiHandlerStateWaitingForAssociation];
                [innerStrong scheduleManualJoinCheck];
            }];
        });
    }];
}

- (void)resolveDeviceIPAddress {
    __weak typeof(self) weakSelf = self;

    // First try to ask the SDK for the device IP (BLE still available immediately after switch).
    [QCSDKCmdCreator getDeviceWifiIPSuccess:^(NSString * _Nullable ipAddress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            NSString *normalizedIP = [strongSelf normalizedIPv4AddressFromString:ipAddress];
            if (normalizedIP.length > 0) {
                __weak typeof(strongSelf) weakInner = strongSelf;
                [strongSelf validatedAssociationForAttempt:0
                                                onFailure:nil
                                                 onSuccess:^{
                    __strong typeof(weakInner) innerStrong = weakInner;
                    if (!innerStrong) { return; }
                    [innerStrong publishStatus:[NSString stringWithFormat:@"Device reported IP %@", normalizedIP]
                                          state:GlassesWiFiHandlerStateResolvingIP];
                    [innerStrong probeCandidates:@[normalizedIP] allowFallback:NO];
                }];
            } else {
                [strongSelf deriveDeviceIPAddressFromLocalInterface];
            }
        });
    } failed:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            [strongSelf deriveDeviceIPAddressFromLocalInterface];
        });
    }];
}

- (void)deriveDeviceIPAddressFromLocalInterface {
    NSString *localAddress = [self currentWiFiInterfaceIPv4Address];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (localAddress.length > 0) {
        NSArray<NSString *> *derived = [self candidateIPsForLocalAddress:localAddress];
        [candidates addObjectsFromArray:derived];
    }

    // Add limited fallback IPs as a last resort.
    NSArray *fallbacks = @[ @"192.168.43.1", @"192.168.4.1", @"192.168.31.1", @"192.168.1.1", @"192.168.0.1", @"192.168.100.1" ];
    for (NSString *ip in fallbacks) {
        if (![candidates containsObject:ip]) {
            [candidates addObject:ip];
        }
    }

    if (candidates.count == 0) {
        NSError *error = [self errorWithCode:-4 description:@"Unable to determine device IP address."];
        [self publishStatus:error.localizedDescription state:GlassesWiFiHandlerStateFailed];
        [self deliverConnectionCompletionWithSuccess:NO ip:nil error:error];
        [self resetInternal];
        return;
    }

    [self probeCandidates:candidates];
}

- (void)probeCandidates:(NSArray<NSString *> *)candidateIPs {
    [self probeCandidates:candidateIPs allowFallback:YES];
}

- (void)probeCandidates:(NSArray<NSString *> *)candidateIPs allowFallback:(BOOL)allowFallback {
    if (candidateIPs.count == 0) {
        NSError *error = [self errorWithCode:-5 description:@"Device did not respond on known IPs."];
        [self publishStatus:error.localizedDescription state:GlassesWiFiHandlerStateFailed];
        [self deliverConnectionCompletionWithSuccess:NO ip:nil error:error];
        [self resetInternal];
        return;
    }

    __weak typeof(self) weakSelf = self;
    __block NSUInteger index = 0;

    void (^probeNext)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        if (index >= candidateIPs.count) {
            NSError *error = [strongSelf errorWithCode:-5 description:@"Device did not respond on known IPs."];
            [strongSelf publishStatus:error.localizedDescription state:GlassesWiFiHandlerStateFailed];
            [strongSelf deliverConnectionCompletionWithSuccess:NO ip:nil error:error];
            [strongSelf resetInternal];
            return;
        }

        NSString *ip = candidateIPs[index++];
        NSString *urlString = [NSString stringWithFormat:@"http://%@/files/media.config", ip];
        NSURL *url = [NSURL URLWithString:urlString];
        NSURLRequest *request = [NSURLRequest requestWithURL:url
                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                            timeoutInterval:kProbeTimeout];

        [strongSelf publishStatus:[NSString stringWithFormat:@"Probing %@", ip]
                             state:GlassesWiFiHandlerStateResolvingIP];

        NSURLSessionDataTask *task = [strongSelf.probeSession dataTaskWithRequest:request
                                                               completionHandler:^(NSData * _Nullable data,
                                                                                   NSURLResponse * _Nullable response,
                                                                                   NSError * _Nullable error) {
            __strong typeof(weakSelf) innerStrongSelf = weakSelf;
            if (!innerStrongSelf) { return; }

            BOOL success = NO;
            if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
                success = (status >= 200 && status < 300);
            }

            dispatch_async(innerStrongSelf.workQueue, ^{
                if (success) {
                    NSString *normalizedIP = [innerStrongSelf normalizedIPv4AddressFromString:ip];
                    if (normalizedIP.length == 0) {
                        probeNext();
                        return;
                    }
                    innerStrongSelf.state = GlassesWiFiHandlerStateConnected;
                    [innerStrongSelf publishStatus:[NSString stringWithFormat:@"Connected to %@", normalizedIP]
                                             state:innerStrongSelf.state];
                    [innerStrongSelf deliverConnectionCompletionWithSuccess:YES ip:normalizedIP error:nil];
                    [innerStrongSelf resetInternal];
                } else {
                    if (!allowFallback) {
                        NSError *networkError = error ?: [innerStrongSelf errorWithCode:-10 description:@"Unable to reach glasses hotspot. Confirm the phone is connected to the glasses Wi-Fi network." ];
                        [innerStrongSelf publishStatus:networkError.localizedDescription state:GlassesWiFiHandlerStateFailed];
                        [innerStrongSelf deliverConnectionCompletionWithSuccess:NO ip:nil error:networkError];
                        [innerStrongSelf resetInternal];
                    } else {
                        probeNext();
                    }
                }
            });
        }];
        [task resume];
    };

    probeNext();
}

#pragma mark - Association Helpers

- (void)rescheduleAssociationAttempt:(NSUInteger)attempt {
    NSTimeInterval delay = kAssociationPollInterval;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.workQueue, ^{
        [self waitForAssociationAttempt:attempt + 1];
    });
}

- (void)validatedAssociationForAttempt:(NSUInteger)attempt
                             onFailure:(dispatch_block_t)failure
                              onSuccess:(dispatch_block_t)success {
    if (self.glassesSSID.length == 0) {
        if (success) { success(); }
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self fetchCurrentSSID:^(NSString * _Nullable ssid) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            if (ssid.length > 0 && ![ssid isEqualToString:strongSelf.glassesSSID]) {
                NSString *message = [NSString stringWithFormat:@"Connected to %@. Join %@ hotspot to continue.",
                                      ssid,
                                      strongSelf.glassesSSID ?: @"the glasses hotspot"];
                [strongSelf publishStatus:message state:GlassesWiFiHandlerStateWaitingForAssociation];

                if (failure) {
                    failure();
                } else {
                    [strongSelf rescheduleAssociationAttempt:attempt];
                }
                return;
            }

            if (success) {
                success();
            }
        });
    }];
}

#pragma mark - Helpers

- (void)publishStatus:(NSString *)status state:(GlassesWiFiHandlerState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.statusCallback) {
            self.statusCallback(state, status, nil);
        }
    });
}

- (void)deliverCredentialCompletionWithSSID:(NSString *)ssid password:(NSString *)password error:(NSError * _Nullable)error {
    if (!self.credentialsCallback) { return; }
    GlassesWiFiHandlerCredentialsCallback callback = self.credentialsCallback;
    self.credentialsCallback = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(ssid, password, error);
    });
}

- (void)deliverConnectionCompletionWithSuccess:(BOOL)success ip:(NSString * _Nullable)ip error:(NSError * _Nullable)error {
    if (!self.connectionCallback) { return; }
    GlassesWiFiHandlerConnectionCallback callback = self.connectionCallback;
    self.connectionCallback = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(success, ip, error);
    });
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:GlassesWiFiHandlerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : description ?: @"Unknown error"}];
}

- (NSError *)wrapNEError:(NSError *)error fallbackMessage:(NSString *)fallback {
    if (!error) {
        return [self errorWithCode:-999 description:fallback];
    }

    if ([error.domain isEqualToString:NEHotspotConfigurationErrorDomain]) {
        return error;
    }

    return [self errorWithCode:error.code description:(error.localizedDescription ?: fallback)];
}

- (NSString *)normalizedIPv4AddressFromString:(NSString *)candidate {
    if (candidate.length == 0) {
        return @"";
    }

    NSError *regexError = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([0-9]{1,3}\\.){3}[0-9]{1,3}"
                                                                           options:0
                                                                             error:&regexError];
    if (regexError) {
        return candidate;
    }

    NSTextCheckingResult *match = [regex firstMatchInString:candidate options:0 range:NSMakeRange(0, candidate.length)];
    if (!match) {
        return @"";
    }

    NSString *ip = [candidate substringWithRange:match.range];
    NSArray<NSString *> *components = [ip componentsSeparatedByString:@"."];
    if (components.count != 4) {
        return @"";
    }

    NSMutableArray<NSString *> *mutableComponents = [components mutableCopy];
    BOOL (^isLocalOctet)(NSInteger) = ^BOOL(NSInteger value) {
        return value == 10 || value == 192 || value == 172;
    };

    NSInteger firstValue = mutableComponents[0].integerValue;
    if (firstValue < 0 || firstValue > 255) {
        return @"";
    }

    if (!isLocalOctet(firstValue)) {
        NSUInteger targetIndex = NSNotFound;
        for (NSUInteger idx = 1; idx < mutableComponents.count; idx++) {
            NSInteger candidateValue = mutableComponents[idx].integerValue;
            if (candidateValue < 0 || candidateValue > 255) {
                return @"";
            }
            if (isLocalOctet(candidateValue)) {
                targetIndex = idx;
                break;
            }
        }

        if (targetIndex != NSNotFound) {
            NSArray<NSString *> *tail = [mutableComponents subarrayWithRange:NSMakeRange(targetIndex, mutableComponents.count - targetIndex)];
            NSArray<NSString *> *head = [mutableComponents subarrayWithRange:NSMakeRange(0, targetIndex)];
            mutableComponents = [[tail arrayByAddingObjectsFromArray:head] mutableCopy];
        }
    } else {
        for (NSUInteger idx = 1; idx < mutableComponents.count; idx++) {
            NSInteger candidateValue = mutableComponents[idx].integerValue;
            if (candidateValue < 0 || candidateValue > 255) {
                return @"";
            }
        }
    }

    return [mutableComponents componentsJoinedByString:@"."];
}

- (void)resetInternal {
    self.state = GlassesWiFiHandlerStateIdle;
    self.glassesSSID = @"";
    self.glassesPassword = @"";
    self.statusCallback = nil;
   self.credentialsCallback = nil;
   self.connectionCallback = nil;
   self.usingManualJoinFallback = NO;
   self.manualJoinAttempts = 0;
   self.manualJoinInstructions = nil;
    self.hotspotConfigurationRetryCount = 0;
}

- (void)fetchCurrentSSID:(void (^)(NSString * _Nullable ssid))completion {
    if (@available(iOS 14.0, *)) {
        [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable currentNetwork) {
            completion(currentNetwork.SSID);
        }];
    } else {
        NSString *ssid = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFArrayRef interfaces = CNCopySupportedInterfaces();
        if (interfaces != nil) {
            CFDictionaryRef networkInfo = CNCopyCurrentNetworkInfo(CFArrayGetValueAtIndex(interfaces, 0));
            if (networkInfo != nil) {
                NSDictionary *info = (__bridge_transfer NSDictionary *)networkInfo;
                ssid = info[(__bridge NSString *)kCNNetworkInfoKeySSID];
            }
            CFRelease(interfaces);
        }
#pragma clang diagnostic pop
        completion(ssid);
    }
}

- (NSString *)currentWiFiInterfaceIPv4Address {
    struct ifaddrs *interfaces = NULL;
    NSString *result = nil;

    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp = interfaces;
        while (temp != NULL) {
            if ((temp->ifa_flags & IFF_UP) && temp->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp->ifa_name];
                if ([name isEqualToString:@"en0"] || [name hasPrefix:@"en"]) {
                    char addrBuf[INET_ADDRSTRLEN];
                    struct sockaddr_in *addr = (struct sockaddr_in *)temp->ifa_addr;
                    const char *cAddr = inet_ntop(AF_INET, &addr->sin_addr, addrBuf, sizeof(addrBuf));
                    if (cAddr) {
                        result = [NSString stringWithUTF8String:cAddr];
                        break;
                    }
                }
            }
            temp = temp->ifa_next;
        }
        freeifaddrs(interfaces);
    }

    return result;
}

- (NSArray<NSString *> *)candidateIPsForLocalAddress:(NSString *)localAddress {
    NSArray<NSString *> *parts = [localAddress componentsSeparatedByString:@"."];
    if (parts.count != 4) {
        return @[];
    }

    NSString *base = [NSString stringWithFormat:@"%@.%@.%@.", parts[0], parts[1], parts[2]];

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    [candidates addObject:[base stringByAppendingString:@"1"]];
    [candidates addObject:[base stringByAppendingString:@"254"]];

    NSInteger lastOctet = [parts[3] integerValue];
    if (lastOctet > 1 && lastOctet < 254) {
        [candidates addObject:[base stringByAppendingFormat:@"%ld", (long)(lastOctet - 1)]];
        [candidates addObject:[base stringByAppendingFormat:@"%ld", (long)(lastOctet + 1)]];
    }

    return candidates;
}

@end
