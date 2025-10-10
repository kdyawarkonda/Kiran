//
//  QGAIImageView.h
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Dedicated AI image display component that shows/hides AI images
 * independently from the main columns list
 */
@interface QGAIImageView : UIView

// AI Image data
@property (nonatomic, strong, nullable) NSData *aiImageData;
@property (nonatomic, assign) BOOL isVisible;

// Appearance
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, strong) UIColor *borderColor;
@property (nonatomic, assign) CGFloat borderWidth;

// Actions
@property (nonatomic, copy, nullable) void(^onImageTap)(NSData *imageData);
@property (nonatomic, copy, nullable) void(^onDismiss)(void);

// Initialization
- (instancetype)initWithFrame:(CGRect)frame;

// Display control
- (void)showAIImage:(NSData *)imageData animated:(BOOL)animated;
- (void)hideAnimated:(BOOL)animated;
- (void)clearImage;

@end

NS_ASSUME_NONNULL_END