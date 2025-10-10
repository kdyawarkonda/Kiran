//
//  WiFiTransferViewController.m
//  QCSDKDemo
//
//  Breaks the Wi-Fi media transfer workflow into observable stages so the user
//  can see exactly where the process stands and retry individual steps if the
//  hotspot is not ready yet.
//

#import "WiFiTransferViewController.h"

#import "GlassesWiFiHandler.h"
#import "MediaGalleryViewController.h"
#import <QCSDK/QCSDKCmdCreator.h>

typedef NS_ENUM(NSInteger, WiFiTransferStepState) {
    WiFiTransferStepStatePending = 0,
    WiFiTransferStepStateInProgress,
    WiFiTransferStepStateSuccess,
    WiFiTransferStepStateFailure,
};

typedef NS_ENUM(NSUInteger, WiFiTransferStepIndex) {
    WiFiTransferStepIndexPrepareDevice = 0,
    WiFiTransferStepIndexRequestCredentials,
    WiFiTransferStepIndexRetrieveDeviceIP,
    WiFiTransferStepIndexJoinHotspot,
    WiFiTransferStepIndexDetectDeviceIP,
    WiFiTransferStepIndexDownloadManifest,
    WiFiTransferStepIndexDownloadMedia,
    WiFiTransferStepIndexCount
};

@interface WiFiTransferStep : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) WiFiTransferStepState state;

@end

@implementation WiFiTransferStep

+ (instancetype)stepWithTitle:(NSString *)title detail:(NSString *)detail {
    WiFiTransferStep *step = [[WiFiTransferStep alloc] init];
    step.title = title ?: @"";
    step.detail = detail ?: @"";
    step.state = WiFiTransferStepStatePending;
    return step;
}

@end

@interface WiFiTransferViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<WiFiTransferStep *> *steps;
@property (nonatomic, strong) NSURLSession *transferSession;
@property (nonatomic, copy) NSString *glassesSSID;
@property (nonatomic, copy) NSString *glassesPassword;
@property (nonatomic, copy) NSString *deviceIP;
@property (nonatomic, copy) NSArray<NSDictionary *> *manifestEntries;
@property (nonatomic, strong) UIBarButtonItem *viewFilesButton;
@property (nonatomic, assign, getter=isWorkflowComplete) BOOL workflowComplete;
@property (nonatomic, assign) NSUInteger busyRetryCounter;
@property (nonatomic, assign) NSUInteger reprepareRetryCounter;

@end

@implementation WiFiTransferViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Wi-Fi Transfer";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self configureTableView];
    [self configureNavigationItems];
    [self configureSteps];
    [self rebuildTransferSession];

    [self startWorkflow];
}

- (void)dealloc {
    [self.transferSession invalidateAndCancel];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[GlassesWiFiHandler sharedHandler] cancelCurrentOperation];
    [self.navigationController setToolbarHidden:YES animated:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
}

#pragma mark - Setup

- (void)configureTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    [self.view addSubview:self.tableView];
}

- (void)configureNavigationItems {
    UIBarButtonItem *retryButton = [[UIBarButtonItem alloc] initWithTitle:@"Retry"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(retryWorkflow)];
    self.navigationItem.rightBarButtonItem = retryButton;

    self.viewFilesButton = [[UIBarButtonItem alloc] initWithTitle:@"View Files"
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(openMediaGallery)];
    self.viewFilesButton.enabled = NO;
    self.toolbarItems = @[self.viewFilesButton];
    [self.navigationController setToolbarHidden:NO animated:YES];
}

- (void)configureSteps {
    self.steps = [NSMutableArray arrayWithCapacity:WiFiTransferStepIndexCount];
    [self.steps addObject:[WiFiTransferStep stepWithTitle:@"Prepare Device"
                                                  detail:@"Switching glasses to Wi-Fi transfer mode"]];
    [self.steps addObject:[WiFiTransferStep stepWithTitle:@"Request Credentials"
                                                  detail:@"Awaiting response from glasses"]];
    [self.steps addObject:[WiFiTransferStep stepWithTitle:@"Retrieve Device IP"
                                                  detail:@"Requesting the glasses Wi-Fi address"]];
    [self.steps addObject:[WiFiTransferStep stepWithTitle:@"Join Hotspot"
                                                  detail:@"Configuring the glasses Wi-Fi network"]];
    [self.steps addObject:[WiFiTransferStep stepWithTitle:@"Detect Device IP"
                                                  detail:@"Verifying the phone is on the glasses hotspot"]];
    [self.steps addObject:[WiFiTransferStep stepWithTitle:@"Download Manifest"
                                                  detail:@"Fetching /files/media.config"]];
    [self.steps addObject:[WiFiTransferStep stepWithTitle:@"Download Media"
                                                  detail:@"Saving media files to device"]];
}

- (void)rebuildTransferSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 10.0;
    config.timeoutIntervalForResource = 120.0;
    config.allowsCellularAccess = NO;
    config.connectionProxyDictionary = @{};
    if (@available(iOS 11.0, *)) {
        config.waitsForConnectivity = NO;
    }
    if (@available(iOS 13.0, *)) {
        config.allowsExpensiveNetworkAccess = NO;
        config.allowsConstrainedNetworkAccess = NO;
    }
    self.transferSession = [NSURLSession sessionWithConfiguration:config];
}

#pragma mark - Workflow Control

- (void)startWorkflow {
    self.workflowComplete = NO;
    self.viewFilesButton.enabled = NO;

    for (WiFiTransferStep *step in self.steps) {
        step.state = WiFiTransferStepStatePending;
        step.detail = [self initialDetailForStep:step.title];
    }
    [self.tableView reloadData];

    self.glassesSSID = nil;
    self.glassesPassword = nil;
    self.deviceIP = nil;
    self.manifestEntries = nil;
    self.busyRetryCounter = 0;
    self.reprepareRetryCounter = 0;

    [self prepareDeviceStep];
}

- (void)retryWorkflow {
    [[GlassesWiFiHandler sharedHandler] reset];
    [self.transferSession invalidateAndCancel];
    [self rebuildTransferSession];
    [self startWorkflow];
}

- (NSString *)initialDetailForStep:(NSString *)title {
    if ([title isEqualToString:@"Prepare Device"]) {
        return @"Switching glasses to Wi-Fi transfer mode";
    } else if ([title isEqualToString:@"Request Credentials"]) {
        return @"Awaiting response from glasses";
    } else if ([title isEqualToString:@"Retrieve Device IP"]) {
        return @"Requesting the glasses Wi-Fi address";
    } else if ([title isEqualToString:@"Join Hotspot"]) {
        return @"Configuring the glasses Wi-Fi network";
    } else if ([title isEqualToString:@"Detect Device IP"]) {
        return @"Verifying the phone is on the glasses hotspot";
    } else if ([title isEqualToString:@"Download Manifest"]) {
        return @"Fetching /files/media.config";
    } else if ([title isEqualToString:@"Download Media"]) {
        return @"Saving media files to device";
    }
    return @"";
}

#pragma mark - Step Execution

- (void)prepareDeviceStep {
    [self setStepState:WiFiTransferStepStateInProgress
               detail:@"Switching glasses to Wi-Fi transfer mode..."
              atIndex:WiFiTransferStepIndexPrepareDevice];

    [self attemptPrepareDeviceWithDelay:0.0];
}

- (void)attemptPrepareDeviceWithDelay:(NSTimeInterval)delay {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        if (![QCSDKCmdCreator isPeripheralFreeNow]) {
            strongSelf.busyRetryCounter += 1;
            if (strongSelf.busyRetryCounter > 5) {
                NSError *error = [NSError errorWithDomain:@"WiFiTransfer"
                                                     code:-151
                                                 userInfo:@{ NSLocalizedDescriptionKey : @"Device is busy. Please try again." }];
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexPrepareDevice withError:error];
                return;
            }

            NSString *status = [NSString stringWithFormat:@"Device busy… retrying (%lu/5)", (unsigned long)strongSelf.busyRetryCounter];
            [strongSelf updateStepDetail:status atIndex:WiFiTransferStepIndexPrepareDevice];
            [strongSelf attemptPrepareDeviceWithDelay:0.5];
            return;
        }

        strongSelf.busyRetryCounter = 0;

        [QCSDKCmdCreator setDeviceMode:QCOperatorDeviceModeTransfer success:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerStrong = weakSelf;
                if (!innerStrong) { return; }

                [innerStrong setStepState:WiFiTransferStepStateSuccess
                                     detail:@"Glasses ready for Wi-Fi transfer"
                                    atIndex:WiFiTransferStepIndexPrepareDevice];
                [innerStrong requestCredentialsStep];
            });
        } fail:^(NSInteger code) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerStrong = weakSelf;
                if (!innerStrong) { return; }

                NSError *error = [NSError errorWithDomain:@"WiFiTransfer"
                                                     code:code
                                                 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to set transfer mode (code %ld)", (long)code] }];
                [innerStrong handleStepFailureAtIndex:WiFiTransferStepIndexPrepareDevice withError:error];
            });
        }];
    });
}

- (void)requestCredentialsStep {
    [self setStepState:WiFiTransferStepStateInProgress
               detail:@"Requesting Wi-Fi credentials..."
              atIndex:WiFiTransferStepIndexRequestCredentials];

    __weak typeof(self) weakSelf = self;
    [[GlassesWiFiHandler sharedHandler] requestWiFiCredentialsWithStatusCallback:^(GlassesWiFiHandlerState state, NSString *status, UIImage * _Nullable previewImage) {
        (void)state;
        (void)previewImage;
        [weakSelf updateStepDetail:status atIndex:WiFiTransferStepIndexRequestCredentials];
    } completion:^(NSString *ssid, NSString *password, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            if (error || ssid.length == 0) {
                NSError *reportedError = error ?: [NSError errorWithDomain:@"WiFiTransfer" code:-100 userInfo:@{ NSLocalizedDescriptionKey : @"No SSID returned by the device." }];
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexRequestCredentials withError:reportedError];
                return;
            }

            strongSelf.glassesSSID = ssid;
            strongSelf.glassesPassword = password;

            NSString *detail = [NSString stringWithFormat:@"SSID: %@\nPassword: %@",
                                ssid.length ? ssid : @"<unknown>",
                                password.length ? password : @"(default)"];
            [strongSelf setStepState:WiFiTransferStepStateSuccess detail:detail atIndex:WiFiTransferStepIndexRequestCredentials];
            [strongSelf retrieveDeviceIPStep];
        });
    }];
}

- (void)retrieveDeviceIPStep {
    [self setStepState:WiFiTransferStepStateInProgress
               detail:@"Requesting the glasses Wi-Fi address..."
              atIndex:WiFiTransferStepIndexRetrieveDeviceIP];

    [self attemptRetrieveDeviceIPWithRetry:0];
}

- (void)attemptRetrieveDeviceIPWithRetry:(NSUInteger)attempt {
    static const NSUInteger kMaxDeviceIPAttempts = 5;
    static const NSTimeInterval kDeviceIPRetryDelay = 1.0;

    __weak typeof(self) weakSelf = self;
    [QCSDKCmdCreator getDeviceWifiIPSuccess:^(NSString * _Nullable ipAddress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            NSString *normalized = [strongSelf normalizedIPv4AddressFromString:ipAddress];
            if (normalized.length > 0) {
                strongSelf.deviceIP = normalized;
                NSString *detail = [NSString stringWithFormat:@"Device reports hotspot IP %@", normalized];
                [strongSelf setStepState:WiFiTransferStepStateSuccess detail:detail atIndex:WiFiTransferStepIndexRetrieveDeviceIP];
                [strongSelf scheduleJoinHotspotAfterDelay:1.5];
            } else {
                [strongSelf scheduleDeviceIPRetryAfterAttempt:attempt
                                            maxAttempts:kMaxDeviceIPAttempts
                                                delay:kDeviceIPRetryDelay];
            }
        });
    } failed:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf scheduleDeviceIPRetryAfterAttempt:attempt
                                        maxAttempts:kMaxDeviceIPAttempts
                                            delay:kDeviceIPRetryDelay];
        });
    }];
}

- (void)scheduleJoinHotspotAfterDelay:(NSTimeInterval)delay {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf reassertTransferModeWithCompletion:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                [strongSelf joinHotspotStep];
            } else if (error) {
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexPrepareDevice withError:error];
            }
        }];
    });
}

- (void)scheduleDeviceIPRetryAfterAttempt:(NSUInteger)attempt
                              maxAttempts:(NSUInteger)maxAttempts
                                   delay:(NSTimeInterval)delay {
    if (attempt + 1 >= maxAttempts) {
        NSError *error = [NSError errorWithDomain:@"WiFiTransfer" code:-150 userInfo:@{ NSLocalizedDescriptionKey : @"Glasses did not return a hotspot IP. Ensure Wi-Fi transfer mode is enabled." }];
        [self handleStepFailureAtIndex:WiFiTransferStepIndexRetrieveDeviceIP withError:error];
        return;
    }

    NSString *status = [NSString stringWithFormat:@"Waiting for glasses hotspot... (%lu/%lu)",
                        (unsigned long)(attempt + 1),
                        (unsigned long)maxAttempts];
    [self updateStepDetail:status atIndex:WiFiTransferStepIndexRetrieveDeviceIP];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf attemptRetrieveDeviceIPWithRetry:attempt + 1];
    });
}

- (void)joinHotspotStep {
    if (self.glassesSSID.length == 0) {
        NSError *error = [NSError errorWithDomain:@"WiFiTransfer" code:-101 userInfo:@{ NSLocalizedDescriptionKey : @"Missing hotspot credentials." }];
        [self handleStepFailureAtIndex:WiFiTransferStepIndexJoinHotspot withError:error];
        return;
    }

    [self setStepState:WiFiTransferStepStateInProgress
               detail:@"Configuring hotspot via NEHotspotConfiguration..."
              atIndex:WiFiTransferStepIndexJoinHotspot];

    __weak typeof(self) weakSelf = self;
    [[GlassesWiFiHandler sharedHandler] connectToGlassesWiFi:self.glassesSSID
                                                    password:self.glassesPassword
                                              statusCallback:^(GlassesWiFiHandlerState state, NSString *status, UIImage * _Nullable previewImage) {
        (void)state;
        (void)previewImage;
        [weakSelf updateStepDetail:status atIndex:WiFiTransferStepIndexJoinHotspot];
    } completion:^(BOOL success, NSString * _Nullable deviceIP, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            if (!success) {
                NSError *reportedError = error ?: [NSError errorWithDomain:@"WiFiTransfer" code:-102 userInfo:@{ NSLocalizedDescriptionKey : @"Failed to join the glasses hotspot." }];
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexJoinHotspot withError:reportedError];
                return;
            }

            if (deviceIP.length > 0) {
                strongSelf.deviceIP = [strongSelf normalizedIPv4AddressFromString:deviceIP] ?: deviceIP;
            }
            [strongSelf setStepState:WiFiTransferStepStateSuccess
                               detail:@"Hotspot configuration applied"
                              atIndex:WiFiTransferStepIndexJoinHotspot];
            [strongSelf detectDeviceIPStep];
        });
    }];
}

- (void)detectDeviceIPStep {
    [self setStepState:WiFiTransferStepStateInProgress
               detail:@"Verifying hotspot association..."
              atIndex:WiFiTransferStepIndexDetectDeviceIP];

    if (self.deviceIP.length == 0) {
        NSError *error = [NSError errorWithDomain:@"WiFiTransfer" code:-201 userInfo:@{ NSLocalizedDescriptionKey : @"Unable to determine device IP address." }];
        [self handleStepFailureAtIndex:WiFiTransferStepIndexDetectDeviceIP withError:error];
        return;
    }

    NSString *pingURLString = [NSString stringWithFormat:@"http://%@/", self.deviceIP];
    NSURL *pingURL = [NSURL URLWithString:pingURLString];
    if (!pingURL) {
        NSError *error = [NSError errorWithDomain:@"WiFiTransfer" code:-202 userInfo:@{ NSLocalizedDescriptionKey : @"Device IP address appears invalid." }];
        [self handleStepFailureAtIndex:WiFiTransferStepIndexDetectDeviceIP withError:error];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:pingURL
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:3.0];
    request.HTTPMethod = @"HEAD";

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.transferSession dataTaskWithRequest:request
                                                         completionHandler:^(NSData * _Nullable data,
                                                                             NSURLResponse * _Nullable response,
                                                                             NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            if (error || ![strongSelf isHTTP200Response:response]) {
                NSString *message = error.localizedDescription ?: @"Device did not respond. Confirm the phone is connected to the glasses hotspot.";
                NSError *reported = [NSError errorWithDomain:@"WiFiTransfer" code:-203 userInfo:@{ NSLocalizedDescriptionKey : message }];
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexDetectDeviceIP withError:reported];
                return;
            }

            NSString *detail = [NSString stringWithFormat:@"Detected device at %@", strongSelf.deviceIP];
            [strongSelf setStepState:WiFiTransferStepStateSuccess detail:detail atIndex:WiFiTransferStepIndexDetectDeviceIP];
            [strongSelf downloadManifestStep];
        });
    }];
    [task resume];
}

- (void)downloadManifestStep {
    if (self.deviceIP.length == 0) {
        NSError *error = [NSError errorWithDomain:@"WiFiTransfer" code:-103 userInfo:@{ NSLocalizedDescriptionKey : @"Device IP missing." }];
        [self handleStepFailureAtIndex:WiFiTransferStepIndexDownloadManifest withError:error];
        return;
    }

    NSString *detail = [NSString stringWithFormat:@"Requesting http://%@/files/media.config", self.deviceIP];
    [self setStepState:WiFiTransferStepStateInProgress detail:detail atIndex:WiFiTransferStepIndexDownloadManifest];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/files/media.config", self.deviceIP]];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"WiFiTransfer" code:-104 userInfo:@{ NSLocalizedDescriptionKey : @"Generated manifest URL is invalid." }];
        [self handleStepFailureAtIndex:WiFiTransferStepIndexDownloadManifest withError:error];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.transferSession dataTaskWithURL:url
                                                     completionHandler:^(NSData * _Nullable data,
                                                                         NSURLResponse * _Nullable response,
                                                                         NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            if (error || ![strongSelf isHTTP200Response:response]) {
                NSError *reportedError = error ?: [NSError errorWithDomain:@"WiFiTransfer" code:-105 userInfo:@{ NSLocalizedDescriptionKey : @"Failed to download manifest." }];
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexDownloadManifest withError:reportedError];
                return;
            }

            NSError *parseError = nil;
            NSArray<NSDictionary *> *entries = [strongSelf parseManifestData:data error:&parseError];
            if (parseError || entries.count == 0) {
                NSError *reportedError = parseError ?: [NSError errorWithDomain:@"WiFiTransfer" code:-106 userInfo:@{ NSLocalizedDescriptionKey : @"Manifest is empty." }];
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexDownloadManifest withError:reportedError];
                return;
            }

            strongSelf.manifestEntries = entries;
            NSString *summary = [NSString stringWithFormat:@"Found %lu media item%@",
                                  (unsigned long)entries.count,
                                  entries.count == 1 ? @"" : @"s"];
            [strongSelf setStepState:WiFiTransferStepStateSuccess detail:summary atIndex:WiFiTransferStepIndexDownloadManifest];
            [strongSelf downloadMediaStepFromIndex:0];
        });
    }];
    [task resume];
}

- (void)downloadMediaStepFromIndex:(NSUInteger)index {
    if (self.manifestEntries.count == 0) {
        [self setStepState:WiFiTransferStepStateSuccess detail:@"No media files listed in manifest." atIndex:WiFiTransferStepIndexDownloadMedia];
        [self finishWorkflow];
        return;
    }

    if (index >= self.manifestEntries.count) {
        NSString *detail = [NSString stringWithFormat:@"Saved %lu file%@ to Documents/GlassesMedia",
                              (unsigned long)self.manifestEntries.count,
                              self.manifestEntries.count == 1 ? @"" : @"s"];
        [self setStepState:WiFiTransferStepStateSuccess detail:detail atIndex:WiFiTransferStepIndexDownloadMedia];
        [self finishWorkflow];
        return;
    }

    NSDictionary *entry = self.manifestEntries[index];
    NSString *relativePath = entry[@"path"] ?: entry[@"url"];
    NSString *filename = entry[@"name"] ?: [relativePath lastPathComponent];

    if (relativePath.length == 0 || filename.length == 0) {
        [self downloadMediaStepFromIndex:index + 1];
        return;
    }

    NSString *detail = [NSString stringWithFormat:@"Downloading %@ (%lu/%lu)", filename, (unsigned long)(index + 1), (unsigned long)self.manifestEntries.count];
    [self setStepState:WiFiTransferStepStateInProgress detail:detail atIndex:WiFiTransferStepIndexDownloadMedia];

    NSString *urlString = relativePath;
    if (![relativePath hasPrefix:@"http://"] && ![relativePath hasPrefix:@"https://"]) {
        NSString *escapedPath = [relativePath hasPrefix:@"/"] ? relativePath : [@"/" stringByAppendingString:relativePath];
        urlString = [NSString stringWithFormat:@"http://%@%@", self.deviceIP, escapedPath];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self updateStepDetail:[NSString stringWithFormat:@"Skipping %@ (invalid URL)", filename] atIndex:WiFiTransferStepIndexDownloadMedia];
        [self downloadMediaStepFromIndex:index + 1];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *task = [self.transferSession downloadTaskWithURL:url
                                                             completionHandler:^(NSURL * _Nullable location,
                                                                                 NSURLResponse * _Nullable response,
                                                                                 NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }

            if (error || ![strongSelf isHTTP200Response:response]) {
                NSError *reportedError = error ?: [NSError errorWithDomain:@"WiFiTransfer" code:-107 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to download %@", filename] }];
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexDownloadMedia withError:reportedError];
                return;
            }

            NSError *persistError = [strongSelf persistDownloadedFileAtLocation:location filename:filename];
            if (persistError) {
                [strongSelf handleStepFailureAtIndex:WiFiTransferStepIndexDownloadMedia withError:persistError];
                return;
            }

            [strongSelf updateStepDetail:[NSString stringWithFormat:@"Saved %@", filename] atIndex:WiFiTransferStepIndexDownloadMedia];
            [strongSelf downloadMediaStepFromIndex:index + 1];
        });
    }];
    [task resume];
}

- (void)finishWorkflow {
    self.workflowComplete = YES;
    self.viewFilesButton.enabled = YES;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Transfer Complete"
                                                                   message:@"Media files have been saved to Documents/GlassesMedia."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"View Files"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openMediaGallery];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Helpers

- (void)setStepState:(WiFiTransferStepState)state detail:(NSString *)detail atIndex:(NSUInteger)index {
    if (index >= self.steps.count) { return; }
    WiFiTransferStep *step = self.steps[index];
    step.state = state;
    if (detail.length > 0) {
        step.detail = detail;
    }
    [self reloadStepAtIndex:index];
}

- (void)updateStepDetail:(NSString *)detail atIndex:(NSUInteger)index {
    if (index >= self.steps.count || detail.length == 0) { return; }
    WiFiTransferStep *step = self.steps[index];
    step.detail = detail;
    [self reloadStepAtIndex:index];
}

- (void)reloadStepAtIndex:(NSUInteger)index {
    if (index >= self.steps.count) { return; }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *visibleCell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (visibleCell) {
        [self configureCell:visibleCell forStep:self.steps[index]];
    } else {
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)handleStepFailureAtIndex:(NSUInteger)index withError:(NSError *)error {
    NSString *message = error.localizedDescription ?: @"An unknown error occurred.";
    [self setStepState:WiFiTransferStepStateFailure detail:message atIndex:index];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Step Failed"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Retry"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self retryWorkflow];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)isHTTP200Response:(NSURLResponse *)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }
    NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
    return status >= 200 && status < 300;
}

- (NSArray<NSDictionary *> *)parseManifestData:(NSData *)data error:(NSError **)error {
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"WiFiTransfer" code:-108 userInfo:@{ NSLocalizedDescriptionKey : @"Manifest data missing." }];
        }
        return @[];
    }

    NSError *jsonError = nil;
    id manifestObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError || ![manifestObject isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = jsonError ?: [NSError errorWithDomain:@"WiFiTransfer" code:-109 userInfo:@{ NSLocalizedDescriptionKey : @"Manifest JSON invalid." }];
        }
        return @[];
    }

    NSDictionary *manifestDict = (NSDictionary *)manifestObject;
    NSArray *files = manifestDict[@"files"];
    if (![files isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"WiFiTransfer" code:-110 userInfo:@{ NSLocalizedDescriptionKey : @"Manifest does not contain a files array." }];
        }
        return @[];
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (id item in files) {
        if (![item isKindOfClass:[NSDictionary class]]) { continue; }
        NSDictionary *dict = (NSDictionary *)item;
        NSString *path = dict[@"path"] ?: dict[@"url"];
        if (path.length == 0) { continue; }
        NSString *name = dict[@"name"];
        if (name.length == 0) {
            name = [path lastPathComponent];
        }
        [entries addObject:@{ @"path" : path ?: @"",
                              @"name" : name ?: @"" }];
    }

    return entries.copy;
}

- (NSError *)persistDownloadedFileAtLocation:(NSURL *)location filename:(NSString *)filename {
    NSString *directory = [self mediaDirectoryPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *directoryError = nil;
    if (![fileManager fileExistsAtPath:directory]) {
        if (![fileManager createDirectoryAtPath:directory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&directoryError]) {
            return directoryError ?: [NSError errorWithDomain:@"WiFiTransfer" code:-111 userInfo:@{ NSLocalizedDescriptionKey : @"Failed to create media directory." }];
        }
    }

    NSString *targetPath = [directory stringByAppendingPathComponent:filename];
    if ([fileManager fileExistsAtPath:targetPath]) {
        [fileManager removeItemAtPath:targetPath error:nil];
    }

    NSError *moveError = nil;
    if (![fileManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:targetPath] error:&moveError]) {
        return moveError ?: [NSError errorWithDomain:@"WiFiTransfer" code:-112 userInfo:@{ NSLocalizedDescriptionKey : @"Failed to persist downloaded file." }];
    }

    return nil;
}

- (NSString *)mediaDirectoryPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject ?: NSTemporaryDirectory();
    return [documents stringByAppendingPathComponent:@"GlassesMedia"];
}

- (void)reassertTransferModeWithCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (![QCSDKCmdCreator isPeripheralFreeNow]) {
        self.reprepareRetryCounter += 1;
        if (self.reprepareRetryCounter > 5) {
            NSError *error = [NSError errorWithDomain:@"WiFiTransfer"
                                                 code:-152
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Device is busy. Please try again." }];
            if (completion) { completion(NO, error); }
            return;
        }

        NSString *status = [NSString stringWithFormat:@"Device busy… retrying (%lu/5)", (unsigned long)self.reprepareRetryCounter];
        [self updateStepDetail:status atIndex:WiFiTransferStepIndexPrepareDevice];

        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf reassertTransferModeWithCompletion:completion];
        });
        return;
    }

    self.reprepareRetryCounter = 0;
    [self updateStepDetail:@"Re-confirming Wi-Fi transfer mode..." atIndex:WiFiTransferStepIndexPrepareDevice];

    __weak typeof(self) weakSelf = self;
    [QCSDKCmdCreator setDeviceMode:QCOperatorDeviceModeTransfer success:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf updateStepDetail:@"Glasses ready for Wi-Fi transfer (confirmed)" atIndex:WiFiTransferStepIndexPrepareDevice];
            if (completion) { completion(YES, nil); }
        });
    } fail:^(NSInteger code) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = [NSError errorWithDomain:@"WiFiTransfer"
                                                 code:code
                                             userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to set transfer mode (code %ld)", (long)code] }];
            if (completion) { completion(NO, error); }
        });
    }];
}

- (NSString *)normalizedIPv4AddressFromString:(NSString *)candidate {
    if (candidate.length == 0) {
        return @"";
    }

    NSString *trimmed = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *components = [trimmed componentsSeparatedByString:@"."];
    if (components.count != 4) {
        return @"";
    }

    NSMutableArray<NSString *> *normalized = [NSMutableArray arrayWithCapacity:4];
    for (NSString *part in components) {
        if (part.length == 0) { return @""; }
        NSScanner *scanner = [NSScanner scannerWithString:part];
        NSInteger value = 0;
        if (![scanner scanInteger:&value] || !scanner.isAtEnd || value < 0 || value > 255) {
            return @"";
        }
        [normalized addObject:[NSString stringWithFormat:@"%ld", (long)value]];
    }

    return [normalized componentsJoinedByString:@"."];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.steps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"WiFiTransferStepCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.detailTextLabel.numberOfLines = 0;
    }
    WiFiTransferStep *step = self.steps[indexPath.row];
    [self configureCell:cell forStep:step];
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell forStep:(WiFiTransferStep *)step {
    cell.textLabel.text = step.title;
    cell.detailTextLabel.text = step.detail;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    switch (step.state) {
        case WiFiTransferStepStatePending:
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            break;
        case WiFiTransferStepStateInProgress: {
            UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            indicator.color = [UIColor systemBlueColor];
            [indicator startAnimating];
            cell.accessoryView = indicator;
            break;
        }
        case WiFiTransferStepStateSuccess:
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            break;
        case WiFiTransferStepStateFailure:
            cell.textLabel.textColor = [UIColor systemRedColor];
            break;
    }
}

#pragma mark - Navigation

- (void)openMediaGallery {
    MediaGalleryViewController *galleryVC = [[MediaGalleryViewController alloc] init];
    galleryVC.mediaDirectoryPath = [self mediaDirectoryPath];
    [self.navigationController pushViewController:galleryVC animated:YES];
}

@end
