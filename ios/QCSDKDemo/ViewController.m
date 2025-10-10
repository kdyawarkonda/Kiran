//
//  ViewController.m
//  QCSDKDemo
//
//  Created by steve on 2025/7/22.
//

#import "ViewController.h"
#import <QCSDK/QCVersionHelper.h>
#import <QCSDK/QCSDKManager.h>
#import <QCSDK/QCSDKCmdCreator.h>
#import <QCSDK/QCDFU_Utils.h>

#import "QCScanViewController.h"
#import "QCCentralManager.h"
#import "QGMediaInfoManager.h"
#import "QGUIColumnsManager.h"
#import "QGAIImageView.h"
#import "QGStateManager.h"

// Remove duplicate enum definition since it's now in QGUIColumnsManager.h



@interface ViewController ()<QCCentralManagerDelegate,QCSDKManagerDelegate,QGUIColumnsManagerDelegate>

@property(nonatomic,strong)UIBarButtonItem *rightItem;
@property(nonatomic,strong)QGUIColumnsManager *columnsManager;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.title = @"Feature(Tap to get data)";

    self.rightItem = [[UIBarButtonItem alloc] initWithTitle:@"Search"
                                                      style:(UIBarButtonItemStylePlain)
                                                     target:self
                                                     action:@selector(rightAction)];
    self.navigationItem.rightBarButtonItem = self.rightItem;

    // Initialize columns manager
    self.columnsManager = [[QGUIColumnsManager alloc] initWithFrame:self.view.bounds];
    self.columnsManager.delegate = self;
    [self.view addSubview:self.columnsManager.tableView];
    [self.columnsManager setHidden:YES];

    // Enable state management with unique identifier
    [self.columnsManager setupStateManagerWithIdentifier:@"QCSDKColumnsState"];

    // Initialize AI image view (floating overlay)
    [self setupAIImageView];

    [QCSDKManager shareInstance].delegate = self;
}

#pragma mark - Device Data Report
- (void)didUpdateBatteryLevel:(NSInteger)battery charging:(BOOL)charging {
    self.columnsManager.battery = battery;
    self.columnsManager.charging = charging;
    [self.columnsManager reloadData];
}

- (void)didUpdateMediaWithPhotoCount:(NSInteger)photo videoCount:(NSInteger)video audioCount:(NSInteger)audio type:(NSInteger)type {

    // Create new media info object from delegate callback
    self.columnsManager.currentMediaInfo = [[QGMediaInfo alloc] initWithPhotoCount:photo
                                                                          videoCount:video
                                                                          audioCount:audio
                                                                           totalSize:type];
    [self.columnsManager reloadData];
}

- (void)didReceiveAIChatImageData:(NSData *)imageData {
    NSLog(@"didReceiveAIChatImageData");
    // Show AI image in floating overlay instead of columns list
    [self.aiImageView showAIImage:imageData animated:YES];
}

#pragma mark - Feature Fuctions
- (void)getHardVersionAndFirmVersion {
    [QCSDKCmdCreator getDeviceVersionInfoSuccess:^(NSString * _Nonnull hdVersion, NSString * _Nonnull firmVersion, NSString * _Nonnull hdWifiVersion, NSString * _Nonnull firmWifiVersion) {

        self.columnsManager.hardVersion = hdVersion;
        self.columnsManager.firmVersion = firmVersion;
        self.columnsManager.hardWiFiVersion = hdWifiVersion;
        self.columnsManager.firmWiFiVersion = firmWifiVersion;
        [self.columnsManager reloadData];
        NSLog(@"hard Version:%@",hdVersion);
        NSLog(@"firm Version:%@",firmVersion);
        NSLog(@"hard Wifi Version:%@",hdWifiVersion);
        NSLog(@"firm Wifi Version:%@",firmWifiVersion);
    } fail:^{
        NSLog(@"get version fail");
    }];
}

- (void)getMacAddress {
    //[QCSDKCmdCreator get
    [QCSDKCmdCreator getDeviceMacAddressSuccess:^(NSString * _Nullable macAddress) {
        self.columnsManager.mac = macAddress;
        [self.columnsManager reloadData];
    } fail:^{
        NSLog(@"get mac address fail");
    }];
}

- (void)syncTime {
    [QCSDKCmdCreator setupDeviceDateTime:^(BOOL isSuccess, NSError * _Nullable err) {
        if (err) {
            NSLog(@"get err fail");
        }
    }];
}

- (void)getBattary {
    [QCSDKCmdCreator getDeviceBattery:^(NSInteger battary, BOOL charging) {

        self.columnsManager.battery = battary;
        self.columnsManager.charging = charging;
        [self.columnsManager reloadData];
    } fail:^{

    }];
}

- (void)getMediaInfo {
    NSLog(@"Getting media information with enhanced UI...");

    // Show loading state
    self.columnsManager.isLoadingMediaInfo = YES;
    self.columnsManager.mediaInfoError = nil;
    [self.columnsManager reloadData];

    [[QGMediaInfoManager shared] getMediaInfoWithCompletion:^(QGMediaInfo *mediaInfo, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.columnsManager.isLoadingMediaInfo = NO;

            if (error) {
                NSLog(@"Failed to get media info: %@", error.localizedDescription);
                self.columnsManager.mediaInfoError = error.localizedDescription;

                // Show enhanced error alert with retry
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:error.localizedDescription
                                                                        preferredStyle:UIAlertControllerStyleAlert];

                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:nil];

                UIAlertAction *retryAction = [UIAlertAction actionWithTitle:@"Retry"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^(UIAlertAction * _Nonnull action) {
                    [self getMediaInfo];
                }];

                [alert addAction:okAction];
                [alert addAction:retryAction];
                [self presentViewController:alert animated:YES completion:nil];

            } else {
                NSLog(@"Successfully retrieved media info: %@", [mediaInfo detailedDescription]);
                self.columnsManager.currentMediaInfo = mediaInfo;
                self.columnsManager.mediaInfoError = nil;
            }

            [self.columnsManager reloadData];
        });
    }];
}

- (void)takePhoto {
    //
    [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModePhoto) success:^{
        
    } fail:^(NSInteger mode) {
        NSLog(@"set fail,current device model:%zd",mode);
    }];
}

- (void)recordVideo {

    if (self.columnsManager.recordingVideo) {

        [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeVideoStop) success:^{
            self.columnsManager.recordingVideo = NO;
            [self.columnsManager reloadData];
        } fail:^(NSInteger mode) {
            NSLog(@"set fail,current device model:%zd",mode);
        }];
    }
    else {
        [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeVideo) success:^{
            self.columnsManager.recordingVideo = YES;
            [self.columnsManager reloadData];
        } fail:^(NSInteger mode) {
            NSLog(@"set fail,current device model:%zd",mode);

        }];
    }
}

- (void)recordAudio {
    if (self.columnsManager.recordingVideo) {
        [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeAudioStop) success:^{
            self.columnsManager.recordingAudio = NO;
            [self.columnsManager reloadData];
        } fail:^(NSInteger mode) {
            NSLog(@"set fail,current device model:%zd",mode);
        }];
    } else {
        [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeAudio) success:^{
            self.columnsManager.recordingAudio = YES;
            [self.columnsManager reloadData];
        } fail:^(NSInteger mode) {
            NSLog(@"set fail,current device model:%zd",mode);
        }];
    }
}

- (void)takeAIImage {
    // Clear previous AI image before taking a new one
    [self.aiImageView clearImage];

    [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeAIPhoto) success:^{
        NSLog(@"AI Image capture initiated");
    } fail:^(NSInteger mode) {
        NSLog(@"set fail,current device model:%zd",mode);
    }];
}

- (void)getTemperature {
    NSLog(@"Requesting temperature reading...");

    // Show loading state
    self.columnsManager.temperatureAvailable = NO;
    [self.columnsManager reloadData];

    // Note: In a real implementation, temperature data would come through:
    // 1. QCSDKManagerDelegate with QCDeviceDataUpdateTemperature
    // 2. Continuous health monitoring setup
    // 3. Real-time temperature data streaming

    // For demo purposes, we'll simulate a realistic temperature reading
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Generate a realistic body temperature (36.0-37.5°C)
        CGFloat randomTemp = 36.0 + (CGFloat)(arc4random_uniform(150)) / 100.0;

        self.columnsManager.temperature = randomTemp;
        self.columnsManager.temperatureAvailable = YES;

        // Save to state manager for persistence
        if (self.columnsManager.stateManager) {
            [self.columnsManager.stateManager setValue:@(randomTemp) forKey:@"temperature"];
            [self.columnsManager.stateManager setValue:@(YES) forKey:@"temperatureAvailable"];
        }

        [self.columnsManager reloadData];

        NSLog(@"Temperature reading: %.1f°C (%.1f°F)", randomTemp, randomTemp * 9.0/5.0 + 32.0);

        // Show alert with temperature reading
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Temperature Reading"
                                                                       message:[NSString stringWithFormat:@"Current body temperature: %.1f°C (%.1f°F)", randomTemp, randomTemp * 9.0/5.0 + 32.0]
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK"
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)systemReboot {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"System Reboot"
                                                                   message:@"Choose reboot type:"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *normalRestart = [UIAlertAction actionWithTitle:@"Normal Restart"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeRestart) success:^{
            NSLog(@"Normal restart initiated");
        } fail:^(NSInteger mode) {
            NSLog(@"Normal restart failed, current device model:%zd", mode);
        }];
    }];

    UIAlertAction *p2pRestart = [UIAlertAction actionWithTitle:@"P2P Restart (No Power Off)"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeNoPowerP2P) success:^{
            NSLog(@"P2P restart initiated");
        } fail:^(NSInteger mode) {
            NSLog(@"P2P restart failed, current device model:%zd", mode);
        }];
    }];

    UIAlertAction *factoryReset = [UIAlertAction actionWithTitle:@"Factory Reset"
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction * _Nonnull action) {
        // Add confirmation for factory reset
        UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Confirm Factory Reset"
                                                                             message:@"This will reset all settings to factory defaults. This action cannot be undone."
                                                                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"Reset"
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(UIAlertAction * _Nonnull action) {
            [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeFactoryReset) success:^{
                NSLog(@"Factory reset initiated");
            } fail:^(NSInteger mode) {
                NSLog(@"Factory reset failed, current device model:%zd", mode);
            }];
        }];

        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel"
                                                         style:UIAlertActionStyleCancel
                                                       handler:nil];

        [confirmAlert addAction:confirm];
        [confirmAlert addAction:cancel];
        [self presentViewController:confirmAlert animated:YES completion:nil];
    }];

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil];

    [alert addAction:normalRestart];
    [alert addAction:p2pRestart];
    [alert addAction:factoryReset];
    [alert addAction:cancel];

    // For iPad support
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
    }

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [QCCentralManager shared].delegate = self;
    [self didState:[QCCentralManager shared].deviceState];
}

- (void)rightAction {
    
    if([self.rightItem.title isEqualToString:@"Unbind"]) {
        [[QCCentralManager shared] remove];
    }
    else if ([self.rightItem.title isEqualToString:@"Search"])  {
        QCScanViewController *viewCtrl = [[QCScanViewController alloc] init];
        [self.navigationController pushViewController:viewCtrl animated:true];
    }
}

#pragma mark - QCCentralManagerDelegate
- (void)didState:(QCState)state {
    self.title = @"Feature";
    switch(state) {
        case QCStateUnbind:
            self.rightItem.title = @"Search";
            [self.columnsManager setHidden:YES];
            break;
        case QCStateConnecting:
            self.title = [QCCentralManager shared].connectedPeripheral.name;
            self.rightItem.title = @"Connecting";
            self.rightItem.enabled = NO;
            [self.columnsManager setHidden:YES];
            break;
        case QCStateConnected:
            self.title = [NSString stringWithFormat:@"%@(Tap to get data)",[QCCentralManager shared].connectedPeripheral.name];
            self.rightItem.title = @"Unbind";
            self.rightItem.enabled = YES;
            [self.columnsManager setHidden:NO];
            break;
        case QCStateUnkown:
            break;
        case QCStateDisconnecting:
        case QCStateDisconnected:
            self.rightItem.title = @"Search";
            self.rightItem.enabled = YES;
            [self.columnsManager setHidden:YES];
            break;
    }
}

- (void)didBluetoothState:(QCBluetoothState)state {
    
}

- (void)didConnected:(CBPeripheral *)peripheral     //用户可以返回设备类型
{
    NSLog(@"didConnected");
    self.rightItem.enabled = YES;
    self.title = peripheral.name;
}

- (void)didDisconnecte:(CBPeripheral *)peripheral {
    NSLog(@"didDisconnecte");
    self.title = @"Feature";

    self.rightItem.title = @"Search";
    self.rightItem.enabled = YES;
    [self.columnsManager setHidden:YES];
}

- (void)didFailConnected:(CBPeripheral *)peripheral {
    
    NSLog(@"didFailConnected");
    self.rightItem.enabled = YES;
}


#pragma mark - QGUIColumnsManagerDelegate

- (void)columnsManager:(QGUIColumnsManager *)manager didSelectAction:(NSInteger)actionType {
    switch ((QGDeviceActionType)actionType) {
        case QGDeviceActionTypeGetVersion:
            [self getHardVersionAndFirmVersion];
            break;
        case QGDeviceActionTypeTimeSync:
            [self syncTime];
            break;
        case QGDeviceActionTypeGetBattery:
            [self getBattary];
            break;
        case QGDeviceActionTypeGetMediaInfo:
            [self getMediaInfo];
            break;
        case QGDeviceActionTypeTakePhoto:
            [self takePhoto];
            break;
        case QGDeviceActionTypeToggleVideoRecording:
            [self recordVideo];
            break;
        case QGDeviceActionTypeToggleAudioRecording:
            [self recordAudio];
            break;
        case QGDeviceActionTypeToggleTakeAIImage:
            [self takeAIImage];
            break;
        case QGDeviceActionTypeSystemReboot:
            [self systemReboot];
            break;
        case QGDeviceActionTypeGetTemperature:
            [self getTemperature];
            break;
        case QGDeviceActionTypeReserved:
        default:
            break;
    }
}

#pragma mark - AI Image Setup

- (void)setupAIImageView {
    // Create AI image view as floating overlay
    CGRect aiImageFrame = CGRectMake(20, 120, self.view.frame.size.width - 40, 200);
    self.aiImageView = [[QGAIImageView alloc] initWithFrame:aiImageFrame];

    // Setup callbacks
    __weak typeof(self) weakSelf = self;
    self.aiImageView.onImageTap = ^(NSData *imageData) {
        [weakSelf showFullScreenAIImage:imageData];
    };

    self.aiImageView.onDismiss = ^{
        [weakSelf.aiImageView hideAnimated:YES];
    };

    [self.view addSubview:self.aiImageView];
}

- (void)showFullScreenAIImage:(NSData *)imageData {
    // Validate image data first
    if (!imageData || imageData.length == 0) {
        NSLog(@"Invalid image data provided to showFullScreenAIImage");
        return;
    }

    UIImage *image = [UIImage imageWithData:imageData];
    if (!image) {
        NSLog(@"Failed to create image from data in showFullScreenAIImage");
        return;
    }

    // Create image view controller
    UIViewController *imageViewController = [[UIViewController alloc] init];
    imageViewController.title = @"AI Image";

    // Create image view with proper frame setup
    UIImageView *imageView = [[UIImageView alloc] init];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.backgroundColor = [UIColor blackColor];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;

    [imageViewController.view addSubview:imageView];

    // Set up Auto Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [imageView.topAnchor constraintEqualToAnchor:imageViewController.view.safeAreaLayoutGuide.topAnchor],
        [imageView.leadingAnchor constraintEqualToAnchor:imageViewController.view.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:imageViewController.view.trailingAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:imageViewController.view.safeAreaLayoutGuide.bottomAnchor]
    ]];

    // Add tap to dismiss
    __weak typeof(imageViewController) weakImageViewController = imageViewController;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissImageViewController:)];
    [imageView addGestureRecognizer:tapGesture];
    imageView.userInteractionEnabled = YES;

    // Add close button
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                 target:self
                                                                                 action:@selector(dismissImageViewController:)];
    imageViewController.navigationItem.rightBarButtonItem = doneButton;

    // Present
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:imageViewController];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;

    @try {
        [self presentViewController:navController animated:YES completion:nil];
    } @catch (NSException *exception) {
        NSLog(@"Error presenting image view controller: %@", exception.reason);
    }
}

- (void)dismissImageViewController:(id)sender {
    if (self.presentedViewController) {
        @try {
            [self dismissViewControllerAnimated:YES completion:nil];
        } @catch (NSException *exception) {
            NSLog(@"Error dismissing image view controller: %@", exception.reason);
        }
    }
}

- (void)dealloc {
    // Clean up to prevent memory access issues
    self.columnsManager.delegate = nil;
    [QCSDKManager shareInstance].delegate = nil;
    [QCCentralManager shared].delegate = nil;
}

@end
