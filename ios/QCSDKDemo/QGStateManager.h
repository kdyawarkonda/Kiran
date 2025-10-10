//
//  QGStateManager.h
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Simple generic state manager for key-value data storage
 * Completely decoupled from any specific business logic
 */

typedef NS_ENUM(NSInteger, QGStateStorageLocation) {
    QGStateStorageLocationUserDefaults = 0,
    QGStateStorageLocationDocuments,
    QGStateStorageLocationCaches
};

@interface QGStateManager : NSObject

// Configuration
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign) QGStateStorageLocation storageLocation;
@property (nonatomic, assign) BOOL autoSaveEnabled;
@property (nonatomic, assign) NSTimeInterval autoSaveInterval;

// Initialization
- (instancetype)initWithIdentifier:(NSString *)identifier storageLocation:(QGStateStorageLocation)location;

// Simple Key-Value State Management
- (void)setValue:(id _Nullable)value forKey:(NSString *)key;
- (id _Nullable)valueForKey:(NSString *)key;
- (void)removeValueForKey:(NSString *)key;
- (void)clearAllValues;

// Batch Operations
- (void)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dictionary;
- (NSDictionary<NSString *, id> *)allValues;

// Persistence
- (BOOL)save;
- (BOOL)load;
- (BOOL)hasSavedData;
- (void)clearSavedData;

// Auto-save
- (void)enableAutoSave;
- (void)disableAutoSave;

// Utility
- (NSDate *)lastSavedDate;
- (NSInteger)dataSize;

@end

NS_ASSUME_NONNULL_END