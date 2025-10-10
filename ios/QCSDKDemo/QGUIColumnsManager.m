//
//  QGUIColumnsManager.m
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import "QGUIColumnsManager.h"
#import "QGMediaInfoManager.h"
#import "QGStateManager.h"

@interface QGUIColumnsManager () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong, readwrite) UITableView *tableView;

@end

@implementation QGUIColumnsManager

#pragma mark - Initialization

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        [self setupTableViewWithFrame:frame];
        [self setupInitialState];
        self.stateManagementEnabled = NO;
    }
    return self;
}

- (void)dealloc {
    // Clean up resources to prevent memory leaks
    self.delegate = nil;
    self.aiImageData = nil;
    [self.tableView setDelegate:nil];
    [self.tableView setDataSource:nil];
}

- (void)setupTableViewWithFrame:(CGRect)frame {
    self.tableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
}

- (void)setupInitialState {
    self.battery = -1;
    self.charging = NO;
    self.isLoadingMediaInfo = NO;
    self.recordingVideo = NO;
    self.recordingAudio = NO;
}

#pragma mark - Public Methods

- (void)reloadData {
    [self.tableView reloadData];
}

- (void)setHidden:(BOOL)hidden {
    self.tableView.hidden = hidden;
}

- (NSString *)titleForActionType:(QGDeviceActionType)actionType {
    switch (actionType) {
        case QGDeviceActionTypeGetVersion:
            return @"Get hard Version & firm Version";
        case QGDeviceActionTypeSetTime:
            return @"Set Time";
        case QGDeviceActionTypeGetBattery:
            return @"Get Battery";
        case QGDeviceActionTypeGetMediaInfo:
            return @"Media Information";
        case QGDeviceActionTypeTakePhoto:
            return @"Take Photo";
        case QGDeviceActionTypeToggleVideoRecording:
            return self.recordingVideo ? @"Stop Recording Video" : @"Start Recording Video";
        case QGDeviceActionTypeToggleAudioRecording:
            return self.recordingAudio ? @"Stop Record audio" : @"Start Record audio";
        case QGDeviceActionTypeToggleTakeAIImage:
            return @"Take AI Image";
        case QGDeviceActionTypeReserved:
        default:
            return @"";
    }
}

- (NSString *)detailTextForActionType:(QGDeviceActionType)actionType {
    switch (actionType) {
        case QGDeviceActionTypeGetVersion:
            return [NSString stringWithFormat:@"hardVersion:%@,\nfirmVersion:%@,\nhardWifiVersion:%@,\nfirmWifiVersion:%@",
                    self.hardVersion ?: @"N/A",
                    self.firmVersion ?: @"N/A",
                    self.hardWiFiVersion ?: @"N/A",
                    self.firmWiFiVersion ?: @"N/A"];

        case QGDeviceActionTypeSetTime:
            return @"";

        case QGDeviceActionTypeGetBattery:
            return [NSString stringWithFormat:@"battary:%zd,charing:%zd", self.battery, (NSInteger)self.charging];

        case QGDeviceActionTypeGetMediaInfo:
            [self configureMediaInfoCellForActionType:actionType];
            return [self mediaInfoDetailText];

        case QGDeviceActionTypeTakePhoto:
        case QGDeviceActionTypeToggleVideoRecording:
        case QGDeviceActionTypeToggleAudioRecording:
        case QGDeviceActionTypeToggleTakeAIImage:
        case QGDeviceActionTypeReserved:
        default:
            return @"";
    }
}

- (void)configureMediaInfoCellForActionType:(QGDeviceActionType)actionType {
    // This method will be used when configuring cells
    // Actual implementation handled in cellForRowAtIndexPath
}

- (NSString *)mediaInfoDetailText {
    if (self.isLoadingMediaInfo) {
        return @"Loading...";
    } else if (self.mediaInfoError) {
        return self.mediaInfoError;
    } else if (self.currentMediaInfo) {
        return [self.currentMediaInfo formattedDescription];
    } else {
        return @"Tap to retrieve media information";
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return QGDeviceActionTypeReserved;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    QGDeviceActionType actionType = (QGDeviceActionType)indexPath.row;
    NSString *cellIdentifier = [NSString stringWithFormat:@"QGColumnsCell_%ld", (long)actionType];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }

    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    QGDeviceActionType actionType = (QGDeviceActionType)indexPath.row;

    // Reset cell state completely to prevent reuse issues
    [self resetCellState:cell];

    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.text = [self titleForActionType:actionType];

    // Handle special cases for different action types
    switch (actionType) {
        case QGDeviceActionTypeGetVersion:
        case QGDeviceActionTypeSetTime:
        case QGDeviceActionTypeGetBattery:
            cell.detailTextLabel.text = [self detailTextForActionType:actionType];
            cell.textLabel.textColor = [UIColor labelColor];
            break;

        case QGDeviceActionTypeGetMediaInfo:
            [self configureMediaInfoCell:cell];
            break;

        case QGDeviceActionTypeTakePhoto:
        case QGDeviceActionTypeToggleVideoRecording:
        case QGDeviceActionTypeToggleAudioRecording:
            cell.textLabel.textColor = [UIColor labelColor];
            break;

        case QGDeviceActionTypeToggleTakeAIImage:
            [self configureAIImageCell:cell];
            break;

        case QGDeviceActionTypeReserved:
        default:
            break;
    }
}

- (void)resetCellState:(UITableViewCell *)cell {
    // Clear all cell properties to prevent reuse artifacts
    cell.imageView.image = nil;
    cell.textLabel.text = @"";
    cell.detailTextLabel.text = @"";
    cell.textLabel.textColor = [UIColor labelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // Remove any loading indicators or custom views
    UIView *loadingIndicator = [cell.contentView viewWithTag:999];
    if (loadingIndicator) {
        [loadingIndicator removeFromSuperview];
    }
}

- (void)configureMediaInfoCell:(UITableViewCell *)cell {
    if (self.isLoadingMediaInfo) {
        // Show loading state
        cell.detailTextLabel.text = @"Loading...";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];

        // Add loading indicator
        UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        indicator.tag = 999;
        indicator.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:indicator];

        [NSLayoutConstraint activateConstraints:@[
            [indicator.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [indicator.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0]
        ]];
        [indicator startAnimating];

    } else if (self.mediaInfoError) {
        // Show error state
        cell.detailTextLabel.text = self.mediaInfoError;
        cell.textLabel.textColor = [UIColor systemRedColor];

    } else if (self.currentMediaInfo) {
        // Show success state with formatted data
        cell.detailTextLabel.text = [self.currentMediaInfo formattedDescription];
        cell.textLabel.textColor = [UIColor labelColor];

    } else {
        // Show idle state
        cell.detailTextLabel.text = @"Tap to retrieve media information";
        cell.textLabel.textColor = [UIColor labelColor];
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    QGDeviceActionType actionType = (QGDeviceActionType)indexPath.row;

    // Special handling for AI Image - with safer delegate access
    if (actionType == QGDeviceActionTypeToggleTakeAIImage && self.aiImageData) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(columnsManager:didSelectAIImage:)]) {
            @try {
                [self.delegate columnsManager:self didSelectAIImage:self.aiImageData];
            } @catch (NSException *exception) {
                NSLog(@"Error in AI image delegate call: %@", exception.reason);
            }
        }
        return;
    }

    if (self.delegate && [self.delegate respondsToSelector:@selector(columnsManager:didSelectAction:)]) {
        @try {
            [self.delegate columnsManager:self didSelectAction:actionType];
        } @catch (NSException *exception) {
            NSLog(@"Error in action delegate call: %@", exception.reason);
        }
    }
}

- (void)configureAIImageCell:(UITableViewCell *)cell {
    // Note: Cell state is already reset in resetCellState method

    if (self.aiImageData && self.aiImageData.length > 0) {
        UIImage *aiImage = [UIImage imageWithData:self.aiImageData];
        if (aiImage) {
            // Create a thumbnail with consistent size - safer approach
            CGSize thumbnailSize = CGSizeMake(40, 40);

            @try {
                UIGraphicsBeginImageContextWithOptions(thumbnailSize, NO, 0.0);
                CGContextRef context = UIGraphicsGetCurrentContext();
                if (context) {
                    [aiImage drawInRect:CGRectMake(0, 0, thumbnailSize.width, thumbnailSize.height)];
                    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
                    if (thumbnail) {
                        cell.imageView.image = thumbnail;
                    }
                }
                UIGraphicsEndImageContext();
            } @catch (NSException *exception) {
                NSLog(@"Error creating thumbnail: %@", exception.reason);
                // Fallback: use original image if thumbnail creation fails
                cell.imageView.image = aiImage;
            }

            // Update detail text to show image status
            cell.detailTextLabel.text = @"AI Image captured - tap to view";
            cell.textLabel.textColor = [UIColor labelColor];
        }
    } else {
        // No AI image available - show placeholder text
        cell.detailTextLabel.text = @"Tap to take AI Image";
        cell.textLabel.textColor = [UIColor labelColor];
    }
}

- (void)clearAIImage {
    self.aiImageData = nil;
    [self reloadData];

    // Auto-save if state management is enabled
    if (self.stateManagementEnabled) {
        [self saveCurrentState];
    }
}

#pragma mark - State Management

- (void)enableStateManagementWithIdentifier:(NSString *)identifier {
    if (!identifier || identifier.length == 0) {
        NSLog(@"Error: Cannot enable state management with invalid identifier");
        return;
    }

    self.stateManager = [[QGStateManager alloc] initWithIdentifier:identifier
                                                   storageLocation:QGStateStorageLocationUserDefaults];
    self.stateManager.delegate = self;
    self.stateManagementEnabled = YES;

    // Try to restore saved state
    [self restoreSavedState];

    // Enable auto-save with 30-second interval
    [self.stateManager enableAutoSave];
    [self.stateManager startAutoSaveTimer];

    NSLog(@"State management enabled with identifier: %@", identifier);
}

- (void)disableStateManagement {
    // Save current state before disabling
    [self saveCurrentState];

    self.stateManagementEnabled = NO;
    [self.stateManager disableAutoSave];
    self.stateManager.delegate = nil;
    self.stateManager = nil;

    NSLog(@"State management disabled");
}

- (BOOL)saveCurrentState {
    if (!self.stateManagementEnabled || !self.stateManager) {
        return NO;
    }

    // Prepare device state
    NSDictionary *deviceState = @{
        @"hardVersion": self.hardVersion ?: @"",
        @"firmVersion": self.firmVersion ?: @"",
        @"hardWiFiVersion": self.hardWiFiVersion ?: @"",
        @"firmWiFiVersion": self.firmWiFiVersion ?: @"",
        @"mac": self.mac ?: @"",
        @"battery": @(self.battery),
        @"charging": @(self.charging),
        @"recordingVideo": @(self.recordingVideo),
        @"recordingAudio": @(self.recordingAudio)
    };

    // Prepare UI state
    NSMutableDictionary *uiState = [NSMutableDictionary dictionary];

    if (self.currentMediaInfo) {
        uiState[@"mediaInfo"] = @{
            @"photoCount": @(self.currentMediaInfo.photoCount),
            @"videoCount": @(self.currentMediaInfo.videoCount),
            @"audioCount": @(self.currentMediaInfo.audioCount),
            @"totalSize": @(self.currentMediaInfo.totalSize)
        };
    }

    if (self.aiImageData) {
        uiState[@"hasAIImage"] = @(YES);
        // Note: We don't save the actual image data, just that it exists
    }

    if (self.mediaInfoError) {
        uiState[@"mediaInfoError"] = self.mediaInfoError;
    }

    uiState[@"isLoadingMediaInfo"] = @(self.isLoadingMediaInfo);

    // Combine into complete state
    NSDictionary *completeState = @{
        @"deviceState": deviceState,
        @"uiState": uiState
    };

    NSError *error;
    BOOL success = [self.stateManager saveState:completeState error:&error];

    if (!success) {
        NSLog(@"Failed to save state: %@", error.localizedDescription);
    } else {
        NSLog(@"State saved successfully");
    }

    return success;
}

- (BOOL)restoreSavedState {
    if (!self.stateManagementEnabled || !self.stateManager) {
        return NO;
    }

    NSError *error;
    NSDictionary *savedState = [self.stateManager restoreStateWithError:&error];

    if (!savedState) {
        NSLog(@"No saved state available or restoration failed: %@", error.localizedDescription);
        return NO;
    }

    // Restore device state
    NSDictionary *deviceState = savedState[@"deviceState"];
    if (deviceState) {
        self.hardVersion = deviceState[@"hardVersion"];
        self.firmVersion = deviceState[@"firmVersion"];
        self.hardWiFiVersion = deviceState[@"hardWiFiVersion"];
        self.firmWiFiVersion = deviceState[@"firmWiFiVersion"];
        self.mac = deviceState[@"mac"];
        self.battery = [deviceState[@"battery"] integerValue];
        self.charging = [deviceState[@"charging"] boolValue];
        self.recordingVideo = [deviceState[@"recordingVideo"] boolValue];
        self.recordingAudio = [deviceState[@"recordingAudio"] boolValue];
    }

    // Restore UI state
    NSDictionary *uiState = savedState[@"uiState"];
    if (uiState) {
        // Restore media info
        NSDictionary *mediaInfoDict = uiState[@"mediaInfo"];
        if (mediaInfoDict) {
            // Note: We create a new QGMediaInfo object here
            // In a real implementation, you'd need the proper constructor
            self.currentMediaInfo = [[QGMediaInfo alloc] initWithPhotoCount:[mediaInfoDict[@"photoCount"] integerValue]
                                                                 videoCount:[mediaInfoDict[@"videoCount"] integerValue]
                                                                 audioCount:[mediaInfoDict[@"audioCount"] integerValue]
                                                                  totalSize:[mediaInfoDict[@"totalSize"] integerValue]];
        }

        // Restore other UI state
        self.mediaInfoError = uiState[@"mediaInfoError"];
        self.isLoadingMediaInfo = [uiState[@"isLoadingMediaInfo"] boolValue];

        // Note: AI image data is not restored, only the fact that it existed
        // The actual image would need to be re-captured from the device
    }

    // Update UI
    [self reloadData];

    NSLog(@"State restored successfully");
    return YES;
}

- (void)clearSavedState {
    if (self.stateManager) {
        [self.stateManager clearSavedState];
        NSLog(@"Saved state cleared");
    }
}

#pragma mark - QGStateManagerDelegate

- (void)stateManager:(QGStateManager *)manager didSaveState:(NSDictionary *)state {
    NSLog(@"State auto-saved successfully");
}

- (void)stateManager:(QGStateManager *)manager didRestoreState:(NSDictionary *)state {
    NSLog(@"State auto-restored successfully");
}

- (void)stateManager:(QGStateManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"State manager error: %@", error.localizedDescription);
    if ([self.delegate respondsToSelector:@selector(columnsManager:didFailWithError:)]) {
        // Note: This would require adding an error delegate method to the main delegate protocol
        NSLog(@"Error in state management: %@", error.localizedDescription);
    }
}

@end
