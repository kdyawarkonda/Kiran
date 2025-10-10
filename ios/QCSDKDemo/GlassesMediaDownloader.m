//
//  GlassesMediaDownloader.m
//  QCSDKDemo
//
//  Coordinates the Wi-Fi transfer workflow: requesting credentials,
//  connecting to the hotspot, pulling the manifest, and downloading the
//  referenced media files. The implementation favors clarity and
//  predictability over overly aggressive retry behaviour.
//

#import "GlassesMediaDownloader.h"

#import "GlassesWiFiHandler.h"

static NSString * const GlassesMediaDownloaderErrorDomain = @"GlassesMediaDownloaderError";
static const NSUInteger kManifestMaxRetries = 2; // additional attempts after the first failure
static const NSTimeInterval kManifestRetryDelay = 0.75; // base delay between manifest retries

typedef NS_ENUM(NSInteger, GlassesMediaDownloaderErrorCode) {
    GlassesMediaDownloaderErrorCodeBusy = 1,
    GlassesMediaDownloaderErrorCodeCancelled,
    GlassesMediaDownloaderErrorCodeCredentials,
    GlassesMediaDownloaderErrorCodeConnection,
    GlassesMediaDownloaderErrorCodeManifest,
    GlassesMediaDownloaderErrorCodeDownload,
};

@interface GlassesMediaDownloader ()

@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) GlassesMediaDownloaderStatusHandler statusHandler;
@property (nonatomic, copy) GlassesMediaDownloaderCompletionHandler completionHandler;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, copy) NSString *ssid;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *deviceIP;

@end

@implementation GlassesMediaDownloader

- (instancetype)initWithStatusHandler:(GlassesMediaDownloaderStatusHandler)statusHandler {
    self = [super init];
    if (self) {
        _statusHandler = [statusHandler copy];
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INITIATED,
                                                                             0);
        _workQueue = dispatch_queue_create("com.heyycyan.qcsdk.mediadownloader", attr);
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
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)startDownloadWithCompletion:(GlassesMediaDownloaderCompletionHandler)completion {
    dispatch_async(self.workQueue, ^{
        if (self.running) {
            NSError *error = [self errorWithCode:GlassesMediaDownloaderErrorCodeBusy description:@"A transfer is already in progress."];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
            return;
        }

        self.running = YES;
        self.cancelled = NO;
        self.completionHandler = [completion copy];
        [self updateStatus:@"Requesting Wi-Fi credentials..." preview:nil];
        [self requestCredentials];
    });
}

- (void)cancel {
    dispatch_async(self.workQueue, ^{
        if (!self.running) { return; }
        self.cancelled = YES;
        [self updateStatus:@"Cancelling transfer..." preview:nil];
        [[GlassesWiFiHandler sharedHandler] cancelCurrentOperation];
        [self finishWithError:[self errorWithCode:GlassesMediaDownloaderErrorCodeCancelled description:@"Transfer cancelled"]];
    });
}

#pragma mark - Flow

- (void)requestCredentials {
    __weak typeof(self) weakSelf = self;
    [[GlassesWiFiHandler sharedHandler] requestWiFiCredentialsWithStatusCallback:^(GlassesWiFiHandlerState state, NSString *status, UIImage * _Nullable previewImage) {
        [weakSelf updateStatus:status preview:previewImage];
    } completion:^(NSString *ssid, NSString *password, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            if (strongSelf.cancelled) { return; }

            if (error || ssid.length == 0) {
                NSError *wrapped = error ?: [strongSelf errorWithCode:GlassesMediaDownloaderErrorCodeCredentials description:@"No SSID returned by device."];
                [strongSelf finishWithError:wrapped];
                return;
            }

            strongSelf.ssid = ssid;
            strongSelf.password = password;
            [strongSelf updateStatus:[NSString stringWithFormat:@"Preparing to join %@", ssid]
                             preview:nil];
            [strongSelf connectToHotspot];
        });
    }];
}

- (void)connectToHotspot {
    __weak typeof(self) weakSelf = self;
    [[GlassesWiFiHandler sharedHandler] connectToGlassesWiFi:self.ssid
                                                    password:self.password
                                              statusCallback:^(GlassesWiFiHandlerState state, NSString *status, UIImage * _Nullable previewImage) {
        [weakSelf updateStatus:status preview:previewImage];
    } completion:^(BOOL success, NSString * _Nullable deviceIP, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            if (strongSelf.cancelled) { return; }

            if (!success || deviceIP.length == 0) {
                NSError *wrapped = error ?: [strongSelf errorWithCode:GlassesMediaDownloaderErrorCodeConnection description:@"Hotspot connection failed."];
                [strongSelf finishWithError:wrapped];
                return;
            }

            strongSelf.deviceIP = deviceIP;
            [strongSelf updateStatus:[NSString stringWithFormat:@"Connected to %@", deviceIP] preview:nil];
            [strongSelf fetchManifest];
        });
    }];
}

- (void)fetchManifest {
    if (self.deviceIP.length == 0) {
        [self finishWithError:[self errorWithCode:GlassesMediaDownloaderErrorCodeManifest description:@"Device IP missing."]];
        return;
    }

    NSString *manifestURLString = [NSString stringWithFormat:@"http://%@/files/media.config", self.deviceIP];
    NSURL *manifestURL = [NSURL URLWithString:manifestURLString];
    if (!manifestURL) {
        [self finishWithError:[self errorWithCode:GlassesMediaDownloaderErrorCodeManifest description:@"Invalid manifest URL."]];
        return;
    }

    [self updateStatus:@"Downloading manifest..." preview:nil];
    [self fetchManifestFromURL:manifestURL attempt:0];
}

- (void)fetchManifestFromURL:(NSURL *)manifestURL attempt:(NSUInteger)attempt {
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:manifestURL
                                             completionHandler:^(NSData * _Nullable data,
                                                                 NSURLResponse * _Nullable response,
                                                                 NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            if (strongSelf.cancelled) { return; }

            BOOL success = (!error && [strongSelf isHTTPResponseSuccessful:response]);
            if (!success) {
                if ([strongSelf shouldRetryManifestWithError:error response:response attempt:attempt]) {
                    NSUInteger nextAttempt = attempt + 1;
                    NSTimeInterval delay = kManifestRetryDelay * (nextAttempt + 1);
                    [strongSelf updateStatus:@"Waiting for glasses hotspot to finish starting..." preview:nil];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), strongSelf.workQueue, ^{
                        if (!strongSelf.cancelled) {
                            [strongSelf fetchManifestFromURL:manifestURL attempt:nextAttempt];
                        }
                    });
                    return;
                }

                NSError *wrapped = error ?: [strongSelf errorWithCode:GlassesMediaDownloaderErrorCodeManifest description:@"Failed to download manifest."];
                [strongSelf finishWithError:wrapped];
                return;
            }

            NSError *parseError = nil;
            NSArray<NSDictionary *> *entries = [strongSelf parseManifestData:data error:&parseError];
            if (!entries || entries.count == 0) {
                NSError *wrapped = parseError ?: [strongSelf errorWithCode:GlassesMediaDownloaderErrorCodeManifest description:@"Manifest is empty."];
                [strongSelf finishWithError:wrapped];
                return;
            }

            [strongSelf updateStatus:[NSString stringWithFormat:@"Found %lu media items", (unsigned long)entries.count]
                             preview:nil];
            [strongSelf downloadEntries:entries index:0];
        });
    }];
    [task resume];
}

- (BOOL)shouldRetryManifestWithError:(NSError * _Nullable)error
                             response:(NSURLResponse * _Nullable)response
                              attempt:(NSUInteger)attempt {
    if (attempt >= kManifestMaxRetries) {
        return NO;
    }

    if (error) {
        if ([error.domain isEqualToString:NSURLErrorDomain]) {
            switch (error.code) {
                case NSURLErrorTimedOut:
                case NSURLErrorNotConnectedToInternet:
                case NSURLErrorNetworkConnectionLost:
                case NSURLErrorCannotFindHost:
                case NSURLErrorCannotConnectToHost:
                case NSURLErrorDNSLookupFailed:
                    return YES;
                default:
                    break;
            }
        }
        return NO;
    }

    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
        return (status == 502 || status == 503 || status == 504);
    }

    return NO;
}

- (void)downloadEntries:(NSArray<NSDictionary *> *)entries index:(NSUInteger)index {
    if (self.cancelled) { return; }

    if (index >= entries.count) {
        [self updateStatus:@"Media download complete" preview:nil];
        [self finishWithError:nil];
        return;
    }

    NSDictionary *entry = entries[index];
    NSString *relativePath = entry[@"path"] ?: entry[@"url"];
    NSString *filename = entry[@"name"] ?: [relativePath lastPathComponent];

    if (relativePath.length == 0 || filename.length == 0) {
        [self downloadEntries:entries index:index + 1];
        return;
    }

    NSString *urlString = relativePath;
    if (![relativePath hasPrefix:@"http://"] && ![relativePath hasPrefix:@"https://"]) {
        NSString *escapedPath = [relativePath hasPrefix:@"/"] ? relativePath : [@"/" stringByAppendingString:relativePath];
        urlString = [NSString stringWithFormat:@"http://%@%@", self.deviceIP, escapedPath];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self downloadEntries:entries index:index + 1];
        return;
    }

    NSString *status = [NSString stringWithFormat:@"Downloading %@ (%lu/%lu)",
                         filename,
                         (unsigned long)(index + 1),
                         (unsigned long)entries.count];
    [self updateStatus:status preview:nil];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url
                                                     completionHandler:^(NSURL * _Nullable location,
                                                                         NSURLResponse * _Nullable response,
                                                                         NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        dispatch_async(strongSelf.workQueue, ^{
            if (strongSelf.cancelled) { return; }

            if (error || ![strongSelf isHTTPResponseSuccessful:response]) {
                NSError *wrapped = error ?: [strongSelf errorWithCode:GlassesMediaDownloaderErrorCodeDownload description:[NSString stringWithFormat:@"Failed to download %@", filename]];
                [strongSelf finishWithError:wrapped];
                return;
            }

            NSError *persistError = [strongSelf persistDownloadedFileAtLocation:location filename:filename];
            if (persistError) {
                [strongSelf finishWithError:persistError];
                return;
            }

            UIImage *preview = [strongSelf previewImageForFileNamed:filename];
            if (preview) {
                [strongSelf updateStatus:[NSString stringWithFormat:@"Saved %@", filename] preview:preview];
            }

            [strongSelf downloadEntries:entries index:index + 1];
        });
    }];
    [task resume];
}

#pragma mark - Helpers

- (void)updateStatus:(NSString *)status preview:(UIImage * _Nullable)preview {
    if (!self.statusHandler) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusHandler(status, preview);
    });
}

- (void)finishWithError:(NSError * _Nullable)error {
    if (!self.running) { return; }
    self.running = NO;

    GlassesMediaDownloaderCompletionHandler completion = self.completionHandler;
    self.completionHandler = nil;

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error);
        });
    }
}

- (BOOL)isHTTPResponseSuccessful:(NSURLResponse *)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }
    NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
    return status >= 200 && status < 300;
}

- (NSError *)persistDownloadedFileAtLocation:(NSURL *)location filename:(NSString *)filename {
    NSString *directory = [self mediaDirectoryPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *dirError = nil;
    if (![fileManager fileExistsAtPath:directory]) {
        if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&dirError]) {
            return dirError ?: [self errorWithCode:GlassesMediaDownloaderErrorCodeDownload description:@"Failed to create media directory."];
        }
    }

    NSString *targetPath = [directory stringByAppendingPathComponent:filename];

    // Remove any existing file before moving the new one in place.
    if ([fileManager fileExistsAtPath:targetPath]) {
        [fileManager removeItemAtPath:targetPath error:nil];
    }

    NSError *moveError = nil;
    if (![fileManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:targetPath] error:&moveError]) {
        return moveError ?: [self errorWithCode:GlassesMediaDownloaderErrorCodeDownload description:@"Failed to persist downloaded file."];
    }

    return nil;
}

- (NSString *)mediaDirectoryPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject ?: NSTemporaryDirectory();
    return [documents stringByAppendingPathComponent:@"GlassesMedia"];
}

- (UIImage * _Nullable)previewImageForFileNamed:(NSString *)filename {
    NSString *lower = filename.lowercaseString;
    if (![lower hasSuffix:@".jpg"] && ![lower hasSuffix:@".jpeg"] && ![lower hasSuffix:@".png"] && ![lower hasSuffix:@".heic"]) {
        return nil;
    }

    NSString *path = [[self mediaDirectoryPath] stringByAppendingPathComponent:filename];
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) { return nil; }
    return [UIImage imageWithData:data scale:[UIScreen mainScreen].scale];
}

- (NSArray<NSDictionary *> *)parseManifestData:(NSData *)data error:(NSError **)error {
    if (!data) { return nil; }

    NSError *jsonError = nil;
    id manifestObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!manifestObject || ![manifestObject isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = jsonError ?: [self errorWithCode:GlassesMediaDownloaderErrorCodeManifest description:@"Manifest format is invalid."];
        }
        return nil;
    }

    NSDictionary *manifest = (NSDictionary *)manifestObject;
    NSArray *files = manifest[@"files"];
    if (![files isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [self errorWithCode:GlassesMediaDownloaderErrorCodeManifest description:@"Manifest does not contain a files array."];
        }
        return nil;
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

        [entries addObject:@{ @"path" : path, @"name" : name }];
    }

    return entries.copy;
}

- (NSError *)errorWithCode:(GlassesMediaDownloaderErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:GlassesMediaDownloaderErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey : description ?: @"Unknown error" }];
}

@end
