//
//  GlassesMediaDownloader.h
//  QCSDKDemo
//
//  Coordinates Wi-Fi credential requests, hotspot connection, manifest
//  retrieval, and media downloads from the glasses device. The downloader is
//  intentionally lightweight and avoids synchronous blocking primitives.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GlassesMediaDownloaderStatusHandler)(NSString *status, UIImage * _Nullable previewImage);
typedef void (^GlassesMediaDownloaderCompletionHandler)(NSError * _Nullable error);

@interface GlassesMediaDownloader : NSObject

- (instancetype)initWithStatusHandler:(GlassesMediaDownloaderStatusHandler)statusHandler;

- (void)startDownloadWithCompletion:(GlassesMediaDownloaderCompletionHandler)completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
