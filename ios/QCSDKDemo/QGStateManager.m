//
//  QGStateManager.m
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import "QGStateManager.h"

// Auto-save interval
static NSTimeInterval const kDefaultAutoSaveInterval = 30.0;

@interface QGStateManager ()

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *values;
@property (nonatomic, strong) NSTimer *autoSaveTimer;
@property (nonatomic, strong) NSDate *lastSaveDate;

@end

@implementation QGStateManager

#pragma mark - Initialization

- (instancetype)initWithIdentifier:(NSString *)identifier storageLocation:(QGStateStorageLocation)location {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _storageLocation = location;
        _autoSaveInterval = kDefaultAutoSaveInterval;
        _autoSaveEnabled = NO;
        _values = [NSMutableDictionary dictionary];

        // Try to load existing data
        [self load];
    }
    return self;
}

- (instancetype)init {
    return [self initWithIdentifier:@"default" storageLocation:QGStateStorageLocationUserDefaults];
}

- (void)dealloc {
    [self disableAutoSave];
}

#pragma mark - Simple Key-Value State Management

- (void)setValue:(id)value forKey:(NSString *)key {
    if (!key || key.length == 0) {
        return;
    }

    if (value) {
        self.values[key] = value;
    } else {
        [self removeValueForKey:key];
    }

    if (self.autoSaveEnabled) {
        [self scheduleAutoSave];
    }
}

- (id)valueForKey:(NSString *)key {
    if (!key || key.length == 0) {
        return nil;
    }

    return self.values[key];
}

- (void)removeValueForKey:(NSString *)key {
    if (!key || key.length == 0) {
        return;
    }

    [self.values removeObjectForKey:key];

    if (self.autoSaveEnabled) {
        [self scheduleAutoSave];
    }
}

- (void)clearAllValues {
    [self.values removeAllObjects];

    if (self.autoSaveEnabled) {
        [self scheduleAutoSave];
    }
}

#pragma mark - Batch Operations

- (void)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dictionary {
    if (!dictionary) {
        return;
    }

    [self.values addEntriesFromDictionary:dictionary];

    if (self.autoSaveEnabled) {
        [self scheduleAutoSave];
    }
}

- (NSDictionary<NSString *, id> *)allValues {
    return [self.values copy];
}

#pragma mark - Persistence

- (BOOL)save {
    if (self.values.count == 0) {
        // Nothing to save
        return YES;
    }

    BOOL success = [self writeValuesToStorage];
    if (success) {
        self.lastSaveDate = [NSDate date];
    }

    return success;
}

- (BOOL)load {
    NSDictionary *loadedValues = [self readValuesFromStorage];
    if (loadedValues) {
        [self.values addEntriesFromDictionary:loadedValues];
        self.lastSaveDate = [NSDate date];
        return YES;
    }

    return NO;
}

- (BOOL)hasSavedData {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        return [[NSUserDefaults standardUserDefaults] objectForKey:self.identifier] != nil;
    } else {
        NSString *storagePath = [self storagePath];
        return [[NSFileManager defaultManager] fileExistsAtPath:storagePath];
    }
}

- (void)clearSavedData {
    [self clearAllValues];
    [self deleteSavedData];
    self.lastSaveDate = nil;
}

#pragma mark - Auto-save

- (void)enableAutoSave {
    self.autoSaveEnabled = YES;
}

- (void)disableAutoSave {
    self.autoSaveEnabled = NO;
    [self stopAutoSaveTimer];
}

- (void)scheduleAutoSave {
    // Debounce auto-save with a short delay
    [self stopAutoSaveTimer];

    self.autoSaveTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(autoSaveTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)autoSaveTimerFired:(NSTimer *)timer {
    if (self.autoSaveEnabled) {
        [self save];
    }
}

- (void)stopAutoSaveTimer {
    if (self.autoSaveTimer) {
        [self.autoSaveTimer invalidate];
        self.autoSaveTimer = nil;
    }
}

#pragma mark - Utility

- (NSDate *)lastSavedDate {
    return self.lastSaveDate;
}

- (NSInteger)dataSize {
    if (self.values.count == 0) {
        return 0;
    }

    NSData *data = [NSPropertyListSerialization
                    dataWithPropertyList:self.values
                    format:NSPropertyListBinaryFormat_v1_0
                    options:0
                    error:nil];

    return data ? data.length : 0;
}

#pragma mark - Private Methods

- (NSString *)storagePath {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        return nil; // Use NSUserDefaults directly
    }

    NSString *baseDirectory;
    switch (self.storageLocation) {
        case QGStateStorageLocationDocuments:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            break;
        case QGStateStorageLocationCaches:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            break;
        default:
            baseDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            break;
    }

    return [baseDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_state.plist", self.identifier]];
}

- (BOOL)writeValuesToStorage {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        [[NSUserDefaults standardUserDefaults] setObject:self.values forKey:self.identifier];
        return [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSString *storagePath = [self storagePath];
        return [self.values writeToFile:storagePath atomically:YES];
    }
}

- (nullable NSDictionary *)readValuesFromStorage {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        return [[NSUserDefaults standardUserDefaults] dictionaryForKey:self.identifier];
    } else {
        NSString *storagePath = [self storagePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:storagePath]) {
            return [NSDictionary dictionaryWithContentsOfFile:storagePath];
        }
        return nil;
    }
}

- (void)deleteSavedData {
    if (self.storageLocation == QGStateStorageLocationUserDefaults) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:self.identifier];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSString *storagePath = [self storagePath];
        [[NSFileManager defaultManager] removeItemAtPath:storagePath error:nil];
    }
}

@end