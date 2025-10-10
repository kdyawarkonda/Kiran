//
//  QGUIColumnsManager.h
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class QGUIColumnsManager;
@class QGMediaInfo;

@protocol QGUIColumnsManagerDelegate <NSObject>

@optional
- (void)columnsManager:(QGUIColumnsManager *)manager didSelectAction:(NSInteger)actionType;
- (void)columnsManager:(QGUIColumnsManager *)manager didRequestMediaInfoRefresh:(void(^)(void))completion;
- (void)columnsManager:(QGUIColumnsManager *)manager didSelectAIImage:(NSData *)imageData;

@end

typedef NS_ENUM(NSInteger, QGDeviceActionType) {
    /// Get hardware version, firmware version, and WiFi firmware versions
    QGDeviceActionTypeGetVersion = 0,

    /// Set the current device time
    QGDeviceActionTypeSetTime,

    /// Get battery level and charging status
    QGDeviceActionTypeGetBattery,

    /// Get the number of photos, videos, and audio files on the device
    QGDeviceActionTypeGetMediaInfo,

    /// Trigger the device to take a photo
    QGDeviceActionTypeTakePhoto,

    /// Start or stop video recording
    QGDeviceActionTypeToggleVideoRecording,

    /// Start or stop audio recording
    QGDeviceActionTypeToggleAudioRecording,

    /// Take AI Image
    QGDeviceActionTypeToggleTakeAIImage,

    /// Reserved for future use
    QGDeviceActionTypeReserved,
};

@interface QGUIColumnsManager : NSObject

@property (nonatomic, weak) id<QGUIColumnsManagerDelegate> delegate;
@property (nonatomic, strong, readonly) UITableView *tableView;

// Device data properties
@property (nonatomic, copy) NSString *hardVersion;
@property (nonatomic, copy) NSString *firmVersion;
@property (nonatomic, copy) NSString *hardWiFiVersion;
@property (nonatomic, copy) NSString *firmWiFiVersion;
@property (nonatomic, copy) NSString *mac;
@property (nonatomic, assign) NSInteger battery;
@property (nonatomic, assign) BOOL charging;
@property (nonatomic, strong) QGMediaInfo *currentMediaInfo;
@property (nonatomic, assign) BOOL isLoadingMediaInfo;
@property (nonatomic, copy) NSString *mediaInfoError;
@property (nonatomic, assign) BOOL recordingVideo;
@property (nonatomic, assign) BOOL recordingAudio;
@property (nonatomic, strong) NSData *aiImageData;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)reloadData;
- (void)setHidden:(BOOL)hidden;
- (NSString *)titleForActionType:(QGDeviceActionType)actionType;
- (NSString *)detailTextForActionType:(QGDeviceActionType)actionType;
- (void)clearAIImage;

@end

NS_ASSUME_NONNULL_END