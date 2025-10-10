#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Represents normalized error codes surfaced by the glasses SDK demo.
 */
typedef NS_ENUM(NSInteger, QGSDKErrorCode) {
    QGSDKErrorCodeUnknown = 1000,
    QGSDKErrorCodeInitializationFailed = 1001,
    QGSDKErrorCodeNetworkUnavailable = 1002,
    QGSDKErrorCodeTimeout = 1003,
    QGSDKErrorCodeInvalidParameters = 1004,
    QGSDKErrorCodeUserNotLoggedIn = 2001,
    QGSDKErrorCodeTokenExpired = 2002,
    QGSDKErrorCodeFileUploadFailed = 3001,
    QGSDKErrorCodeUnsupportedOperation = 3002,
    QGSDKErrorCodeModeConflict = 4001,
    QGSDKErrorCodeBluetoothPoweredOff = 5001,
    QGSDKErrorCodePeripheralMissing = 5002,
    QGSDKErrorCodeConnectionFailed = 5003,
    QGSDKErrorCodeDeviceNotReady = 5004
};

FOUNDATION_EXPORT NSString * const QGSDKErrorDomain;

/// Creates an NSError populated with the standardized error domain, description, and optional metadata.
FOUNDATION_EXPORT NSError *QGSDKErrorMake(QGSDKErrorCode code,
                                          NSString * _Nullable context,
                                          NSError * _Nullable underlyingError,
                                          NSDictionary * _Nullable extraUserInfo);

/// Maps a raw SDK numeric error into the normalized NSError form.
FOUNDATION_EXPORT NSError *QGSDKErrorFromSDKCode(NSInteger sdkCode, NSString * _Nullable context);

/// Convenience constructor for timeout scenarios.
FOUNDATION_EXPORT NSError *QGSDKTimeoutError(NSString * _Nullable context);

/// Convenience constructor for command rejections caused by conflicting device mode.
FOUNDATION_EXPORT NSError *QGSDKModeConflictError(NSInteger currentMode, NSString * _Nullable context);

/// Bluetooth powered-off helper.
FOUNDATION_EXPORT NSError *QGSDKBluetoothPoweredOffError(void);

/// Peripheral missing helper (typically when the CBPeripheral reference can no longer be found).
FOUNDATION_EXPORT NSError *QGSDKPeripheralMissingError(void);

/// Generic connection failure helper.
FOUNDATION_EXPORT NSError *QGSDKConnectionFailedError(NSString * _Nullable context);

/// Wraps an arbitrary NSError (or nil) to ensure it uses the shared domain/code metadata.
FOUNDATION_EXPORT NSError *QGSDKWrapError(NSError * _Nullable error,
                                          NSString * _Nullable context,
                                          QGSDKErrorCode fallbackCode);

/// Returns the best end-user facing message for the error, falling back to domain defaults.
FOUNDATION_EXPORT NSString *QGSDKErrorDisplayMessage(NSError *error);

NS_ASSUME_NONNULL_END
