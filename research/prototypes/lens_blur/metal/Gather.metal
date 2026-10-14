// The gather renderer's kernels (render_gather.py), for timing only (OTH-03). Not linked into the app.

#include <metal_stdlib>
using namespace metal;

struct Sample {
    float2 offset;
    float rho;
    float spacing;
    float area;
    float gFront;
    float gBack;
    float unused;
};

struct Params {
    int2 size;
    int sampleCount;
    int lutCount;
    float lutStep;
    int tile;
    int2 tiles;
    int window;
    int rowStart;
    float2 unused;
};

// Bilinear resample of a source (rgb, signed radius) and its log depth to the timed size.
kernel void lb_resample(texture2d<float, access::sample> colour [[texture(0)]],
                        texture2d<float, access::sample> logz [[texture(1)]],
                        texture2d<half, access::write> outColour [[texture(2)]],
                        texture2d<half, access::write> outLogz [[texture(3)]],
                        constant float &radiusScale [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outColour.get_width() || gid.y >= outColour.get_height()) return;
    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5f) / float2(outColour.get_width(), outColour.get_height());
    float4 c = colour.sample(s, uv);
    outColour.write(half4(half3(c.rgb), half(c.w * radiusScale)), gid);
    outLogz.write(half4(half(logz.sample(s, uv).r)), gid);
}

kernel void lb_tile_max(texture2d<half, access::read> colour [[texture(0)]],
                        texture2d<float, access::write> tiles [[texture(1)]],
                        constant Params &p [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    if (int(gid.x) >= p.tiles.x || int(gid.y) >= p.tiles.y) return;
    float m = 0.0f;
    int2 origin = int2(gid) * p.tile;
    for (int y = 0; y < p.tile; y++) {
        for (int x = 0; x < p.tile; x++) {
            int2 q = min(origin + int2(x, y), p.size - 1);
            m = max(m, abs(float(colour.read(uint2(q)).w)));
        }
    }
    tiles.write(float4(m), gid);
}

// How far samples must reach for each tile: the largest radius of any tile near enough to reach it.
kernel void lb_tile_reach(texture2d<float, access::read> tiles [[texture(0)]],
                          texture2d<float, access::write> reach [[texture(1)]],
                          constant Params &p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    if (int(gid.x) >= p.tiles.x || int(gid.y) >= p.tiles.y) return;
    float r = 0.0f;
    for (int dy = -p.window; dy <= p.window; dy++) {
        for (int dx = -p.window; dx <= p.window; dx++) {
            int2 q = int2(gid) + int2(dx, dy);
            if (any(q < 0) || any(q >= p.tiles)) continue;
            float m = tiles.read(uint2(q)).r;
            float gap = (max(abs(float(dx)), abs(float(dy))) - 1.0f) * float(p.tile);
            // A sample's coverage fades over half its ring spacing (rho / kappa) past its radius.
            if (gap <= m * 1.07f + 1.0f) r = max(r, m);
        }
    }
    reach.write(float4(r), gid);
}

// Pull-push: the far field's colour weighted by how far it is, then a box pyramid of it.
kernel void lb_pull_base(texture2d<half, access::read> colour [[texture(0)]],
                         texture2d<float, access::write> level [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= level.get_width() || gid.y >= level.get_height()) return;
    float4 c = float4(colour.read(gid));
    float w = 1.0f - smoothstep(0.25f, 1.0f, c.w);
    level.write(float4(c.rgb * w, w), gid);
}

kernel void lb_pull(texture2d<float, access::read> fine [[texture(0)]],
                    texture2d<float, access::write> coarse [[texture(1)]],
                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= coarse.get_width() || gid.y >= coarse.get_height()) return;
    float4 sum = 0.0f;
    float n = 0.0f;
    for (uint y = 0; y < 2; y++) {
        for (uint x = 0; x < 2; x++) {
            uint2 q = gid * 2 + uint2(x, y);
            if (q.x < fine.get_width() && q.y < fine.get_height()) { sum += fine.read(q); n += 1.0f; }
        }
    }
    coarse.write(sum / n, gid);
}

// filled = a * known + (1 - a) * upsampled coarser fill, a = clamp(2 w); the coarsest is normalised as is.
kernel void lb_push(texture2d<float, access::read> pulled [[texture(0)]],
                    texture2d<float, access::sample> coarser [[texture(1)]],
                    texture2d<float, access::write> filled [[texture(2)]],
                    constant int &coarsest [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= filled.get_width() || gid.y >= filled.get_height()) return;
    float4 v = pulled.read(gid);
    float3 known = v.rgb / max(v.w, 1e-8f);
    if (coarsest != 0) { filled.write(float4(known, 1.0f), gid); return; }
    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    float3 up = coarser.sample(s, (float2(gid) + 0.5f) / float2(filled.get_width(), filled.get_height())).rgb;
    float a = clamp(v.w * 2.0f, 0.0f, 1.0f);
    filled.write(float4(a * known + (1.0f - a) * up, 1.0f), gid);
}

kernel void lb_gather(texture2d<half, access::read> colour [[texture(0)]],
                      texture2d<half, access::read> logz [[texture(1)]],
                      texture2d<float, access::read> reach [[texture(2)]],
                      texture2d<float, access::read> fill [[texture(3)]],
                      texture2d<float, access::write> out [[texture(4)]],
                      device const Sample *samples [[buffer(0)]],
                      device const float *lutFront [[buffer(1)]],
                      device const float *lutBack [[buffer(2)]],
                      constant Params &p [[buffer(3)]],
                      uint2 tid [[thread_position_in_grid]])
{
    uint2 gid = uint2(tid.x, tid.y + uint(p.rowStart));
    if (int(gid.x) >= p.size.x || int(gid.y) >= p.size.y) return;
    float4 centre = float4(colour.read(gid));
    float rc = centre.w;
    float zc = float(logz.read(gid).r);
    float nearC = smoothstep(0.25f, 1.0f, rc);
    float limit = reach.read(gid / uint(p.tile)).r;
    float3 cn = 0.0f, cf = 0.0f;
    float an = 0.0f, wf = 0.0f;
    int last = p.lutCount - 1;
    for (int k = 0; k < p.sampleCount; k++) {
        Sample s = samples[k];
        if (s.rho > limit + s.spacing) break;
        // Outside the frame repeats its edge, as render_gather.py does.
        int2 q = clamp(int2(gid) + int2(s.offset), int2(0), p.size - 1);
        float4 v = float4(colour.read(uint2(q)));
        float rj = v.w;
        float zj = float(logz.read(uint2(q)).r);
        float nf = smoothstep(0.25f, 1.0f, rj);
        float behind = clamp((zj - zc) / 0.05f, 0.0f, 1.0f) * (1.0f - nearC);
        float ra = abs(rj);
        float reff = mix(ra, min(ra, abs(rc)), behind);
        float wFar = s.area * clamp(0.5f + (reff - s.rho * s.gBack) / s.spacing, 0.0f, 1.0f)
                     / lutBack[clamp(int(rint(reff * p.lutStep)), 0, last)] * (1.0f - nf);
        float rn = max(rj, 0.0f);
        float wNear = s.area * clamp(0.5f + (rn - s.rho * s.gFront) / s.spacing, 0.0f, 1.0f)
                      / lutFront[clamp(int(rint(rn * p.lutStep)), 0, last)] * nf;
        cf += wFar * v.rgb;
        wf += wFar;
        cn += wNear * v.rgb;
        an += wNear;
    }
    float alpha = clamp(an, 0.0f, 1.0f);
    float3 nearColour = cn / max(an, 1e-6f);
    float3 farColour = (cf + 1e-3f * fill.read(gid).rgb) / (wf + 1e-3f);
    out.write(float4(alpha * nearColour + (1.0f - alpha) * farColour, 1.0f), gid);
}
