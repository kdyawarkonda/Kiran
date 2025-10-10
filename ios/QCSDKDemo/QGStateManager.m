//
//  QGStateManager.m
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import "QGStateManager.h"

// State storage keys
static NSString * const kQGStateManagerVersionKey = @"version";
static NSString * const kQGStateManagerTimestampKey = @"timestamp";
static NSString * const kQGStateManagerDeviceStateKey = @"deviceState";
static NSString * const kQGStateManagerUIStateKey = @"uiState";
static NSString * const kQGStateManagerMetadataKey = @"metadata";
static NSString * const kQGStateManagerCurrentVersion = @"1.0.0";

// Auto save timer
static NSTimeInterval const kQGStateManagerDefaultAutoSaveInterval = 30.0;

@interface QGStateManager ()

@property (nonatomic, strong) NSTimer *autoSaveTimer;
@property (nonatomic, strong) NSMutableDictionary *currentPendingState;
@property (nonatomic, copy) NSString *currentVersion;

@end

@implementation QGStateManager

#pragma mark - Initialization

- (instancetype)initWithIdentifier:(NSString *)identifier storageLocation:(QGStateStorageLocation)location {
    self = [super init];
    if (self) {
        _stateIdentifier = [identifier copy];
        _storageLocation = location;
        _autoSaveEnabled = NO;
        _autoSaveInterval = kQGStateManagerDefaultAutoSaveInterval;
        _currentVersion = kQGStateManagerCurrentVersion;
        _currentPendingState = [NSMutableDictionary dictionary];

        [self createStorageDirectoryIfNeeded];
    }
    return self;
}

- (instancetype)init {
    return [self initWithIdentifier:@"default" storageLocation:QGStateStorageLocationUserDefaults];
}

- (void)dealloc {
    [self stopAutoSaveTimer];
}

#pragma mark - State Management

- (BOOL)saveState:(NSDictionary *)state error:(NSError **)error {
    if (!state || ![state isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [self errorWithCode:400 description:@"Invalid state provided"];
        }
        return NO;
    }

    // Validate state before saving
    QGStateValidationResult validationResult = [self validateState:state];
    if (validationResult != QGStateValidationResultValid) {
        if (error) {
            *error = [self errorWithCode:401 description:[NSString stringWithFormat:@"State validation failed: %ld", (long)validationResult]];
        }
        return NO;
    }

    // Prepare state for storage
    NSMutableDictionary *stateToSave = [state mutableCopy];
    stateToSave[kQGStateManagerVersionKey] = self.currentVersion;
    stateToSave[kQGStateManagerTimestampKey] = [NSDate date];

    // Add metadata
    NSDictionary *metadata = [self generateMetadata];
    stateToSave[kQGStateManagerMetadataKey] = metadata;

    @try {
        BOOL success = [self writeStateToStorage:stateToSave error:error];
        if (success && [self.delegate respondsToSelector:@selector(stateManager:didSaveState:)]) {
            [self.delegate stateManager:self didSaveState:state];
        }
        return success;
    } @catch (NSException *exception) {
        if (error) {
            *error = [self errorWithCode:500 description:[NSString stringWithFormat:@"Exception during save: %@", exception.reason]];
        }
        return NO;
    }
}

- (nullable NSDictionary *)restoreStateWithError:(NSError **)error {
    @try {
        NSDictionary *savedState = [self readStateFromStorage:error];
        if (!savedState) {
            return nil;
        }

        // Validate loaded state
        QGStateValidationResult validationResult = [self validateState:savedState];
        if (validationResult != QGStateValidationResultValid) {
            if (error) {
                *error = [self errorWithCode:402 description:[NSString stringWithFormat:@"Loaded state validation failed: %ld", (long)validationResult]];
            }
            return nil;
        }

        // Check version compatibility
        NSString *stateVersion = savedState[kQGStateManagerVersionKey];
        if (![self isStateVersionCompatible:stateVersion]) {
            // Attempt migration
            NSDictionary *migratedState = [self migrateStateFromVersion:stateVersion toVersion:self.currentVersion];
            if (migratedState) {
                savedState = migratedState;
                // Save the migrated state
                [self saveState:migratedState error:nil];
            } else {
                if (error) {
                    *error = [self errorWithCode:403 description:@"State version not compatible and migration failed"];
                }
                return nil;
            }
        }

        NSDictionary *cleanState = [self sanitizeState:savedState];
        if ([self.delegate respondsToSelector:@selector(stateManager:didRestoreState:)]) {
            [self.delegate stateManager:self didRestoreState:cleanState];
        }

        return cleanState;
    } @catch (NSException *exception) {
        if (error) {
            *error = [self errorWithCode:501 description:[NSString stringWithFormat:@"Exception during restore: %@", exception.reason]];
        }
        return nil;
    }
}

- (BOOL)hasSavedState {
    NSString *storagePath = [self storagePath];
    return [[NSFileManager defaultManager] fileExistsAtPath:storagePath];
}

- (void)clearSavedState {
    NSString *storagePath = [self storagePath];
    [[NSFileManager defaultManager] removeItemAtPath:storagePath error:nil];

    [self.currentPendingState removeAllObjects];
    [self stopAutoSaveTimer];
}

#pragma mark - Automatic State Management

- (void)enableAutoSave {
    self.autoSaveEnabled = YES;
    [self startAutoSaveTimer];
}

- (void)disableAutoSave {
    self.autoSaveEnabled = NO;
    [self stopAutoSaveTimer];
}

- (void)startAutoSaveTimer {
    [self stopAutoSaveTimer];

    if (self.autoSaveEnabled && self.autoSaveInterval > 0) {
        self.autoSaveTimer = [NSTimer scheduledTimerWithTimeInterval:self.autoSaveInterval
                                                             target:self
                                                           selector:@selector(autoSaveTimerFired:)
                                                           userInfo:nil
                                                            repeats:YES];
    }
}

- (void)stopAutoSaveTimer {
    if (self.autoSaveTimer) {
        [self.autoSaveTimer invalidate];
        self.autoSaveTimer = nil;
    }
}

- (void)autoSaveTimerFired:(NSTimer *)timer {
    if (self.autoSaveEnabled && self.currentPendingState.count > 0) {
        NSError *error;
        BOOL success = [self saveState:self.currentPendingState error:&error];
        if (!success && error && [self.delegate respondsToSelector:@selector(stateManager:didFailWithError:)]) {
            [self.delegate stateManager:self didFailWithError:error];
        }

        [self.currentPendingState removeAllObjects];
    }
}

- (void)queueStateForAutoSave:(NSDictionary *)state {
    if (self.autoSaveEnabled) {
        [self.currentPendingState addEntriesFromDictionary:state];

        if (!self.autoSaveTimer) {
            [self startAutoSaveTimer];
        }
    }
}

#pragma mark - State Validation

- (QGStateValidationResult)validateState:(NSDictionary *)state {
    if (!state || ![state isKindOfClass:[NSDictionary class]]) {
        return QGStateValidationResultInvalidFormat;
    }

    // Check required keys
    NSArray *requiredKeys = @[@"deviceState", @"uiState"];
    for (NSString *key in requiredKeys) {
        if (!state[key]) {
            return QGStateValidationResultInvalidFormat;
        }
    }

    // Validate version
    NSString *version = state[kQGStateManagerVersionKey];
    if (!version || ![self isStateVersionCompatible:version]) {
        return QGStateValidationResultVersionMismatch;
    }

    // Validate timestamp
    id timestamp = state[kQGStateManagerTimestampKey];
    if (timestamp && ![timestamp isKindOfClass:[NSDate class]]) {
        return QGStateValidationResultInvalidFormat;
    }

    return QGStateValidationResultValid;
}

- (BOOL)isStateVersionCompatible:(NSString *)version {
    if (!version) return YES; // No version means old format, assume compatible

    // Simple version compatibility check
    NSArray *currentComponents = [self.currentVersion componentsSeparatedByString:@"."];
    NSArray *stateComponents = [version componentsSeparatedByString:@"."];

    // Major version must match
    if (currentComponents.count > 0 && stateComponents.count > 0) {
        NSString *currentMajor = currentComponents[0];
        NSString *stateMajor = stateComponents[0];
        return [currentMajor isEqualToString:stateMajor];
    }

    return YES;
}

- (NSDictionary *)sanitizeState:(NSDictionary *)state {
    NSMutableDictionary *sanitized = [state mutableCopy];

    // Remove internal keys
    [sanitized removeObjectForKey:kQGStateManagerTimestampKey];
    [sanitized removeObjectForKey:kQGStateManagerMetadataKey];

    return [sanitized copy];
}

#pragma mark - Device-specific State Management

- (BOOL)saveDeviceState:(NSDictionary *)deviceState error:(NSError **)error {
    NSDictionary *currentState = [self loadCurrentState];
    NSMutableDictionary *updatedState = [currentState mutableCopy];
    updatedState[kQGStateManagerDeviceStateKey] = deviceState;

    return [self saveState:updatedState error:error];
}

- (nullable NSDictionary *)restoreDeviceStateWithError:(NSError **)error {
    NSDictionary *currentState = [self restoreStateWithError:error];
    return currentState[kQGStateManagerDeviceStateKey];
}

- (BOOL)saveUIState:(NSDictionary *)uiState error:(NSError **)error {
    NSDictionary *currentState = [self loadCurrentState];
    NSMutableDictionary *updatedState = [currentState mutableCopy];
    updatedState[kQGStateManagerUIStateKey] = uiState;

    return [self saveState:updatedState error:error];
}

- (nullable NSDictionary *)restoreUIStateWithError:(NSError **)error {
    NSDictionary *currentState = [self restoreStateWithError:error];
    return currentState[kQGStateManagerUIStateKey];
}

#pragma mark - Utility Methods

- (NSString *)storagePath {
    NSString *baseDirectory;

    switch (self.storageLocation) {
        case QGStateStorageLocationUserDefaults:
            return nil; // Use NSUserDefaults directly

        case QGStateStorageLocationDocuments:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            break;

        case QGStateStorageLocationCaches:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            break;

        case QGStateStorageLocationTemporary:
            baseDirectory = NSTemporaryDirectory();
            break;
    }

    if (baseDirectory) {
        return [baseDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_state.plist", self.stateIdentifier]];
    }

    return nil;
}

- (NSDate *)lastSavedDate {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        NSDictionary *state = [[NSUserDefaults standardUserDefaults] dictionaryForKey:self.stateIdentifier];
        return state[kQGStateManagerTimestampKey];
    } else {
        NSString *storagePath = [self storagePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:storagePath]) {
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:storagePath error:nil];
            return attributes[NSFileModificationDate];
        }
    }
    return nil;
}

- (NSInteger)savedStateSize {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        NSDictionary *state = [[NSUserDefaults standardUserDefaults] dictionaryForKey:self.stateIdentifier];
        if (state) {
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            return data.length;
        }
    } else {
        NSString *storagePath = [self storagePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:storagePath]) {
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:storagePath error:nil];
            return [attributes[NSFileSize] integerValue];
        }
    }
    return 0;
}

- (void)migrateStateFromVersion:(NSString *)fromVersion toVersion:(NSString *)toVersion {
    // Implementation for state migration
    // This would handle specific migration logic between versions
    NSLog(@"Migrating state from version %@ to %@", fromVersion, toVersion);
}

#pragma mark - Backup and Recovery

- (BOOL)createBackupOfCurrentState:(NSError **)error {
    NSString *backupPath = [self backupPathWithName:[self currentBackupName]];
    NSString *storagePath = [self storagePath];

    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        NSDictionary *state = [[NSUserDefaults standardUserDefaults] dictionaryForKey:self.stateIdentifier];
        return [state writeToFile:backupPath atomically:YES];
    } else {
        return [[NSFileManager defaultManager] copyItemAtPath:storagePath toPath:backupPath error:error];
    }
}

- (NSArray<NSString *> *)availableBackups {
    NSString *backupDirectory = [self backupDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:backupDirectory error:nil];

    NSMutableArray *backupNames = [NSMutableArray array];
    for (NSString *file in files) {
        if ([file hasPrefix:[NSString stringWithFormat:@"%@_backup_", self.stateIdentifier]]) {
            [backupNames addObject:file];
        }
    }

    return [backupNames copy];
}

- (BOOL)restoreFromBackup:(NSString *)backupName error:(NSError **)error {
    NSString *backupPath = [self backupPathWithName:backupName];
    NSString *storagePath = [self storagePath];

    return [[NSFileManager defaultManager] copyItemAtPath:backupPath toPath:storagePath error:error];
}

- (void)cleanupOldBackups {
    NSArray *backups = [self availableBackups];
    NSString *backupDirectory = [self backupDirectory];

    // Keep only the 5 most recent backups
    NSArray *sortedBackups = [backups sortedArrayUsingComparator:^NSComparisonResult(NSString *name1, NSString *name2) {
        NSString *path1 = [backupDirectory stringByAppendingPathComponent:name1];
        NSString *path2 = [backupDirectory stringByAppendingPathComponent:name2];

        NSDictionary *attr1 = [[NSFileManager defaultManager] attributesOfItemAtPath:path1 error:nil];
        NSDictionary *attr2 = [[NSFileManager defaultManager] attributesOfItemAtPath:path2 error:nil];

        return [attr2[NSFileModificationDate] compare:attr1[NSFileModificationDate]];
    }];

    for (NSInteger i = 5; i < sortedBackups.count; i++) {
        NSString *backupPath = [backupDirectory stringByAppendingPathComponent:sortedBackups[i]];
        [[NSFileManager defaultManager] removeItemAtPath:backupPath error:nil];
    }
}

#pragma mark - Private Methods

- (BOOL)writeStateToStorage:(NSDictionary *)state error:(NSError **)error {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        [[NSUserDefaults standardUserDefaults] setObject:state forKey:self.stateIdentifier];
        return [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSString *storagePath = [self storagePath];
        return [state writeToFile:storagePath atomically:YES];
    }
}

- (nullable NSDictionary *)readStateFromStorage:(NSError **)error {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        return [[NSUserDefaults standardUserDefaults] dictionaryForKey:self.stateIdentifier];
    } else {
        NSString *storagePath = [self storagePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:storagePath]) {
            return [NSDictionary dictionaryWithContentsOfFile:storagePath];
        }
        return nil;
    }
}

- (NSDictionary *)loadCurrentState {
    NSError *error;
    return [self restoreStateWithError:&error] ?: @{};
}

- (void)createStorageDirectoryIfNeeded {
    if (self.storageLocation != QGStateStorageLocationUserDefaults) {
        NSString *storagePath = [self storagePath];
        NSString *directory = [storagePath stringByDeletingLastPathComponent];

        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
}

- (NSDictionary *)generateMetadata {
    return @{
        @"platform": @"iOS",
        @"deviceModel": [[UIDevice currentDevice] model],
        @"systemVersion": [[UIDevice currentDevice] systemVersion],
        @"appVersion": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown"
    };
}

- (NSString *)backupDirectory {
    NSString *baseDirectory;

    switch (self.storageLocation) {
        case QGStateStorageLocationDocuments:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            break;
        case QGStateStorageLocationCaches:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            break;
        case QGStateStorageLocationTemporary:
            baseDirectory = NSTemporaryDirectory();
            break;
        default:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            break;
    }

    NSString *backupDir = [baseDirectory stringByAppendingPathComponent:@"QGStateBackups"];
    [[NSFileManager defaultManager] createDirectoryAtPath:backupDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    return backupDir;
}

- (NSString *)backupPathWithName:(NSString *)backupName {
    NSString *backupDirectory = [self backupDirectory];
    return [backupDirectory stringByAppendingPathComponent:backupName];
}

- (NSString *)currentBackupName {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];

    return [NSString stringWithFormat:@"%@_backup_%@.plist", self.stateIdentifier, timestamp];
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:@"QGStateManagerErrorDomain"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@end