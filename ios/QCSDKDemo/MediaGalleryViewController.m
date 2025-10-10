//
//  MediaGalleryViewController.m
//  QCSDKDemo
//
//  Presents the files downloaded via Wi-Fi transfer using a basic table view
//  with sharing support.
//

#import "MediaGalleryViewController.h"

@interface MediaGalleryViewController ()

@property (nonatomic, strong) NSArray<NSDictionary *> *mediaItems;

@end

@implementation MediaGalleryViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Glasses Media";
    self.tableView.rowHeight = 64.0;
    self.tableView.tableFooterView = [UIView new];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(refreshMediaItems)];

    [self refreshMediaItems];
}

- (void)refreshMediaItems {
    NSString *directory = self.mediaDirectoryPath;
    if (directory.length == 0) {
        self.mediaItems = @[];
        [self.tableView reloadData];
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray<NSString *> *filenames = [fileManager contentsOfDirectoryAtPath:directory error:&error];
    if (error || filenames.count == 0) {
        self.mediaItems = @[];
        [self.tableView reloadData];
        return;
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSString *name in filenames) {
        if ([name hasPrefix:@"."]) { continue; }

        NSString *path = [directory stringByAppendingPathComponent:name];
        NSURL *url = [NSURL fileURLWithPath:path];

        NSDictionary<NSURLResourceKey, id> *resourceValues = [url resourceValuesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                                                   error:nil];
        NSDate *date = resourceValues[NSURLContentModificationDateKey] ?: [NSDate distantPast];
        NSNumber *size = resourceValues[NSURLFileSizeKey] ?: @(0);

        [items addObject:@{
            @"url": url,
            @"name": name,
            @"date": date,
            @"size": size
        }];
    }

    [items sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        NSDate *date1 = obj1[@"date"];
        NSDate *date2 = obj2[@"date"];
        return [date2 compare:date1];
    }];

    self.mediaItems = items.copy;
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.mediaItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MediaCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MediaCell"];
    }

    NSDictionary *item = self.mediaItems[indexPath.row];
    cell.textLabel.text = item[@"name"];

    NSNumber *sizeNumber = item[@"size"];
    NSDate *date = item[@"date"];
    NSString *sizeText = [self formattedFileSize:sizeNumber.unsignedLongLongValue];
    NSString *dateText = [NSDateFormatter localizedStringFromDate:date
                                                        dateStyle:NSDateFormatterShortStyle
                                                        timeStyle:NSDateFormatterShortStyle];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", sizeText, dateText];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *item = self.mediaItems[indexPath.row];
    NSURL *url = item[@"url"];
    if (!url) { return; }

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                                                           applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    }
    [self presentViewController:activity animated:YES completion:nil];
}

#pragma mark - Helpers

- (NSString *)formattedFileSize:(unsigned long long)bytes {
    if (bytes == 0) { return @"0 B"; }

    NSArray<NSString *> *units = @[ @"B", @"KB", @"MB", @"GB" ];
    double size = (double)bytes;
    NSInteger unitIndex = 0;

    while (size >= 1024.0 && unitIndex < units.count - 1) {
        size /= 1024.0;
        unitIndex += 1;
    }

    return [NSString stringWithFormat:@"%.1f %@", size, units[unitIndex]];
}

@end
