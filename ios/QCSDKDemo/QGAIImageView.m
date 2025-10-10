//
//  QGAIImageView.m
//  QCSDKDemo
//
//  Created by Claude on 2025/10/09.
//

#import "QGAIImageView.h"

@interface QGAIImageView ()

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIButton *dismissButton;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;

@end

@implementation QGAIImageView

#pragma mark - Initialization

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    self.layer.cornerRadius = 12.0;
    self.layer.masksToBounds = YES;

    // Default appearance
    _cornerRadius = 12.0;
    _borderColor = [UIColor whiteColor];
    _borderWidth = 2.0;
    _isVisible = NO;

    // Setup image view
    self.imageView = [[UIImageView alloc] init];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.backgroundColor = [UIColor clearColor];
    self.imageView.layer.cornerRadius = 8.0;
    self.imageView.layer.masksToBounds = YES;
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.imageView];

    // Setup dismiss button
    self.dismissButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.dismissButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.dismissButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dismissButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    self.dismissButton.layer.cornerRadius = 12.0;
    self.dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dismissButton addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.dismissButton];

    // Setup tap gesture
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageTapped)];
    [self.imageView addGestureRecognizer:self.tapGesture];
    self.imageView.userInteractionEnabled = YES;

    // Setup constraints
    [self setupConstraints];

    // Initially hidden
    self.alpha = 0.0;
    self.hidden = YES;
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // Image view constraints
        [self.imageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:40],
        [self.imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [self.imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [self.imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],

        // Dismiss button constraints
        [self.dismissButton.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [self.dismissButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [self.dismissButton.widthAnchor constraintEqualToConstant:24],
        [self.dismissButton.heightAnchor constraintEqualToConstant:24]
    ]];
}

#pragma mark - Display Control

- (void)showAIImage:(NSData *)imageData animated:(BOOL)animated {
    if (!imageData || imageData.length == 0) {
        NSLog(@"Cannot show AI image: invalid data");
        return;
    }

    self.aiImageData = imageData;

    UIImage *image = [UIImage imageWithData:imageData];
    if (!image) {
        NSLog(@"Cannot show AI image: failed to create image from data");
        return;
    }

    self.imageView.image = image;
    self.hidden = NO;

    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 1.0;
        }];
    } else {
        self.alpha = 1.0;
    }

    self.isVisible = YES;
}

- (void)hideAnimated:(BOOL)animated {
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.hidden = YES;
            self.isVisible = NO;
        }];
    } else {
        self.alpha = 0.0;
        self.hidden = YES;
        self.isVisible = NO;
    }
}

- (void)clearImage {
    self.aiImageData = nil;
    self.imageView.image = nil;
    [self hideAnimated:YES];
}

#pragma mark - Appearance

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
    self.imageView.layer.cornerRadius = cornerRadius - 4.0;
}

- (void)setBorderColor:(UIColor *)borderColor {
    _borderColor = borderColor;
    self.layer.borderColor = borderColor.CGColor;
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    _borderWidth = borderWidth;
    self.layer.borderWidth = borderWidth;
}

#pragma mark - Actions

- (void)imageTapped {
    if (self.onImageTap && self.aiImageData) {
        self.onImageTap(self.aiImageData);
    }
}

- (void)dismissTapped {
    if (self.onDismiss) {
        self.onDismiss();
    } else {
        [self hideAnimated:YES];
    }
}

#pragma mark - Touch Handling

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // Allow dismissing by tapping outside the image
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];

    if (!CGRectContainsPoint(self.imageView.frame, location)) {
        [self hideAnimated:YES];
    }
}

@end