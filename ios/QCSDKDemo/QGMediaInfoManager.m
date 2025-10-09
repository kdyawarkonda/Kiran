//
//  QGMediaInfoManager.m
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import "QGMediaInfoManager.h"
#import <QCSDK/QCSDKCmdCreator.h>

// Error domain
static NSString * const kQGMediaInfoErrorDomain = @"QGMediaInfoErrorDomain";

// Error codes
typedef NS_ENUM(NSInteger, QGMediaInfoErrorCode) {
    QGMediaInfoErrorCodeDeviceNotConnected = 1001,
    QGMediaInfoErrorCodeSDKCommandFailed = 1002,
    QGMediaInfoErrorCodeInvalidResponse = 1003,
};

@implementation QGMediaInfo

- (instancetype)initWithPhotoCount:(NSInteger)photoCount
                        videoCount:(NSInteger)videoCount
                        audioCount:(NSInteger)audioCount
                         totalSize:(NSInteger)totalSize {
    self = [super init];
    if (self) {
        _photoCount = photoCount;
        _videoCount = videoCount;
        _audioCount = audioCount;
        _totalSize = totalSize;
    }
    return self;
}

- (NSString *)formattedDescription {
    return [NSString stringWithFormat:@"Photos: %ld, Videos: %ld, Audio: %ld",
            (long)self.photoCount, (long)self.videoCount, (long)self.audioCount];
}

- (NSString *)detailedDescription {
    return [NSString stringWithFormat:@"Media Information:\nPhotos: %ld\nVideos: %ld\nAudio: %ld\nTotal Size: %ld bytes",
            (long)self.photoCount, (long)self.videoCount, (long)self.audioCount, (long)self.totalSize];
}

@end

@interface QGMediaInfoManager ()

@property (nonatomic, strong) QGMediaInfo *cachedMediaInfo;
@property (nonatomic, assign) NSTimeInterval lastUpdateTime;

@end

@implementation QGMediaInfoManager

+ (instancetype)shared {
    static QGMediaInfoManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[QGMediaInfoManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastUpdateTime = 0;
        _cachedMediaInfo = nil;
    }
    return self;
}

- (void)getMediaInfoWithCompletion:(void (^)(QGMediaInfo *_Nullable mediaInfo, NSError *_Nullable error))completion {
    // Check if device is connected (basic check)
    if (![self isDeviceReady]) {
        NSError *error = [NSError errorWithDomain:kQGMediaInfoErrorDomain
                                             code:QGMediaInfoErrorCodeDeviceNotConnected
                                         userInfo:@{NSLocalizedDescriptionKey: @"Device not connected or not ready"}];
        if (completion) completion(nil, error);
        return;
    }

    NSLog(@"[QGMediaInfoManager] Requesting media information from device...");

    [QCSDKCmdCreator getDeviceMedia:^(NSInteger photo, NSInteger video, NSInteger audio, NSInteger totalSize) {
        NSLog(@"[QGMediaInfoManager] Received media info - Photos: %ld, Videos: %ld, Audio: %ld, Total Size: %ld",
              (long)photo, (long)video, (long)audio, (long)totalSize);

        // Validate response
        if (photo < 0 || video < 0 || audio < 0 || totalSize < 0) {
            NSError *error = [NSError errorWithDomain:kQGMediaInfoErrorDomain
                                                 code:QGMediaInfoErrorCodeInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid media data received from device"}];
            if (completion) completion(nil, error);
            return;
        }

        // Create and cache media info
        QGMediaInfo *mediaInfo = [[QGMediaInfo alloc] initWithPhotoCount:photo
                                                              videoCount:video
                                                              audioCount:audio
                                                               totalSize:totalSize];

        self.cachedMediaInfo = mediaInfo;
        self.lastUpdateTime = [[NSDate date] timeIntervalSince1970];

        if (completion) completion(mediaInfo, nil);

    } fail:^{
        NSLog(@"[QGMediaInfoManager] Failed to get media information from device");

        NSError *error = [NSError errorWithDomain:kQGMediaInfoErrorDomain
                                             code:QGMediaInfoErrorCodeSDKCommandFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to retrieve media information from device"}];
        if (completion) completion(nil, error);
    }];
}

- (void)getFormattedMediaCountWithCompletion:(void (^)(NSString *_Nullable formattedString, NSError *_Nullable error))completion {
    [self getMediaInfoWithCompletion:^(QGMediaInfo *mediaInfo, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        NSString *formattedString = [mediaInfo formattedDescription];
        if (completion) completion(formattedString, nil);
    }];
}

- (void)hasAnyMediaWithCompletion:(void (^)(BOOL hasMedia, NSError *_Nullable error))completion {
    [self getMediaInfoWithCompletion:^(QGMediaInfo *mediaInfo, NSError *error) {
        if (error) {
            if (completion) completion(NO, error);
            return;
        }

        BOOL hasMedia = (mediaInfo.photoCount > 0 || mediaInfo.videoCount > 0 || mediaInfo.audioCount > 0);
        if (completion) completion(hasMedia, nil);
    }];
}

#pragma mark - Private Methods

- (BOOL)isDeviceReady {
    // This is a basic implementation - in a real scenario, you might want to check
    // the actual connection state through QCCentralManager or QCSDKManager
    return YES; // For now, assume device is ready if method is called
}

- (BOOL)isCacheValid {
    // Cache is valid for 30 seconds
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    return (self.cachedMediaInfo && (currentTime - self.lastUpdateTime) < 30.0);
}

@end