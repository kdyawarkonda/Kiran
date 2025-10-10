//
//  QGStateManager.h
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QGStateManager;

@protocol QGStateManagerDelegate <NSObject>

@optional
- (void)stateManager:(QGStateManager *)manager didSaveState:(NSDictionary *)state;
- (void)stateManager:(QGStateManager *)manager didRestoreState:(NSDictionary *)state;
- (void)stateManager:(QGStateManager *)manager didFailWithError:(NSError *)error;

@end

typedef NS_ENUM(NSInteger, QGStateStorageLocation) {
    QGStateStorageLocationUserDefaults = 0,
    QGStateStorageLocationDocuments,
    QGStateStorageLocationCaches,
    QGStateStorageLocationTemporary
};

typedef NS_ENUM(NSInteger, QGStateValidationResult) {
    QGStateValidationResultValid = 0,
    QGStateValidationResultInvalidFormat,
    QGStateValidationResultVersionMismatch,
    QGStateValidationResultCorruptedData
};

@interface QGStateManager : NSObject

@property (nonatomic, weak) id<QGStateManagerDelegate> delegate;
@property (nonatomic, assign) QGStateStorageLocation storageLocation;
@property (nonatomic, copy) NSString *stateIdentifier;
@property (nonatomic, assign) BOOL autoSaveEnabled;
@property (nonatomic, assign) NSTimeInterval autoSaveInterval;

// State Management
- (instancetype)initWithIdentifier:(NSString *)identifier storageLocation:(QGStateStorageLocation)location;
- (BOOL)saveState:(NSDictionary *)state error:(NSError **)error;
- (nullable NSDictionary *)restoreStateWithError:(NSError **)error;
- (BOOL)hasSavedState;
- (void)clearSavedState;

// Automatic State Management
- (void)enableAutoSave;
- (void)disableAutoSave;
- (void)startAutoSaveTimer;
- (void)stopAutoSaveTimer;

// State Validation
- (QGStateValidationResult)validateState:(NSDictionary *)state;
- (BOOL)isStateVersionCompatible:(NSString *)version;
- (NSDictionary *)sanitizeState:(NSDictionary *)state;

// Utility Methods
- (NSString *)storagePath;
- (NSDate *)lastSavedDate;
- (NSInteger)savedStateSize;
- (void)migrateStateFromVersion:(NSString *)fromVersion toVersion:(NSString *)toVersion;

// Device-specific State Management
- (BOOL)saveDeviceState:(NSDictionary *)deviceState error:(NSError **)error;
- (nullable NSDictionary *)restoreDeviceStateWithError:(NSError **)error;
- (BOOL)saveUIState:(NSDictionary *)uiState error:(NSError **)error;
- (nullable NSDictionary *)restoreUIStateWithError:(NSError **)error;

// Backup and Recovery
- (BOOL)createBackupOfCurrentState:(NSError **)error;
- (NSArray<NSString *> *)availableBackups;
- (BOOL)restoreFromBackup:(NSString *)backupName error:(NSError **)error;
- (void)cleanupOldBackups;

@end

NS_ASSUME_NONNULL_END