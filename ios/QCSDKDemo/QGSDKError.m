#import "QGSDKError.h"

NSString * const QGSDKErrorDomain = @"com.heycyan.glasses.sdkdemo.error";

static NSString * const QGSDKErrorContextKey = @"context";
static NSString * const QGSDKErrorSDKCodeKey = @"sdk_code";
static NSString * const QGSDKErrorCurrentModeKey = @"current_mode";

static NSDictionary<NSNumber *, NSString *> *QGSDKErrorBaselineDescriptions(void) {
    static NSDictionary<NSNumber *, NSString *> *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @{
            @(QGSDKErrorCodeUnknown): @"An unknown error occurred.",
            @(QGSDKErrorCodeInitializationFailed): @"Initialization failed. Verify credentials and try again.",
            @(QGSDKErrorCodeNetworkUnavailable): @"Network is unavailable. Check the glasses connectivity.",
            @(QGSDKErrorCodeTimeout): @"The request timed out. Please retry.",
            @(QGSDKErrorCodeInvalidParameters): @"Invalid parameters were provided.",
            @(QGSDKErrorCodeUserNotLoggedIn): @"User session is missing. Log in before retrying.",
            @(QGSDKErrorCodeTokenExpired): @"Session token expired. Re-authenticate to continue.",
            @(QGSDKErrorCodeFileUploadFailed): @"File upload failed. Check format and permissions.",
            @(QGSDKErrorCodeUnsupportedOperation): @"Operation not supported on the current firmware.",
            @(QGSDKErrorCodeModeConflict): @"Device is busy with another task.",
            @(QGSDKErrorCodeBluetoothPoweredOff): @"Bluetooth is powered off. Turn it on to continue.",
            @(QGSDKErrorCodePeripheralMissing): @"The device reference is no longer available.",
            @(QGSDKErrorCodeConnectionFailed): @"Failed to establish a connection with the device.",
            @(QGSDKErrorCodeDeviceNotReady): @"Device is not ready to process the request."
        };
    });
    return table;
}

static NSString *QGSDKDefaultMessageForCode(QGSDKErrorCode code) {
    NSString *message = QGSDKErrorBaselineDescriptions()[@(code)];
    return message ?: QGSDKErrorBaselineDescriptions()[@(QGSDKErrorCodeUnknown)];
}

NSError *QGSDKErrorMake(QGSDKErrorCode code,
                        NSString * _Nullable context,
                        NSError * _Nullable underlyingError,
                        NSDictionary * _Nullable extraUserInfo) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (extraUserInfo.count) {
        [userInfo addEntriesFromDictionary:extraUserInfo];
    }

    if (context.length) {
        userInfo[QGSDKErrorContextKey] = context;
    }

    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
        NSString *existingDescription = [userInfo[NSLocalizedDescriptionKey] isKindOfClass:[NSString class]]
            ? userInfo[NSLocalizedDescriptionKey]
            : nil;
        if (!existingDescription.length && underlyingError.localizedDescription.length) {
            userInfo[NSLocalizedDescriptionKey] = underlyingError.localizedDescription;
        }
    }

    if (!userInfo[NSLocalizedDescriptionKey]) {
        userInfo[NSLocalizedDescriptionKey] = QGSDKDefaultMessageForCode(code);
    }

    return [NSError errorWithDomain:QGSDKErrorDomain code:code userInfo:userInfo];
}

NSError *QGSDKErrorFromSDKCode(NSInteger sdkCode, NSString * _Nullable context) {
    QGSDKErrorCode mappedCode = QGSDKErrorCodeUnknown;
    switch (sdkCode) {
        case 1000: mappedCode = QGSDKErrorCodeUnknown; break;
        case 1001: mappedCode = QGSDKErrorCodeInitializationFailed; break;
        case 1002: mappedCode = QGSDKErrorCodeNetworkUnavailable; break;
        case 1003: mappedCode = QGSDKErrorCodeTimeout; break;
        case 1004: mappedCode = QGSDKErrorCodeInvalidParameters; break;
        case 2001: mappedCode = QGSDKErrorCodeUserNotLoggedIn; break;
        case 2002: mappedCode = QGSDKErrorCodeTokenExpired; break;
        case 3001: mappedCode = QGSDKErrorCodeFileUploadFailed; break;
        case 3002: mappedCode = QGSDKErrorCodeUnsupportedOperation; break;
        default:
            mappedCode = QGSDKErrorCodeUnknown;
            break;
    }

    return QGSDKErrorMake(mappedCode,
                          context,
                          nil,
                          @{ QGSDKErrorSDKCodeKey : @(sdkCode) });
}

NSError *QGSDKTimeoutError(NSString * _Nullable context) {
    return QGSDKErrorMake(QGSDKErrorCodeTimeout, context, nil, nil);
}

NSError *QGSDKModeConflictError(NSInteger currentMode, NSString * _Nullable context) {
    NSString *message = [NSString stringWithFormat:@"Device rejected the request because it is busy (mode %ld).",
                         (long)currentMode];
    return QGSDKErrorMake(QGSDKErrorCodeModeConflict,
                          context,
                          nil,
                          @{ QGSDKErrorCurrentModeKey : @(currentMode),
                             NSLocalizedDescriptionKey : message });
}

NSError *QGSDKBluetoothPoweredOffError(void) {
    return QGSDKErrorMake(QGSDKErrorCodeBluetoothPoweredOff,
                          @"bluetooth_state",
                          nil,
                          nil);
}

NSError *QGSDKPeripheralMissingError(void) {
    return QGSDKErrorMake(QGSDKErrorCodePeripheralMissing,
                          @"peripheral_lookup",
                          nil,
                          nil);
}

NSError *QGSDKConnectionFailedError(NSString * _Nullable context) {
    return QGSDKErrorMake(QGSDKErrorCodeConnectionFailed, context, nil, nil);
}

NSError *QGSDKWrapError(NSError * _Nullable error,
                        NSString * _Nullable context,
                        QGSDKErrorCode fallbackCode) {
    if (!error) {
        return QGSDKErrorMake(fallbackCode, context, nil, nil);
    }

    if ([error.domain isEqualToString:QGSDKErrorDomain]) {
        NSMutableDictionary *userInfo = error.userInfo.mutableCopy ?: [NSMutableDictionary dictionary];
        if (context.length) {
            userInfo[QGSDKErrorContextKey] = context;
        }
        return [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (error.localizedDescription.length) {
        userInfo[NSLocalizedDescriptionKey] = error.localizedDescription;
    }
    return QGSDKErrorMake(fallbackCode, context, error, userInfo);
}

NSString *QGSDKErrorDisplayMessage(NSError *error) {
    if (!error) {
        return @"";
    }

    NSString *message = error.userInfo[NSLocalizedDescriptionKey];
    if (message.length) {
        return message;
    }

    if ([error.domain isEqualToString:QGSDKErrorDomain]) {
        return QGSDKDefaultMessageForCode((QGSDKErrorCode)error.code);
    }

    return error.localizedDescription.length ? error.localizedDescription : QGSDKDefaultMessageForCode(QGSDKErrorCodeUnknown);
}
