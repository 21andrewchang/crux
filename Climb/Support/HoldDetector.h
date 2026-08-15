#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Output of one hold-detection run: the normalized wall photo the detector actually
/// worked on (orientation fixed, downscaled), and the flat-color route render built
/// from the holds that matched the route color.
@interface HoldDetectionResult : NSObject

@property (nonatomic, readonly) UIImage *wallImage;
@property (nonatomic, readonly) UIImage *routeImage;
/// Holds that matched the route color and made it into the render.
@property (nonatomic, readonly) NSInteger routeHoldCount;
/// Every hold-shaped blob the detector kept, any color.
@property (nonatomic, readonly) NSInteger totalHoldCount;

@end

/// On-device port of the hybrid hold-detection pipeline prototyped in
/// scripts/holds/pipeline.py + hybrid.py, finished with the vector-trace render from
/// final_layer.py. The classical stage (mean-shift + per-channel Canny edges,
/// color-anomaly candidates, edges as hard walls) proposes prompt points; SAM 2.1
/// Small (Core ML, bundled in Climb/ML) refines each prompt into a smooth mask with
/// the classical blob as fallback for tiny chips; then dedup, a seeded per-hold
/// color pass, and Chaikin-smoothed flat shapes on black.
@interface HoldDetector : NSObject

/// Color keys the route pass understands, in display order.
@property (class, nonatomic, readonly) NSArray<NSString *> *supportedColors;

/// Runs the full pipeline. Slow (a few seconds) — call off the main thread.
+ (nullable HoldDetectionResult *)detectRouteIn:(UIImage *)photo
                                          color:(NSString *)colorName
    NS_SWIFT_NAME(detectRoute(in:color:));

@end

NS_ASSUME_NONNULL_END
