//
//  MediaGalleryViewController.h
//  QCSDKDemo
//
//  Lightweight file browser to inspect media downloaded from the glasses.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MediaGalleryViewController : UITableViewController

@property (nonatomic, copy) NSString *mediaDirectoryPath;

@end

NS_ASSUME_NONNULL_END
