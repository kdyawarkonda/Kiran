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
        case QGDeviceActionTypeTimeSync:
            return @"Time Sync";
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
        case QGDeviceActionTypeSystemReboot:
            return @"System Reboot";
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

        case QGDeviceActionTypeTimeSync:
            return @"";

        case QGDeviceActionTypeSystemReboot:
            return @"Normal, P2P, or Factory Reset";

        case QGDeviceActionTypeGetBattery:            return [NSString stringWithFormat:@"battary:%zd,charing:%zd", self.battery, (NSInteger)self.charging];

        case QGDeviceActionTypeGetMediaInfo:
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

    if (actionType == QGDeviceActionTypeGetMediaInfo) {
        [self configureMediaInfoCell:cell];
    } else {
        cell.detailTextLabel.text = [self detailTextForActionType:actionType];
        cell.textLabel.textColor = [UIColor labelColor];
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

    if (self.delegate && [self.delegate respondsToSelector:@selector(columnsManager:didSelectAction:)]) {
        @try {
            [self.delegate columnsManager:self didSelectAction:actionType];
        } @catch (NSException *exception) {
            NSLog(@"Error in action delegate call: %@", exception.reason);
        }
    }
}


#pragma mark - State Management

- (void)setupStateManagerWithIdentifier:(NSString *)identifier {
    if (!identifier || identifier.length == 0) {
        NSLog(@"Error: Cannot enable state management with invalid identifier");
        return;
    }

    self.stateManager = [[QGStateManager alloc] initWithIdentifier:identifier
                                                   storageLocation:QGStateStorageLocationUserDefaults];
    [self.stateManager enableAutoSave];
    [self restoreSavedState];
    NSLog(@"State management enabled with identifier: %@", identifier);
}


- (void)restoreSavedState {
    // Restore device state
    self.hardVersion = [self.stateManager valueForKey:@"hardVersion"];
    self.firmVersion = [self.stateManager valueForKey:@"firmVersion"];
    self.hardWiFiVersion = [self.stateManager valueForKey:@"hardWiFiVersion"];
    self.firmWiFiVersion = [self.stateManager valueForKey:@"firmWiFiVersion"];
    self.mac = [self.stateManager valueForKey:@"mac"];

    NSNumber *battery = [self.stateManager valueForKey:@"battery"];
    if (battery) self.battery = [battery integerValue];

    NSNumber *charging = [self.stateManager valueForKey:@"charging"];
    if (charging) self.charging = [charging boolValue];

    NSNumber *recordingVideo = [self.stateManager valueForKey:@"recordingVideo"];
    if (recordingVideo) self.recordingVideo = [recordingVideo boolValue];

    NSNumber *recordingAudio = [self.stateManager valueForKey:@"recordingAudio"];
    if (recordingAudio) self.recordingAudio = [recordingAudio boolValue];

    NSNumber *isLoadingMediaInfo = [self.stateManager valueForKey:@"isLoadingMediaInfo"];
    if (isLoadingMediaInfo) self.isLoadingMediaInfo = [isLoadingMediaInfo boolValue];

    self.mediaInfoError = [self.stateManager valueForKey:@"mediaInfoError"];
    [self reloadData];
}


@end
