// OpenCV must come before any Apple header so its symbols dodge the NO/YES macros.
#import <opencv2/opencv.hpp>
#import "HoldDetector.h"
#import <CoreML/CoreML.h>

#include <algorithm>
#include <cmath>
#include <map>
#include <string>
#include <vector>

using cv::Mat;

// Hue gates (OpenCV H, 0–180) that pick the seed holds for each route color. Red
// wraps around the hue circle, so it gets both ends.
static const std::map<std::string, std::vector<std::pair<double, double>>> kHueRanges = {
    {"red", {{0, 10}, {170, 180}}},
    {"orange", {{10, 18}}},
    {"yellow", {{18, 32}}},
    {"green", {{36, 85}}},
    {"blue", {{90, 130}}},
    {"purple", {{130, 158}}},
    {"pink", {{158, 178}}},
};

// Flat fill per route color (BGR), matching the iOS system palette the app's climb
// tags already use, so the render reads as the same color as the heading chip.
static const std::map<std::string, cv::Vec3b> kFillBGR = {
    {"red", {58, 69, 255}},      // #FF453A
    {"orange", {10, 159, 255}},  // #FF9F0A
    {"yellow", {10, 214, 255}},  // #FFD60A
    {"green", {88, 209, 48}},    // #30D158
    {"blue", {255, 132, 10}},    // #0A84FF
    {"purple", {242, 90, 191}},  // #BF5AF2
    {"pink", {95, 55, 255}},     // #FF375F
};

/// Redraws the photo upright at detection resolution: bakes in the EXIF orientation
/// and caps the longest side so mean-shift stays a few seconds, not a minute.
static UIImage *normalizedPhoto(UIImage *photo, CGFloat maxSide) {
    CGFloat longest = MAX(photo.size.width, photo.size.height);
    if (longest < 1) return nil;
    CGFloat scale = MIN((CGFloat)1, maxSide / longest);
    CGSize size = CGSizeMake(round(photo.size.width * scale), round(photo.size.height * scale));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [photo drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

static Mat bgrFromUIImage(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) return Mat();
    int w = (int)CGImageGetWidth(cg), h = (int)CGImageGetHeight(cg);
    Mat rgba(h, w, CV_8UC4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba.data, w, h, 8, rgba.step[0], space,
                                             kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
    CGColorSpaceRelease(space);
    if (!ctx) return Mat();
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    Mat bgr;
    cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);
    return bgr;
}

static UIImage *uiImageFromBGR(const Mat &bgr) {
    Mat rgba;
    cv::cvtColor(bgr, rgba, cv::COLOR_BGR2RGBA);
    NSData *data = [NSData dataWithBytes:rgba.data length:rgba.total() * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef cg = CGImageCreate(rgba.cols, rgba.rows, 8, 32, rgba.step[0], space,
                                  kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault,
                                  provider, NULL, false, kCGRenderingIntentDefault);
    UIImage *image = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

/// np.median semantics: even-length inputs average the two middle values.
static double medianOfVector(std::vector<double> &values) {
    if (values.empty()) return NAN;
    size_t mid = values.size() / 2;
    std::nth_element(values.begin(), values.begin() + mid, values.end());
    double m = values[mid];
    if (values.size() % 2 == 0) {
        double below = *std::max_element(values.begin(), values.begin() + mid);
        m = (m + below) / 2.0;
    }
    return m;
}

static double medianOfMat(const Mat &m) {
    long hist[256] = {0};
    for (int y = 0; y < m.rows; y++) {
        const uchar *row = m.ptr<uchar>(y);
        for (int x = 0; x < m.cols; x++) hist[row[x]]++;
    }
    long total = (long)m.total(), seen = 0;
    for (int i = 0; i < 256; i++) {
        seen += hist[i];
        if (seen * 2 >= total) return i;
    }
    return 127;
}

/// A hold mask stored as its bounding box plus the cropped 0/255 patch, so a couple
/// hundred candidate masks never hold a couple hundred full-frame images in memory.
struct MaskROI {
    cv::Rect box;
    Mat crop;
    int area = 0;
};

static MaskROI roiFromMask(const Mat &mask) {
    MaskROI roi;
    roi.box = cv::boundingRect(mask);
    if (roi.box.empty()) return roi;
    roi.crop = mask(roi.box).clone();
    roi.area = cv::countNonZero(roi.crop);
    return roi;
}

static int overlapArea(const MaskROI &a, const MaskROI &b) {
    cv::Rect r = a.box & b.box;
    if (r.empty()) return 0;
    Mat ac = a.crop(cv::Rect(r.x - a.box.x, r.y - a.box.y, r.width, r.height));
    Mat bc = b.crop(cv::Rect(r.x - b.box.x, r.y - b.box.y, r.width, r.height));
    return cv::countNonZero(ac & bc);
}

/// SAM's per-mask cleanup from the prototype: reject stringy masks, then keep only
/// the outer contour so chalk cracks inside a hold don't punch holes in it.
static bool finishMask(const Mat &binFull, MaskROI &out) {
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(binFull, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    if (contours.empty()) return false;
    auto &c = *std::max_element(contours.begin(), contours.end(),
                                [](const std::vector<cv::Point> &a, const std::vector<cv::Point> &b) {
                                    return cv::contourArea(a) < cv::contourArea(b);
                                });
    std::vector<cv::Point> hull;
    cv::convexHull(c, hull);
    double hullArea = cv::contourArea(hull);
    if (hullArea <= 0 || cv::countNonZero(binFull) / hullArea < 0.6) return false;
    Mat filled = Mat::zeros(binFull.size(), CV_8U);
    cv::drawContours(filled, std::vector<std::vector<cv::Point>>{c}, -1, 255, cv::FILLED);
    out.box = cv::boundingRect(c);
    out.crop = filled(out.box).clone();
    out.area = cv::countNonZero(out.crop);
    return out.area > 0;
}

/// Two prompt points on the same hold give near-identical masks; keep the largest.
static void dedupMasks(std::vector<MaskROI> &masks) {
    std::sort(masks.begin(), masks.end(),
              [](const MaskROI &a, const MaskROI &b) { return a.area > b.area; });
    std::vector<MaskROI> keep;
    for (auto &m : masks) {
        bool fresh = true;
        for (auto &k : keep) {
            if (overlapArea(m, k) >= 0.6 * std::max(m.area, k.area)) {
                fresh = false;
                break;
            }
        }
        if (fresh) keep.push_back(std::move(m));
    }
    masks = std::move(keep);
}

/// The seeded color pass shared by every mask source. Color comes from the mask's
/// intersection with the chroma-anomaly map — pixels already known to differ from
/// the wall — so slightly-fat SAM masks don't dilute a small chip toward the wall
/// color (an eroded core is the fallback). Confident in-gate holds seed a Lab hue
/// angle, and membership is angular distance from that seed — robust to gym lighting.
static std::vector<size_t> colorPass(const std::vector<MaskROI> &rois, const Mat &hsv,
                                     const Mat &lab, const Mat &chroma,
                                     const std::string &key) {
    Mat ones5 = Mat::ones(5, 5, CV_8U);
    struct HoldColor { double h, s, v, L, mag, ang; };
    std::vector<HoldColor> colors;
    colors.reserve(rois.size());
    for (auto &roi : rois) {
        Mat core = roi.crop & chroma(roi.box);
        if (cv::countNonZero(core) < 20) cv::erode(roi.crop, core, ones5);
        if (cv::countNonZero(core) < 20) core = roi.crop;
        std::vector<double> hv, sv, vv, Lv, av, bv;
        for (int y = 0; y < roi.box.height; y++) {
            const uchar *cp = core.ptr<uchar>(y);
            const cv::Vec3b *hp = hsv.ptr<cv::Vec3b>(roi.box.y + y);
            const cv::Vec3b *lp = lab.ptr<cv::Vec3b>(roi.box.y + y);
            for (int x = 0; x < roi.box.width; x++) {
                if (!cp[x]) continue;
                hv.push_back(hp[roi.box.x + x][0]);
                sv.push_back(hp[roi.box.x + x][1]);
                vv.push_back(hp[roi.box.x + x][2]);
                Lv.push_back(lp[roi.box.x + x][0]);
                av.push_back(lp[roi.box.x + x][1]);
                bv.push_back(lp[roi.box.x + x][2]);
            }
        }
        double a = medianOfVector(av) - 128, b = medianOfVector(bv) - 128;
        colors.push_back({medianOfVector(hv), medianOfVector(sv), medianOfVector(vv),
                          medianOfVector(Lv), std::hypot(a, b),
                          std::atan2(b, a) * 180.0 / M_PI});
    }

    const auto &ranges = kHueRanges.at(key);
    auto inHue = [&](double hh) {
        for (auto &r : ranges) {
            if (hh >= r.first && hh <= r.second) return true;
        }
        return false;
    };
    std::vector<double> seedAngs;
    for (auto &s : colors) {
        if (inHue(s.h) && s.s > 140 && s.v > 90) seedAngs.push_back(s.ang);
    }

    std::vector<size_t> picked;
    if (!seedAngs.empty()) {
        double seed = medianOfVector(seedAngs);
        for (size_t i = 0; i < colors.size(); i++) {
            auto &s = colors[i];
            if (s.mag < 22 && s.L > 170) continue;  // warm-lit white: route angle, weak chroma
            double d = s.ang - seed;
            if (s.mag > 15 && d >= -10 && d <= 18 && s.L > 40) {
                if (d > 8 && s.L < 80) continue;  // lime chips are light; olive holds are dark
                picked.push_back(i);
            }
        }
    } else {
        // No confident seed hold in frame — fall back to a plain hue gate rather
        // than returning nothing.
        for (size_t i = 0; i < colors.size(); i++) {
            auto &s = colors[i];
            if (inHue(s.h) && s.s > 80 && s.v > 60) picked.push_back(i);
        }
    }
    return picked;
}

// MARK: - SAM 2.1 (Core ML)

/// One loaded copy of the SAM 2.1 Small Core ML models (image encoder, prompt
/// encoder, mask decoder). Nil when the .mlpackage resources are missing from the
/// bundle — the detector then degrades to the classical pipeline alone.
@interface SAMSession : NSObject {
   @public
    MLModel *_encoder;
    MLModel *_promptEncoder;
    MLModel *_maskDecoder;
    MLMultiArray *_embedding;
    MLMultiArray *_feats0;
    MLMultiArray *_feats1;
}
+ (nullable SAMSession *)sharedSession;
@end

@implementation SAMSession

static MLModel *loadModel(NSString *name, MLModelConfiguration *config) {
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"mlmodelc"];
    if (!url) return nil;
    return [MLModel modelWithContentsOfURL:url configuration:config error:nil];
}

+ (nullable SAMSession *)sharedSession {
    static SAMSession *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MLModelConfiguration *config = [MLModelConfiguration new];
        config.computeUnits = MLComputeUnitsAll;
        MLModel *encoder = loadModel(@"SAM2_1SmallImageEncoderFLOAT16", config);
        MLModel *prompt = loadModel(@"SAM2_1SmallPromptEncoderFLOAT16", config);
        MLModel *decoder = loadModel(@"SAM2_1SmallMaskDecoderFLOAT16", config);
        if (encoder && prompt && decoder) {
            shared = [SAMSession new];
            shared->_encoder = encoder;
            shared->_promptEncoder = prompt;
            shared->_maskDecoder = decoder;
        }
    });
    return shared;
}

/// Encodes the working image once; every prompt afterwards reuses the embedding.
/// SAM's own preprocessing is a plain (aspect-squashing) resize to 1024×1024.
- (BOOL)setImage:(const Mat &)bgr {
    Mat resized, bgra;
    cv::resize(bgr, resized, cv::Size(1024, 1024), 0, 0, cv::INTER_AREA);
    cv::cvtColor(resized, bgra, cv::COLOR_BGR2BGRA);

    CVPixelBufferRef buffer = NULL;
    NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVPixelBufferCreate(kCFAllocatorDefault, 1024, 1024, kCVPixelFormatType_32BGRA,
                        (__bridge CFDictionaryRef)attrs, &buffer);
    if (!buffer) return NO;
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    for (int y = 0; y < 1024; y++) {
        memcpy(base + y * stride, bgra.ptr(y), 1024 * 4);
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);

    NSError *error;
    MLDictionaryFeatureProvider *input = [[MLDictionaryFeatureProvider alloc]
        initWithDictionary:@{@"image" : [MLFeatureValue featureValueWithPixelBuffer:buffer]}
                     error:&error];
    id<MLFeatureProvider> output = input ? [_encoder predictionFromFeatures:input error:&error] : nil;
    CVPixelBufferRelease(buffer);
    if (!output) return NO;
    _embedding = [output featureValueForName:@"image_embedding"].multiArrayValue;
    _feats0 = [output featureValueForName:@"feats_s0"].multiArrayValue;
    _feats1 = [output featureValueForName:@"feats_s1"].multiArrayValue;
    return _embedding && _feats0 && _feats1;
}

/// Decodes one foreground point (working-image coordinates) into SAM's three mask
/// candidates as 256×256 float logit maps plus their predicted IoU scores.
- (BOOL)decodePoint:(cv::Point2f)point
          imageSize:(cv::Size)size
             logits:(std::vector<Mat> &)outLogits
             scores:(std::vector<float> &)outScores {
    NSError *error;
    MLMultiArray *points = [[MLMultiArray alloc] initWithShape:@[ @1, @1, @2 ]
                                                      dataType:MLMultiArrayDataTypeFloat32
                                                         error:&error];
    MLMultiArray *labels = [[MLMultiArray alloc] initWithShape:@[ @1, @1 ]
                                                      dataType:MLMultiArrayDataTypeFloat32
                                                         error:&error];
    if (!points || !labels) return NO;
    points[0] = @(point.x / size.width * 1024.0);
    points[1] = @(point.y / size.height * 1024.0);
    labels[0] = @1;  // foreground

    MLDictionaryFeatureProvider *promptInput = [[MLDictionaryFeatureProvider alloc]
        initWithDictionary:@{@"points" : points, @"labels" : labels}
                     error:&error];
    id<MLFeatureProvider> prompt =
        promptInput ? [_promptEncoder predictionFromFeatures:promptInput error:&error] : nil;
    MLMultiArray *sparse = [prompt featureValueForName:@"sparse_embeddings"].multiArrayValue;
    MLMultiArray *dense = [prompt featureValueForName:@"dense_embeddings"].multiArrayValue;
    if (!sparse || !dense) return NO;

    MLDictionaryFeatureProvider *decodeInput = [[MLDictionaryFeatureProvider alloc]
        initWithDictionary:@{
            @"image_embedding" : _embedding,
            @"sparse_embedding" : sparse,
            @"dense_embedding" : dense,
            @"feats_s0" : _feats0,
            @"feats_s1" : _feats1,
        }
        error:&error];
    id<MLFeatureProvider> decoded =
        decodeInput ? [_maskDecoder predictionFromFeatures:decodeInput error:&error] : nil;
    MLMultiArray *masks = [decoded featureValueForName:@"low_res_masks"].multiArrayValue;
    MLMultiArray *scores = [decoded featureValueForName:@"scores"].multiArrayValue;
    if (!masks || !scores) return NO;

    long s1 = masks.strides[1].longValue, s2 = masks.strides[2].longValue,
         s3 = masks.strides[3].longValue;
    outLogits.assign(3, Mat());
    [masks getBytesWithHandler:^(const void *bytes, NSInteger byteSize) {
        for (int k = 0; k < 3; k++) {
            Mat m(256, 256, CV_32F);
            if (masks.dataType == MLMultiArrayDataTypeFloat16) {
                const __fp16 *p = (const __fp16 *)bytes;
                for (int y = 0; y < 256; y++) {
                    float *row = m.ptr<float>(y);
                    for (int x = 0; x < 256; x++) row[x] = p[k * s1 + y * s2 + x * s3];
                }
            } else {
                const float *p = (const float *)bytes;
                for (int y = 0; y < 256; y++) {
                    float *row = m.ptr<float>(y);
                    for (int x = 0; x < 256; x++) row[x] = p[k * s1 + y * s2 + x * s3];
                }
            }
            outLogits[k] = m;
        }
    }];
    outScores.assign(3, 0);
    for (int k = 0; k < 3; k++) {
        outScores[k] = [scores objectForKeyedSubscript:@[ @0, @(k) ]].floatValue;
    }
    return YES;
}

@end

// MARK: - Detector

@implementation HoldDetectionResult

- (instancetype)initWithWall:(UIImage *)wall
                       route:(UIImage *)route
                      picked:(NSInteger)picked
                       total:(NSInteger)total {
    if ((self = [super init])) {
        _wallImage = wall;
        _routeImage = route;
        _routeHoldCount = picked;
        _totalHoldCount = total;
    }
    return self;
}

@end

@implementation HoldDetector

+ (NSArray<NSString *> *)supportedColors {
    return @[ @"red", @"orange", @"yellow", @"green", @"blue", @"purple", @"pink" ];
}

+ (nullable HoldDetectionResult *)detectRouteIn:(UIImage *)photo color:(NSString *)colorName {
    std::string key = colorName.lowercaseString.UTF8String;
    if (kHueRanges.find(key) == kHueRanges.end()) key = "yellow";

    UIImage *wall = normalizedPhoto(photo, 1600);
    if (!wall) return nil;
    Mat img = bgrFromUIImage(wall);
    if (img.empty()) return nil;
    const int w = img.cols, h = img.rows;

    // --- edges: mean-shift + per-channel Canny ---
    // A yellow hold on a teal wall has no luminance edge but a big chroma edge, so
    // Canny runs per Lab channel and ORs. Mean-shift at half res posterizes the wall
    // into flat regions first — chalk/texture noise flattens out, boundaries survive.
    Mat halfImg, shifted, msLab;
    cv::resize(img, halfImg, cv::Size(w / 2, h / 2), 0, 0, cv::INTER_AREA);
    cv::pyrMeanShiftFiltering(halfImg, shifted, 12, 24);
    cv::cvtColor(shifted, msLab, cv::COLOR_BGR2Lab);
    Mat edges = Mat::zeros(shifted.size(), CV_8U);
    {
        std::vector<Mat> channels;
        cv::split(msLab, channels);
        for (auto &c : channels) {
            Mat e;
            cv::Canny(c, e, 30, 90);
            edges |= e;
        }
    }
    cv::resize(edges, edges, cv::Size(w, h), 0, 0, cv::INTER_NEAREST);
    Mat ones5 = Mat::ones(5, 5, CV_8U);
    Mat edgeNear;
    cv::dilate(edges, edgeNear, ones5);  // tolerance band for "outline sits on an edge"

    // Clutter map stays on luminance edges: wall texture is chroma-noisy but
    // luminance-quiet, while ceiling beams and the climber are busy in luminance.
    Mat gray, smooth, edgesMono, density;
    cv::cvtColor(img, gray, cv::COLOR_BGR2GRAY);
    cv::bilateralFilter(gray, smooth, 9, 60, 60);
    double v = medianOfMat(smooth);
    cv::Canny(smooth, edgesMono, 0.66 * v, 1.6 * v);
    Mat monoF;
    edgesMono.convertTo(monoF, CV_32F, 1.0 / 255.0);
    cv::blur(monoF, density, cv::Size(121, 121));

    // --- hold candidates: local color anomalies vs the wall ---
    // The "wall color" at each pixel is a heavy median blur of quarter-res Lab; a
    // hold is anywhere far from that background in weighted Lab distance.
    Mat labFull, bgSmall, bg;
    cv::cvtColor(img, labFull, cv::COLOR_BGR2Lab);
    cv::resize(labFull, bgSmall, cv::Size(), 0.25, 0.25, cv::INTER_AREA);
    {
        std::vector<Mat> channels;
        cv::split(bgSmall, channels);
        for (auto &c : channels) cv::medianBlur(c, c, 61);
        cv::merge(channels, bgSmall);
    }
    cv::resize(bgSmall, bg, cv::Size(w, h), 0, 0, cv::INTER_LINEAR);

    Mat dist(h, w, CV_32F);
    for (int y = 0; y < h; y++) {
        const cv::Vec3b *lp = labFull.ptr<cv::Vec3b>(y);
        const cv::Vec3b *bp = bg.ptr<cv::Vec3b>(y);
        float *dp = dist.ptr<float>(y);
        for (int x = 0; x < w; x++) {
            float dL = 0.35f * ((float)lp[x][0] - (float)bp[x][0]);
            float da = (float)lp[x][1] - (float)bp[x][1];
            float db = (float)lp[x][2] - (float)bp[x][2];
            dp[x] = std::sqrt(dL * dL + da * da + db * db);
        }
    }
    Mat ell3 = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(3, 3));
    Mat ell7 = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(7, 7));
    Mat ell13 = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(13, 13));
    Mat rawChroma = dist > 16;
    Mat chromaCand;
    cv::morphologyEx(rawChroma, chromaCand, cv::MORPH_OPEN, ell7);
    Mat cand;
    cv::morphologyEx(rawChroma, cand, cv::MORPH_OPEN, ell7);
    cv::morphologyEx(cand, cand, cv::MORPH_CLOSE, ell13);

    // Second candidate source: closed contours in the edge map itself, so holds
    // whose color hugs the wall (weak chroma anomaly) still get proposed.
    Mat closedEdges, edgeCand = Mat::zeros(h, w, CV_8U);
    cv::morphologyEx(edges, closedEdges, cv::MORPH_CLOSE, ell7);
    {
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(closedEdges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
        for (auto &c : contours) {
            double a = cv::contourArea(c);
            if (a > 30 && a < 0.04 * h * w) {
                cv::drawContours(edgeCand, std::vector<std::vector<cv::Point>>{c}, -1, 255, cv::FILLED);
            }
        }
    }
    cv::morphologyEx(edgeCand, edgeCand, cv::MORPH_OPEN, ell3);
    cand |= edgeCand;

    // --- candidate blobs; edges are hard walls ---
    // Cut candidate blobs along real edges before labeling: two touching holds
    // merged by morphology get separated again by the boundary the edge map drew
    // between them. Every size-gated blob becomes a SAM prompt, even ones the shape
    // tests reject — SAM filters junk better than the shape tests can. Blobs that
    // do pass regrow (never across an edge) and double as SAM's fallback masks.
    Mat candNoEdge = cand & ~edges;
    Mat labels, stats, cents;
    int n = cv::connectedComponentsWithStats(candNoEdge, labels, stats, cents, 4);
    std::vector<cv::Point2f> prompts;
    std::map<size_t, Mat> keptByPrompt;  // prompt index → grown classical mask
    for (int i = 1; i < n; i++) {
        int area = stats.at<int>(i, cv::CC_STAT_AREA);
        if (!(area > 40 && area < 0.04 * h * w)) continue;
        prompts.push_back(cv::Point2f((float)cents.at<double>(i, 0), (float)cents.at<double>(i, 1)));
        Mat blob = (labels == i);
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(blob, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
        if (contours.empty()) continue;
        auto &c = *std::max_element(contours.begin(), contours.end(),
                                    [](const std::vector<cv::Point> &a, const std::vector<cv::Point> &b) {
                                        return cv::contourArea(a) < cv::contourArea(b);
                                    });
        std::vector<cv::Point> hull;
        cv::convexHull(c, hull);
        double hullArea = cv::contourArea(hull);
        double solidity = hullArea > 0 ? area / hullArea : 0;
        cv::RotatedRect rect = cv::minAreaRect(c);
        double elong = std::max(rect.size.width, rect.size.height) /
                       std::max(std::min(rect.size.width, rect.size.height), 1.0f);
        double onEdge = 0;
        for (auto &p : c) onEdge += edgeNear.at<uchar>(p.y, p.x) > 0 ? 1 : 0;
        onEdge /= (double)c.size();
        int cx = std::max(0, std::min(w - 1, (int)cents.at<double>(i, 0)));
        int cy = std::max(0, std::min(h - 1, (int)cents.at<double>(i, 1)));
        double clutter = density.at<float>(cy, cx);
        bool chromaBacked = cv::countNonZero(blob & chromaCand) > 0.3 * area;
        bool ok = chromaBacked
            ? (solidity > 0.5 && elong < 5 && onEdge > 0.30 && clutter < 0.12)
            : (solidity > 0.6 && elong < 4 && onEdge > 0.55 && clutter < 0.08);
        if (!ok) continue;
        Mat grown;
        cv::dilate(blob, grown, ones5);
        grown &= candNoEdge;
        keptByPrompt[prompts.size() - 1] = grown;
    }

    std::vector<MaskROI> classicalROIs;
    for (auto &entry : keptByPrompt) {
        MaskROI roi = roiFromMask(entry.second);
        if (roi.area > 0) classicalROIs.push_back(std::move(roi));
    }

    Mat hsv;
    cv::cvtColor(img, hsv, cv::COLOR_BGR2HSV);

    // --- SAM refinement (hybrid.py): prompt SAM only at classical candidates ---
    // SAM's smooth crack-free masks replace the jagged classical blobs; the
    // classical mask stays as the fallback for tiny chips SAM declines.
    SAMSession *sam = [SAMSession sharedSession];
    std::vector<MaskROI> sources;
    NSInteger totalHolds = 0;
    bool samRan = false;
    if (sam && [sam setImage:img]) {
        samRan = true;
        std::vector<MaskROI> refined;
        size_t promptCount = std::min(prompts.size(), (size_t)500);
        for (size_t pi = 0; pi < promptCount; pi++) {
            std::vector<Mat> logits;
            std::vector<float> scores;
            int pick = -1;
            if ([sam decodePoint:prompts[pi] imageSize:cv::Size(w, h) logits:logits scores:scores]) {
                // Smallest mask above a score floor: point prompts often offer
                // hold / hold+wall-panel / whole-wall — we want the hold. Area
                // gates are the prototype's, rescaled to the 256×256 logit grid.
                // SAM 2.1 Small predicts lower IoU on small holds than the
                // prototype's SAM 1 ViT-B did; 0.5 was validated against the
                // prototype's reference run on the Mac harness.
                int areas[3];
                std::vector<int> order{0, 1, 2};
                for (int k = 0; k < 3; k++) areas[k] = cv::countNonZero(logits[k] > 0);
                std::sort(order.begin(), order.end(), [&](int a, int b) { return areas[a] < areas[b]; });
                for (int k : order) {
                    if (scores[k] > 0.5 && areas[k] > 3 && areas[k] < 0.02 * 256 * 256) {
                        pick = k;
                        break;
                    }
                }
            }
            Mat binFull;
            if (pick >= 0) {
                Mat fullLogits;
                cv::resize(logits[pick], fullLogits, cv::Size(w, h), 0, 0, cv::INTER_LINEAR);
                binFull = fullLogits > 0;
            } else {
                // SAM declined (usually a tiny chip) — keep the classical mask.
                auto found = keptByPrompt.find(pi);
                if (found == keptByPrompt.end() || cv::countNonZero(found->second) < 32) continue;
                binFull = found->second;
            }
            MaskROI roi;
            if (finishMask(binFull, roi)) refined.push_back(std::move(roi));
        }
        dedupMasks(refined);
        totalHolds = (NSInteger)refined.size();

        std::vector<size_t> picked = colorPass(refined, hsv, labFull, chromaCand, key);
        Mat unionMask = Mat::zeros(h, w, CV_8U);
        for (size_t idx : picked) {
            sources.push_back(refined[idx]);
            unionMask(refined[idx].box) |= refined[idx].crop;
        }

        // Recover route-colored classical holds the refinement lost (final_layer.py):
        // usually the bottom foot chips.
        std::vector<size_t> classicalPicked = colorPass(classicalROIs, hsv, labFull, chromaCand, key);
        for (size_t idx : classicalPicked) {
            MaskROI &roi = classicalROIs[idx];
            if (roi.area < 40) continue;
            if (cv::countNonZero(unionMask(roi.box) & roi.crop) < 0.3 * roi.area) {
                unionMask(roi.box) |= roi.crop;
                sources.push_back(roi);
            }
        }
    }
    if (!samRan) {
        // Models missing or the encoder failed: classical-only, as before.
        totalHolds = (NSInteger)classicalROIs.size();
        for (size_t idx : colorPass(classicalROIs, hsv, labFull, chromaCand, key)) {
            sources.push_back(classicalROIs[idx]);
        }
    }

    // --- final render: vector-traced flat shapes on black ---
    // Simplify each outline faithfully (straight edges stay straight, arcs keep
    // their vertices), then Chaikin corner-cutting rounds the corners without
    // inventing curvature anywhere else. Tiny chips become clean circles.
    const int S = 3;  // supersample for clean anti-aliased edges
    Mat shapeBin = Mat::zeros(h * S, w * S, CV_8U);
    NSInteger drawn = 0;
    for (auto &roi : sources) {
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(roi.crop, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE,
                         roi.box.tl());
        if (contours.empty()) continue;
        auto &c = *std::max_element(contours.begin(), contours.end(),
                                    [](const std::vector<cv::Point> &a, const std::vector<cv::Point> &b) {
                                        return cv::contourArea(a) < cv::contourArea(b);
                                    });
        double area = cv::contourArea(c);
        if (area < 40) continue;
        if (area < 400) {
            cv::Point2f center;
            float radius;
            cv::minEnclosingCircle(c, center, radius);
            cv::circle(shapeBin, cv::Point((int)(center.x * S), (int)(center.y * S)),
                       std::max(4, (int)(radius * 0.9 * S)), 255, cv::FILLED);
            drawn++;
            continue;
        }
        double eps = 0.012 * cv::arcLength(c, true);
        std::vector<cv::Point> approx;
        cv::approxPolyDP(c, approx, eps, true);
        std::vector<cv::Point2d> pts(approx.begin(), approx.end());
        for (int iter = 0; iter < 4; iter++) {
            std::vector<cv::Point2d> next;
            next.reserve(pts.size() * 2);
            for (size_t i = 0; i < pts.size(); i++) {
                const cv::Point2d &p = pts[i], &q = pts[(i + 1) % pts.size()];
                next.push_back(p * 0.75 + q * 0.25);
                next.push_back(p * 0.25 + q * 0.75);
            }
            pts = std::move(next);
        }
        std::vector<cv::Point> poly;
        poly.reserve(pts.size());
        for (auto &p : pts) {
            poly.emplace_back((int)std::lround(p.x * S), (int)std::lround(p.y * S));
        }
        cv::fillPoly(shapeBin, std::vector<std::vector<cv::Point>>{poly}, 255, cv::LINE_AA);
        drawn++;
    }

    cv::Vec3b fill = kFillBGR.at(key);
    Mat canvas = Mat::zeros(h * S, w * S, CV_8UC3);
    canvas.setTo(cv::Scalar(fill[0], fill[1], fill[2]), shapeBin);
    Mat render;
    cv::resize(canvas, render, cv::Size(w, h), 0, 0, cv::INTER_AREA);

    return [[HoldDetectionResult alloc] initWithWall:wall
                                               route:uiImageFromBGR(render)
                                              picked:drawn
                                               total:totalHolds];
}

@end
