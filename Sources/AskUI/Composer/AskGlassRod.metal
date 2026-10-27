// The Glass Rod: the composer's rim as a clear glass tube with the spectrum's
// light inside it, the fill `AskGlassRod` draws over the capsule's edge.
// AskGlassRod.swift says what it looks like and why; this file is the
// per-pixel arithmetic.
//
// Everything is measured in points from the capsule's edge, and the tube is
// a circle in cross-section that each pixel casts one ray into, so the look
// is a formula and needs no blur, no mask and no offscreen layer.

#include <metal_stdlib>
using namespace metal;

namespace {

constant float tau = 6.28318531;

// `colors` out and back: `t`'s fraction walks from the first through every
// one of them to the last, at the half, and back again, so a hue that drifts
// never meets a seam, and no two colors that aren't neighbours in the list
// ever mix. Straight from the last back to the first, a spectrum whose ends
// sit across the color wheel from each other, as aurora's coral and cyan do,
// passed through a grey (`theRodRunsOutAndBackThroughTheColors`).
half4 palette(device const half4 *colors, int count, float t) {
    int legs = 2 * (count - 1);
    float x = fract(t) * float(legs);
    int i = min(int(x), legs - 1);
    half f = half(x - float(i));
    if (i < count - 1) {
        return mix(colors[i], colors[i + 1], f);
    }
    int back = legs - i;
    return mix(colors[back], colors[back - 1], f);
}

// Where `p` sits round the rim of a rounded rectangle whose corners are
// circles of radius `r`, centred `straight.x` across and `straight.y` up or
// down from the origin, as a fraction of the perimeter: 0 at the middle of
// the right-hand side, rising anticlockwise (y up). A capsule is the one
// whose `straight.y` is 0, its ends two of the corners. By arc length, not by
// angle, so a coordinate that moves at one rate moves at one pace on the
// straights and round the corners.
float rimCoordinate(float2 p, float2 straight, float r) {
    float a = straight.x;
    float b = straight.y;
    float quarter = 0.5 * M_PI_F * r;
    float perimeter = 4.0 * (a + b + quarter);
    float2 d = abs(p) - straight;
    float s;
    if (d.x > 0.0 && d.y > 0.0) {
        // Round a corner, by its angle from the corner's centre.
        float angle = atan2(p.y - sign(p.y) * b, p.x - sign(p.x) * a);
        if (angle < 0.0) {
            angle += tau;
        }
        if (p.x > 0.0 && p.y > 0.0) {
            s = b + angle * r;
        } else if (p.y > 0.0) {
            s = b + quarter + 2.0 * a + (angle - 0.5 * M_PI_F) * r;
        } else if (p.x < 0.0) {
            s = 3.0 * b + 2.0 * quarter + 2.0 * a + (angle - M_PI_F) * r;
        } else {
            s = 3.0 * b + 3.0 * quarter + 4.0 * a + (angle - 1.5 * M_PI_F) * r;
        }
    } else if (d.x > d.y) {
        // Up the right-hand side from its middle, or down the left.
        s = p.x > 0.0
            ? (p.y >= 0.0 ? p.y : perimeter + p.y)
            : 2.0 * b + 2.0 * quarter + 2.0 * a - p.y;
    } else {
        // Leftward along the top, or rightward along the bottom.
        s = p.y >= 0.0
            ? b + quarter + (a - p.x)
            : 3.0 * b + 3.0 * quarter + 3.0 * a + p.x;
    }
    return s / perimeter;
}

// `pow(x, 2)` is undefined for negative x under fast math, where it is
// `exp2(2 * log2(x))`.
float square(float x) {
    return x * x;
}

// Three slow waves along the rim at `s`, at `t` seconds: what the light's
// color and brightness ride, so they pool along the rod rather than sit even.
float wave(float s, float t) {
    return 0.5 * sin(tau * 2.0 * s + t * 0.9) + 0.3 * sin(tau * 3.0 * s - t * 1.3)
        + 0.2 * sin(tau * 5.0 * s + t * 2.1);
}

} // namespace

// The rod at `position`, premultiplied.
//
// - bounds: the rectangle being filled, which reaches past the composer.
// - inset: from the rectangle's edge in to the composer's capsule.
// - outset: from the composer's capsule out to the rod's centre line; less
//   than zero puts it inside the capsule.
// - radius: the tube's radius, in points.
// - corner: the radius of the capsule's corners, which a capsule's ends cap
//   at half its height; less, and a capsule taller than that is a rounded
//   rectangle.
// - headroom: how far over the capsule's top, on the screen, the glow may
//   reach: it is gone that far up, so it stays off what sits there.
// - facing: 1 where the cast glow falls on both sides of the rod, most of it
//   outside, over the screen's bar; -1 where it falls inward only, on the
//   face in a host's slot, which also draws nothing past the composer's
//   capsule.
// - mirror: 1, or -1 in a right-to-left layout, whose trailing end, where the
//   send circle is, is on the left.
// - time: seconds on the clock the colors drift by, from the send.
// - drift: 0 for the colors at rest, 1 for the colors drifting at `time`,
//   and between them while the stage's animation carries one to the other.
// - on: how much of the rod is drawn, 0 to 1, animated as its capsule is
//   covered or uncovered.
// - dark: 1 in dark mode, 0 in light.
// - scale: pixels to a point, so the tube's edge is smoothed over a pixel and
//   a half at any scale.
[[ stitchable ]] half4 askGlassRod(
    float2 position,
    float4 bounds,
    float inset,
    float outset,
    float radius,
    float corner,
    float headroom,
    float facing,
    float mirror,
    float time,
    float drift,
    float on,
    float dark,
    float scale,
    device const half4 *colors,
    int count
) {
    // Centred, y up, and the trailing end on the right.
    float2 p = position - (bounds.xy + 0.5 * bounds.zw);
    p.y = -p.y;
    p.x *= mirror;
    float2 half_size = 0.5 * bounds.zw - inset;
    // How far over the capsule's top the point is, on the screen.
    float above = p.y - half_size.y;
    // Taller than wide, the capsule runs up and down: the same arithmetic on
    // its long axis.
    bool tall = half_size.y > half_size.x;
    if (tall) {
        p = p.yx;
        half_size = half_size.yx;
    }
    float r = clamp(corner, 0.5, max(half_size.y, 0.5));
    float2 straight = max(half_size - r, 0.0);

    // Signed distance from the capsule's edge, positive outside, and the
    // edge's outward normal at the nearest point, turned back to the screen's
    // axes for the light, which comes from the upper left in either layout
    // direction.
    float2 d = abs(p) - straight;
    float2 q = max(d, 0.0);
    float fromCorner = length(q);
    float edge = fromCorner + min(max(d.x, d.y), 0.0) - r;
    float2 toward = float2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
    float2 normal = fromCorner > 1e-4
        ? toward * q / fromCorner
        : (d.x > d.y ? float2(toward.x, 0.0) : float2(0.0, toward.y));
    if (tall) {
        normal = normal.yx;
    }
    normal.x *= mirror;

    // Across the tube: -1 at its inner side, 1 at its outer.
    float dc = edge - outset;
    float x = dc / radius;
    float past = max(abs(dc) - radius, 0.0);

    // How much of the glow is left. It goes to nothing over its fourth 5 pt
    // falloff, where it is under half a percent. Facing out, it also goes
    // the rest of the way to nothing over the last 40% of the room the fill
    // gives it, so the fill's rectangle never shows, and over the capsule's
    // top it is gone by `headroom`; facing in, nothing past the composer's
    // own capsule.
    float room = max(inset - (outset + radius), 1.0);
    float beyond = max(dc - radius, 0.0);
    float fade = (1.0 - smoothstep(15.0, 20.0, past)) * (facing > 0.0
        ? (1.0 - smoothstep(0.6 * room, room, beyond))
            * (1.0 - smoothstep(outset + radius, max(headroom, outset + radius + 1.0), above))
        : 1.0 - smoothstep(-0.5 / scale, 0.5 / scale, edge));
    // Nothing left and no tube here: the most of the fill, where the color
    // work below would come to nothing.
    if (fade <= 0.0 && abs(x) >= 1.0) {
        return half4(0.0);
    }

    // The light inside the tube, its color and brightness riding the waves.
    // At rest the colors hold where the waves put them at time 0, the first
    // color at the trailing end and the last at the leading end; in flight
    // they drift slowly round the rod, a twentieth of the way round a second,
    // and the waves shimmer. `drift` carries one to the other as a fade,
    // never by running the clock back.
    float s = rimCoordinate(p, straight, r);
    float restWave = wave(s, 0.0);
    half4 light = palette(colors, count, s + 0.09 * restWave);
    float shimmer = restWave;
    if (drift > 0.0) {
        float flightWave = wave(s, time);
        half4 drifting = palette(colors, count, s + 0.09 * flightWave + 0.05 * time);
        light = mix(light, drifting, half(drift));
        shimmer = mix(restWave, flightWave, drift);
    }
    float3 lc = float3(light.rgb);
    // A touch brighter toward the ends, where the tube bends and gathers light.
    float ends = smoothstep(straight.x - 6.0, straight.x + r * 0.6, abs(p.x));
    float lit = (1.0 + 0.3 * ends) * (0.85 + 0.15 * shimmer);

    // A soft glow cast just past the tube. Facing out, most of it falls
    // outside the capsule; facing in, all of it falls inside the face.
    float side = facing > 0.0 ? (dc > 0.0 ? 1.0 : 0.45) : (dc < 0.0 ? 0.6 : 0.0);
    float cast = 0.5 * exp(-past / 5.0) * side * lit * fade;
    float4 glow = float4(lc * cast, cast);

    float4 rod = float4(0.0);
    if (abs(x) < 1.0) {
        // The ray meets the tube's surface at height z, bends into the glass
        // once per channel, a little more for blue than red, and the core of
        // light it reaches along the tube's middle splits into a fringe at
        // its sides.
        float z = sqrt(1.0 - x * x);
        float2 n = float2(x, z);
        float3 core;
        for (int k = 0; k < 3; k++) {
            float eta = 1.0 / (1.45 + 0.04 * float(k));
            float2 bent = refract(float2(0.0, -1.0), n, eta);
            float landing = x + bent.x * (z / max(-bent.y, 1e-3));
            core[k] = exp(-square(landing / 0.40));
        }
        float body = 0.28 * z;
        // Fresnel: the glass turns to a mirror toward its silhouette.
        float fresnel = 0.04 + 0.96 * pow(1.0 - z, 5.0);
        // A highlight from a light at the upper left.
        float3 surface = float3(normal * x, z);
        float3 toLight = normalize(float3(-0.35, 0.7, 0.62));
        float3 halfway = normalize(toLight + float3(0.0, 0.0, 1.0));
        float specular = pow(max(dot(surface, halfway), 0.0), 80.0);
        float strongest = max(core.r, max(core.g, core.b));
        // Brighter than white is cut back to it a channel at a time, which
        // whitens the core as a hot light does, but only for what sRGB holds
        // of the color: what a Display P3 color reaches past sRGB's 0 and 1
        // goes back on after, so the core stays a P3 color. Clamped to 0 and
        // 1 with the rest, P3's green came back as sRGB's.
        float3 gain = (core * 1.15 + body) * lit;
        float3 within = saturate(lc);
        float3 color = saturate(within * gain + specular * 0.95 + fresnel * 0.35) + (lc - within) * min(gain, 1.0);
        float alpha = saturate(0.2 + 0.8 * strongest * lit + specular + fresnel * 0.3);
        // In light mode a faint dark line at the tube's silhouette, which on
        // white is what a clear tube shows.
        float outline = smoothstep(0.8, 1.0, abs(x)) * 0.2 * (1.0 - dark);
        color = mix(color, float3(0.1, 0.12, 0.2), outline);
        alpha = max(alpha, outline);
        // The silhouette smoothed over a pixel and a half.
        alpha *= 1.0 - smoothstep(1.0 - 1.5 / (radius * scale), 1.0, abs(x));
        // Facing in, nothing past the face, the tube's outer edge included.
        if (facing < 0.0) {
            alpha *= 1.0 - smoothstep(-0.5 / scale, 0.5 / scale, edge);
        }
        rod = float4(color * alpha, alpha);
    }

    return half4((rod + glow * (1.0 - rod.a)) * on);
}
