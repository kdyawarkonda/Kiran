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
@class QGStateManager;

@protocol QGUIColumnsManagerDelegate <NSObject>

@optional
- (void)columnsManager:(QGUIColumnsManager *)manager didSelectAction:(NSInteger)actionType;
- (void)columnsManager:(QGUIColumnsManager *)manager didRequestMediaInfoRefresh:(void(^)(void))completion;

@end

typedef NS_ENUM(NSInteger, QGDeviceActionType) {
    /// Get hardware version, firmware version, and WiFi firmware versions
    QGDeviceActionTypeGetVersion = 0,

    /// Sync the device time with the phone
    QGDeviceActionTypeTimeSync,

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

    /// Take AI Image (trigger only - display handled separately)
    QGDeviceActionTypeToggleTakeAIImage,

    /// System reboot with multiple options
    QGDeviceActionTypeSystemReboot,

    /// Wearing detection status
    QGDeviceActionTypeWearingDetection,

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
@property (nonatomic, assign) BOOL stateManagementEnabled;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)reloadData;
- (void)setHidden:(BOOL)hidden;
- (NSString *)titleForActionType:(QGDeviceActionType)actionType;
- (NSString *)detailTextForActionType:(QGDeviceActionType)actionType;

// State Management - Direct access to QStateManager
@property (nonatomic, strong) QGStateManager *stateManager;
- (void)setupStateManagerWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
