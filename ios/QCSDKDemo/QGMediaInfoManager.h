//
//  QGMediaInfoManager.h
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Media information data model
@interface QGMediaInfo : NSObject

@property (nonatomic, assign) NSInteger photoCount;
@property (nonatomic, assign) NSInteger videoCount;
@property (nonatomic, assign) NSInteger audioCount;
@property (nonatomic, assign) NSInteger totalSize;

- (instancetype)initWithPhotoCount:(NSInteger)photoCount
                        videoCount:(NSInteger)videoCount
                        audioCount:(NSInteger)audioCount
                         totalSize:(NSInteger)totalSize;

- (NSString *)formattedDescription;
- (NSString *)detailedDescription;

@end

/// Manager for handling media information operations
@interface QGMediaInfoManager : NSObject

+ (instancetype)shared;

/// Get current media information from device
/// @param completion Completion block with QGMediaInfo object or error
- (void)getMediaInfoWithCompletion:(void (^)(QGMediaInfo *_Nullable mediaInfo, NSError *_Nullable error))completion;

/// Get formatted media count string for display
/// @param completion Completion block with formatted string or error
- (void)getFormattedMediaCountWithCompletion:(void (^)(NSString *_Nullable formattedString, NSError *_Nullable error))completion;

/// Check if device has any media
/// @param completion Completion block with boolean result and error
- (void)hasAnyMediaWithCompletion:(void (^)(BOOL hasMedia, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END