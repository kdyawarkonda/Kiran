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

#import "QCScanViewController.h"
#import "QCCentralManager.h"
#import "QGMediaInfoManager.h"
#import "QGUIColumnsManager.h"

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
    self.columnsManager.aiImageData = imageData;
    [self.columnsManager reloadData];
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

- (void)setTime {
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
    [self.columnsManager clearAIImage];

    //- (void)didReceiveAIChatImageData:(NSData *)imageData
    [QCSDKCmdCreator setDeviceMode:(QCOperatorDeviceModeAIPhoto) success:^{
        NSLog(@"AI Image capture initiated");
    } fail:^(NSInteger mode) {
        NSLog(@"set fail,current device model:%zd",mode);
    }];
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
        case QGDeviceActionTypeSetTime:
            [self setTime];
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
        case QGDeviceActionTypeReserved:
        default:
            break;
    }
}

- (void)columnsManager:(QGUIColumnsManager *)manager didSelectAIImage:(NSData *)imageData {
    // Show options for the AI image
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AI Image Options"
                                                                   message:@"What would you like to do with this AI image?"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *viewAction = [UIAlertAction actionWithTitle:@"View Full Image"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        [self showFullScreenAIImage:imageData];
    }];

    UIAlertAction *clearAction = [UIAlertAction actionWithTitle:@"Clear Image"
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(UIAlertAction * _Nonnull action) {
        [manager clearAIImage];
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [alert addAction:viewAction];
    [alert addAction:clearAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFullScreenAIImage:(NSData *)imageData {
    UIImage *image = [UIImage imageWithData:imageData];
    if (!image) return;

    // Create image view controller
    UIViewController *imageViewController = [[UIViewController alloc] init];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:imageViewController.view.bounds];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.backgroundColor = [UIColor blackColor];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [imageViewController.view addSubview:imageView];

    // Add tap to dismiss
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:imageViewController action:@selector(dismissViewControllerAnimated:completion:)];
    [imageView addGestureRecognizer:tapGesture];
    imageView.userInteractionEnabled = YES;

    // Add close button
    imageViewController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:imageViewController action:@selector(dismissViewControllerAnimated:completion:)];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:imageViewController];
    [self presentViewController:navController animated:YES completion:nil];
}

@end
