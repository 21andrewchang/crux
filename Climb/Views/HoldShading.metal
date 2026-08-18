#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

namespace {

/// A hold's silhouette is all the detector gave us, so the shape has to be lit off the
/// only thing the cut-out knows about itself: its own coverage. Everything below is in
/// service of turning that flat mask into something with a top, a shoulder and a side.

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < octaves; ++i) {
        sum += amp * valueNoise(p);
        p *= 2.03;
        amp *= 0.5;
    }
    return sum;
}

}

/// Sculpts one hold out of its cut-out.
///
/// Coverage — how much of a small disc around a pixel lands inside the shape — stands in
/// for height: deep inside is the top of the hold, the outline is where it meets the
/// wall. The same disc gives the slope for free, because the samples inside the shape
/// pull toward the hold's middle, hardest right at the edge where half the disc is
/// empty. That vector, tipped away from the middle, is the surface normal, and once
/// there is a normal there is light: a key from wherever `light` points, an ambient that
/// is cool from above and warm off the floor, a tight specular for the gloss and a rim
/// that catches the shoulders the way moulded polyurethane does. The surface itself is
/// left smooth: whatever the shape says is all there is.
///
/// Sampling the mask over a disc also resamples it: the cut-outs are small, and the
/// coverage ramp gives a cleaner outline than blowing the pixels up ever would.
[[ stitchable ]] half4 climbingHold(float2 pos,
                                    SwiftUI::Layer layer,
                                    float radius,
                                    float2 lightXY,
                                    float lightZ,
                                    float swirl,
                                    half4 tint) {
    // Taps laid out on a golden-angle spiral rather than on rings. Rings put every tap
    // on one of a few radii, and a boundary sweeping across them crosses a whole ring at
    // once — which comes out as spokes running down the shoulder. A spiral has no two
    // taps at the same radius or the same angle, so there is nothing for the edge to
    // cross all at once. Grain used to cover this up; without grain it is the surface.
    constexpr int taps = 40;
    constexpr float golden = 2.39996323;
    constexpr float tau = 6.28318530718;

    float cov = 0.0;
    float2 pull = float2(0.0);
    for (int i = 0; i < taps; ++i) {
        // Square-rooted, so the taps sit evenly over the disc's *area* and the average is
        // the coverage rather than something weighted toward the middle.
        float rr = radius * sqrt((float(i) + 0.5) / float(taps));
        float angle = float(i) * golden;
        float2 dir = float2(cos(angle), sin(angle));
        float a = float(layer.sample(pos + dir * rr).a);
        cov += a;
        pull += dir * a;
    }
    cov /= float(taps);
    pull /= float(taps);

    // The outline is cut from a tight ring of its own. The wide disc is what gives the
    // shape its height, and a height read over ten points would give an edge to match —
    // a hold has a hard edge whatever its shoulder does behind it.
    float nearCov = 2.0 * float(layer.sample(pos).a);
    for (int i = 0; i < 8; ++i) {
        float angle = (float(i) + 0.5) * (tau / 8.0);
        float2 dir = float2(cos(angle), sin(angle));
        nearCov += float(layer.sample(pos + dir * radius * 0.22).a);
    }
    nearCov /= 10.0;

    // The cut-outs are small, and a coverage ramp gives a cleaner edge than blowing the
    // source pixels up ever would.
    float alpha = smoothstep(0.36, 0.64, nearCov);
    if (alpha <= 0.002) { return half4(0.0h); }

    float slope = length(pull);
    float2 downhill = slope > 1e-5 ? pull / slope : float2(0.0);
    // Flat across the top, rolling over hard at the shoulder — a hold's profile, not a
    // sphere's. The exponent is what keeps a foot chip a chip: without it the small
    // cut-outs are all shoulder and come out as beads.
    float tilt = saturate(slope * 3.3);
    tilt = pow(tilt, 1.05);

    float3 n = float3(-downhill * tilt, sqrt(max(1.0 - tilt * tilt, 0.015)));

    // Nothing is added to the surface: the hold is poured, not sanded, and the normal is
    // left exactly as the shape gave it. The one speck of noise kept is dither, put on
    // the colour at the very end — a smooth surface bands where a rough one never could,
    // and the flat top of a big hold is the widest gradient on the screen.
    float dither = hash21(floor(pos * 2.0)) - 0.5;

    float3 L = normalize(float3(lightXY, lightZ));
    float3 H = normalize(L + float3(0.0, 0.0, 1.0));

    // Wrapped, so the side facing away still reads as plastic rather than as a hole.
    float diffuse = saturate(dot(n, L) * 0.62 + 0.38);
    diffuse *= diffuse;
    // Tighter and brighter than a gritty hold's: with nothing to break the highlight
    // into pieces, the whole of it lands in one place, which is what gloss looks like.
    float spec = pow(saturate(dot(n, H)), 62.0);
    float sheen = pow(saturate(dot(n, H)), 5.0);
    float rim = pow(1.0 - saturate(n.z), 3.0);
    // The outline is where the hold meets the wall, and nothing much gets in there.
    float occlusion = smoothstep(0.02, 0.58, cov);

    // A whisper of swirl, far too broad to read as texture — it only keeps the colour
    // off being a dead flat swatch, the way a poured hold is never quite one colour.
    float3 albedo = float3(tint.rgb);
    albedo *= 0.96 + 0.07 * fbm(pos * swirl * 0.06, 2);

    float3 sky = float3(0.26, 0.30, 0.40);
    float3 floorBounce = float3(0.13, 0.10, 0.08);
    // Screen y runs down, so a face pointing up the screen has a negative y normal.
    float3 ambient = mix(floorBounce, sky, saturate(-n.y * 0.5 + 0.5));
    float3 key = float3(1.03, 0.99, 0.92);

    float3 col = albedo * (ambient * occlusion * 1.05 + key * diffuse * 0.98);
    col += key * spec * 0.50;
    col += albedo * sheen * 0.15;
    col += (albedo * 0.26 + 0.06) * rim;
    col += dither * (1.0 / 255.0);

    col = clamp(col, 0.0, 1.6);
    return half4(half3(col) * half(alpha), half(alpha));
}

/// The wall behind the route. Painted ply, the seams between the boards, and a pool of
/// light coming from the same place the holds are lit from — a flat black rectangle gives
/// a hold nothing to sit on, and a hold that sits on nothing looks stuck on. It has to
/// stay dark enough that the route is the only thing on the screen with a colour, but not
/// so dark that the shadows land on nothing.
[[ stitchable ]] half4 gymWall(float2 pos, half4 current, float2 size, float2 lightXY) {
    float2 uv = pos / max(size, float2(1.0));

    float3 base = float3(0.085, 0.088, 0.098);

    // Paint over ply: broad blotching, then the tooth of the roller, then the grit.
    float blotch = fbm(pos * 0.005, 3);
    float tooth = fbm(pos * 0.08, 2);
    base *= 0.78 + 0.46 * blotch;
    base *= 0.93 + 0.14 * tooth;
    base += 0.014 * (hash21(floor(pos * 1.4)) - 0.5);

    // Board seams. Ply is stood on its end up a climbing wall, so the joins run up it and
    // never across, and a seam is a shadowed groove rather than a drawn line — a line
    // across the middle of a screen reads as the screen, not as the wall.
    float edge = abs(fract(pos.x / 330.0) - 0.5);
    float groove = smoothstep(0.4965, 0.5, edge);
    base *= 1.0 - 0.26 * groove;

    // The key light, thrown down from wherever the holds think it hangs.
    float2 lightPoint = float2(0.5) + normalize(lightXY + float2(1e-4)) * 0.40;
    float pool = 1.0 - smoothstep(0.0, 1.15, distance(uv, lightPoint));
    base += float3(0.055, 0.053, 0.048) * pool * pool;

    // Corners down, so the middle of the route carries the eye.
    float vignette = 1.0 - 0.62 * smoothstep(0.30, 1.10, distance(uv, float2(0.5)) * 1.30);
    base *= vignette;

    base = max(base, float3(0.0));
    return half4(half3(base) * current.a, current.a);
}
