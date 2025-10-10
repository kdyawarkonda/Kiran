//
//  QGUIColumnsManager.m
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import "QGUIColumnsManager.h"
#import "QGMediaInfoManager.h"

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
    }
    return self;
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
    static NSString *cellIdentifier = @"QGColumnsCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }

    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    QGDeviceActionType actionType = (QGDeviceActionType)indexPath.row;

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

    // Special handling for AI Image
    if (actionType == QGDeviceActionTypeToggleTakeAIImage && self.aiImageData) {
        if ([self.delegate respondsToSelector:@selector(columnsManager:didSelectAIImage:)]) {
            [self.delegate columnsManager:self didSelectAIImage:self.aiImageData];
        }
        return;
    }

    if ([self.delegate respondsToSelector:@selector(columnsManager:didSelectAction:)]) {
        [self.delegate columnsManager:self didSelectAction:actionType];
    }
}

- (void)configureAIImageCell:(UITableViewCell *)cell {
    // Clear any existing image to avoid cell reuse issues
    cell.imageView.image = nil;

    if (self.aiImageData) {
        UIImage *aiImage = [UIImage imageWithData:self.aiImageData];
        if (aiImage) {
            // Create a thumbnail with consistent size
            CGSize thumbnailSize = CGSizeMake(40, 40);
            UIGraphicsBeginImageContextWithOptions(thumbnailSize, NO, 0.0);
            [aiImage drawInRect:CGRectMake(0, 0, thumbnailSize.width, thumbnailSize.height)];
            UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            cell.imageView.image = thumbnail;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

            // Update detail text to show image status
            cell.detailTextLabel.text = @"AI Image captured - tap to view";
            cell.textLabel.textColor = [UIColor labelColor];
        }
    } else {
        // No AI image available - show placeholder text
        cell.detailTextLabel.text = @"Tap to take AI Image";
        cell.textLabel.textColor = [UIColor labelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
}

- (void)clearAIImage {
    self.aiImageData = nil;
    [self reloadData];
}

@end
