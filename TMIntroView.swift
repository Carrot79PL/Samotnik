import Cocoa
import MetalKit
import MetalPerformanceShaders

/// Uniwersalne intro „Tomasz Marchewka STUDIO” (Swift + Metal).
/// Użycie w grze:   let v = TMIntroView(frame: bounds); v.onFinish = { … }; contentView.addSubview(v); v.start()
/// Pisanie: litera po literze → podkreślenie → STUDIO, niebieska poświata, świetlik na piórze, błysk, wygaszenie.
let tmIntroShader = #"""
#include <metal_stdlib>
using namespace metal;
struct U { float2 res; float2 logoC; float2 logoS; float2 tip;
           float t; float w; float inn; float out; float tipA; float shim; float soft; float pad; float style; float p1; float p2; float p3; float4 c0; float4 c1; float4 c2; float4 c3; };
struct VO { float4 pos [[position]]; };
vertex VO vmain(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2); VO o; o.pos = float4(p * 2.0 - 1.0, 0, 1); return o; }
static float hash(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
static float dust(float2 p, float time, float cell, float speed) {
    float2 q = p / cell + float2(0, time * speed); float2 id = floor(q), f = fract(q);
    float h = hash(id + cell); if (h < 0.55) return 0.0;
    float2 c = float2(hash(id + 7.1), hash(id + 3.3)) * 0.8 + 0.1;
    float d = length(f - c) * cell; float tw = 0.5 + 0.5 * sin(time * (0.8 + h * 2.0) + h * 40.0);
    return smoothstep(2.2, 0.0, d) * (0.25 + 0.75 * h) * tw; }
// (odsłonięty atrament, „żar” świeżo napisanego)
static float2 inkAt(float2 p, constant U& u, texture2d<float> aTex, texture2d<float> tTex) {
    constexpr sampler lin(filter::linear, address::clamp_to_edge), nea(filter::nearest, address::clamp_to_edge);
    float2 uv = (p - u.logoC) / u.logoS + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0)) return float2(0.0);
    float a = aTex.sample(lin, uv).r, tau = tTex.sample(nea, uv).r;
    float la = a * smoothstep(0.0, 1.0, (u.w - tau) / u.soft);
    float heat = exp(-max(u.w - tau, 0.0) / 0.035) * (u.w < 0.9999 ? 1.0 : 0.0);
    return float2(la, la * heat);
}
fragment float4 imain(VO in [[stage_in]], constant U& u [[buffer(0)]], texture2d<float> aTex [[texture(0)]], texture2d<float> tTex [[texture(1)]]) {
    return float4(inkAt(in.pos.xy * 2.0, u, aTex, tTex), 0.0, 1.0); }
static float tauAt(float2 p, constant U& u, texture2d<float> tTex) {
    constexpr sampler nea(filter::nearest, address::clamp_to_edge);
    float2 uv = (p - u.logoC) / u.logoS + 0.5; if (any(uv < 0.0) || any(uv > 1.0)) return u.w; return tTex.sample(nea, uv).r; }
static float3 bokehL(float2 q, float cell, float rad, float soft, float t) {
    float2 bq = q / cell + float2(0.0, t * 0.01), id = floor(bq), f = fract(bq); float h = hash(id + 3.1);
    float2 c = 0.3 + 0.4 * float2(hash(id + 1.7), hash(id + 9.1)); float d = length(f - c);
    float disc = smoothstep(rad, rad - soft, d) * step(0.55, h);
    float3 cl = mix(float3(1.0, 0.75, 0.35), float3(0.4, 0.8, 1.0), step(0.6, hash(id + 7.7))); cl = mix(cl, float3(1.0, 0.4, 0.6), step(0.85, hash(id + 4.4)));
    return cl * disc * (0.4 + 0.6 * hash(id + 2.2)); }
static float2 warpq(float2 pp, float2 C, float f, float ca, float sa) {
    float2 d = pp - C; float X = d.x * f / (f * ca - d.x * sa); float s = f / (f + X * sa); return C + float2(X, d.y / s); }
static float vnoise(float2 p) { float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), f.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y); }
static float fbm(float2 p) { float a = 0.5, s = 0.0; float2x2 R = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = R * p * 2.03 + 17.0; a *= 0.5; } return s / 0.9375; }
fragment float4 fmain(VO in [[stage_in]], constant U& u [[buffer(0)]],
                      texture2d<float> aTex [[texture(0)]], texture2d<float> tTex [[texture(1)]],
                      texture2d<float> bN [[texture(2)]], texture2d<float> bW [[texture(3)]], constant float4* sparks [[buffer(1)]]) {
    constexpr sampler lin(filter::linear, address::clamp_to_edge);
    float2 p = in.pos.xy, suv = p / u.res;
    float maxd = max(u.res.x, u.res.y), dpr = u.res.y / 900.0;
    float r = length(p - u.res * 0.5) / (maxd * 0.7);
    float2 uv = (p - u.logoC) / u.logoS + 0.5;
    float2 gn = bN.sample(lin, suv).rg, gw = bW.sample(lin, suv).rg;
    float2 ih = inkAt(p, u, aTex, tTex); float la = ih.x, heat = ih.y / max(ih.x, 1e-4);
    float breath = u.pad, t = u.t;
    int st = int(u.style + 0.5);
    float3 col, bgFlat = float3(0.02, 0.027, 0.05), acc = float3(0.5, 0.7, 1.0);
    float dd = dust(p / dpr, t, 46.0, 6.0) * 0.8 + dust(p / dpr + 90.0, t, 90.0, 11.0) * 0.6 + dust(p / dpr + 400.0, t, 28.0, 3.0) * 0.5;
    float band = exp(-pow((uv.x * 0.9 + uv.y * 0.35 - (u.shim * 1.6 - 0.3)) / 0.06, 2.0)) * step(0.001, u.shim) * step(u.shim, 0.999);
    float vig = 0.38;
    float tg = 1.0, noGrain = 0.0; float3 nib = float3(0.15);
    float2 q2 = p / dpr; float stu = smoothstep(0.78, 0.82, uv.y);
    if (st == 0) { // ===== KREDKA: czerwone logo na idealnie białym tle =====
        bgFlat = float3(1.0);
        col = float3(1.0 - 0.7 * smoothstep(0.30, 0.95, r));
        float tooth = vnoise(p * 0.9) * 0.55 + hash(p) * 0.45;
        float hatch = 0.5 + 0.5 * sin((p.x + p.y * 0.6) * 0.9 / dpr + vnoise(q2 * 0.3) * 3.0);
        // atrament koloru krwi: świeży = jaśniejszy i mokry, schnie do ciemnej czerwieni
        float wet = saturate(0.55 + 0.45 * heat); // cały tekst jeszcze mokry, świeżo pod piórem najbardziej
        float3 dry = float3(0.035, 0.06, 0.2), fresh = float3(0.07, 0.13, 0.42);
        float3 cc = mix(dry, fresh, wet) * (0.92 + 0.1 * vnoise(q2 * 0.6));
        cc = mix(cc, dry * 0.85, smoothstep(0.55, 1.0, la) * 0.35 * (1.0 - wet)); // gęstsze środki kresek
        float edge = la * (1.0 - la) * 4.0; cc *= 1.0 - 0.18 * edge * (1.0 - wet);
        float ink = smoothstep(0.08, 0.6, la + 0.08 * (tooth - 0.5));
        col = mix(col, cc, ink);
        // mokry połysk: normalna z rozmytej maski atramentu, odblask od światła z lewej-góry
        float2 ex = float2(1.5 * dpr, 0.0) / u.res, ey = float2(0.0, 1.5 * dpr) / u.res;
        float2 gr2 = float2(bN.sample(lin, suv + ex).x - bN.sample(lin, suv - ex).x, bN.sample(lin, suv + ey).x - bN.sample(lin, suv - ey).x);
        float3 nrm = normalize(float3(-gr2 * 12.0, 1.0));
        float spec = pow(saturate(dot(nrm, normalize(float3(-0.45, -0.6, 0.66)))), 10.0);
        col += float3(0.75, 0.85, 1.0) * spec * wet * la * 1.1;
        col = mix(col, col * float3(0.85, 0.9, 1.05), saturate(gn.x - la) * 0.5 * wet); // lekkie wsiąkanie w papier
        // drobny kleks + krople
        float2 bc = u.logoC + (float2(0.875, 0.74) - 0.5) * u.logoS;
        float2 bd = (p - bc) / u.logoS.x;
        float bt = saturate((u.p1 - 0.3) / 0.18); float gro = 1.0 - pow(1.0 - bt, 3.0);
        float R = 0.017 * (0.35 + 0.65 * gro);
        float2 q = bd / R;
        // metakule: główna kropla + nieregularne płaty + „języczek” w kierunku upadku
        float fld = exp(-dot(q, q) * 1.1);
        for (int i = 0; i < 6; i++) { float fi = float(i);
            float an = fi * 1.047 + hash(float2(fi, 1.0)) * 0.9, ds = 0.45 + 0.45 * hash(float2(fi, 2.0)), sg = 0.28 + 0.3 * hash(float2(fi, 4.0));
            float2 c = float2(cos(an), sin(an)) * ds; float2 e = q - c; fld += 0.75 * exp(-dot(e, e) / (sg * sg)); }
        float2 fdir = normalize(float2(0.85, 0.5));
        for (int i = 1; i <= 3; i++) { float fi = float(i); float2 e = q - fdir * (0.75 + 0.42 * fi); float sg = 0.32 - 0.07 * fi; fld += 0.8 * exp(-dot(e, e) / (sg * sg)); }
        fld += 0.22 * (fbm(q * 2.2 + 5.0) - 0.5);
        float aa = max(fwidth(fld), 1e-4);
        float blot = smoothstep(0.5 - aa, 0.5 + aa, fld);
        // rozprysk: kropelki w stożku, wydłużone promieniście, maleją z odległością
        float spr = 0.0;
        for (int i = 0; i < 10; i++) { float fi = float(i);
            float an = atan2(fdir.y, fdir.x) + (hash(float2(fi, 11.0)) - 0.5) * 1.9;
            float ds = 1.5 + 2.4 * hash(float2(fi, 13.0));
            float2 dv = float2(cos(an), sin(an));
            float2 e = q - dv * ds * (0.5 + 0.5 * gro);
            float along = dot(e, dv), across = dot(e, float2(-dv.y, dv.x));
            float rr = (0.2 - 0.04 * ds) * (0.6 + 0.6 * hash(float2(fi, 17.0)));
            float dd = length(float2(along / 1.7, across));
            spr = max(spr, smoothstep(rr + 0.03, rr - 0.03, dd) * step(0.25, bt)); }
        float inside = smoothstep(0.5, 0.95, fld);
        float3 bcol = mix(dry * 0.78, mix(dry, fresh, saturate(1.0 - (u.p1 - 0.5) / 0.6) * 0.6), inside); // ciemniejszy brzeg (zasychanie)
        bcol *= 0.95 + 0.08 * vnoise(q2 * 0.9);
        col = mix(col, bcol, max(blot, spr * 0.95));
        col += float3(0.75, 0.85, 1.0) * pow(saturate(1.0 - length(q - float2(-0.3, -0.35)) / 0.45), 3.0) * 0.5 * blot;
        tg = 0.0; nib = float3(0.03, 0.05, 0.18); vig = 0.2; noGrain = 1.0;
    } else if (st == 1) { // ===== OŁÓWEK na zeszycie w kratkę =====
        bgFlat = float3(0.96, 0.95, 0.9);
        col = bgFlat * (0.96 + 0.06 * fbm(q2 * 0.02));
        float2 gq = abs(fract(q2 / 26.0) - 0.5); col = mix(col, float3(0.62, 0.74, 0.92), smoothstep(0.465, 0.5, max(gq.x, gq.y)) * 0.55);
        col = mix(col, float3(0.92, 0.4, 0.4), 0.55 * smoothstep(1.4 * dpr, 0.4 * dpr, abs(p.x - u.res.x * 0.09)));
        float tooth = vnoise(p * 1.1) * 0.5 + hash(p) * 0.5, hatch = 0.5 + 0.5 * sin((p.x - p.y) * 1.1 / dpr);
        float gr = la * smoothstep(0.12, 0.55, tooth + 0.5 * la);
        col *= 1.0 - 0.1 * gn.x;
        col = mix(col, float3(0.2, 0.2, 0.24) * (0.88 + 0.3 * hatch) + float3(0.12) * pow(hatch, 6.0), gr * 0.93); tg = 0.0; nib = float3(0.25); vig = 0.2;
    } else if (st == 2) { // ===== AKWARELA =====
        bgFlat = float3(0.97, 0.95, 0.91);
        col = bgFlat * (0.96 + 0.06 * fbm(q2 * 0.03));
        col = mix(col, float3(1.0, 0.72, 0.76), 0.55 * smoothstep(0.45, 0.75, fbm(q2 * 0.0045 + 1.0)));
        col = mix(col, float3(0.62, 0.8, 1.0), 0.55 * smoothstep(0.5, 0.8, fbm(q2 * 0.004 + 6.0)));
        col = mix(col, float3(1.0, 0.92, 0.55), 0.5 * smoothstep(0.55, 0.85, fbm(q2 * 0.005 + 12.0)));
        float gr = vnoise(p * 0.5);
        float3 pig = mix(float3(0.27, 0.16, 0.58), float3(0.1, 0.42, 0.62), stu);
        float bleed = gn.x * 0.55 + gw.x * 0.5;
        col *= mix(float3(1.0), pig * 1.5, saturate(bleed * 0.55));
        col = mix(col, pig * (0.55 + 0.45 * gr) * (0.8 + 0.5 * (1.0 - gn.x)), la * 0.92); tg = 0.0; nib = pig; vig = 0.15;
    } else if (st == 3) { // ===== PIASEK: wyryte w piasku =====
        float grain = hash(p) * 0.5 + vnoise(p * 0.6) * 0.5; float dunes = fbm(q2 * 0.004);
        float3 sand = mix(float3(0.86, 0.73, 0.52), float3(0.68, 0.52, 0.35), dunes) * (0.9 + 0.2 * grain) * (1.0 + 0.04 * sin(q2.y * 0.3 + fbm(q2 * 0.01) * 20.0));
        float2 e = float2(3.0 * dpr) / u.res; float sh = bN.sample(lin, suv + e).x - bN.sample(lin, suv - e).x;
        float depthg = saturate(la * 0.85 + gn.x * 0.55);
        col = sand * (1.0 - 0.55 * depthg) + float3(1.0, 0.92, 0.75) * saturate(-sh * 5.0) * 0.45 - float3(0.2, 0.12, 0.05) * saturate(sh * 5.0) * 0.3;
        col += float3(1.0, 0.95, 0.8) * step(0.9993, hash(floor(p / (1.5 * dpr)))) * (0.5 + 0.5 * sin(t * 4.0 + p.x));
        bgFlat = float3(0.78, 0.64, 0.46); acc = float3(0.8, 0.65, 0.45); tg = 0.0; nib = float3(0.4, 0.3, 0.2); vig = 0.3;
    } else if (st == 4) { // ===== SZRON NA OKNIE: pismo wycieranym palcem, w tle miasto =====
        bgFlat = float3(0.04, 0.06, 0.1);
        float3 soft = bokehL(q2, 90.0, 0.42, 0.3, t) + bokehL(q2 + 50.0, 55.0, 0.4, 0.3, t * 1.3);
        float3 sharp = bokehL(q2, 90.0, 0.3, 0.05, t) * 1.8 + bokehL(q2 + 50.0, 55.0, 0.3, 0.05, t * 1.3) * 1.8;
        float frost = fbm(q2 * 0.025) * 0.7 + fbm(q2 * 0.3) * 0.3;
        float fa = 1.0 - saturate(la * 1.2 + gn.x * 0.4);
        col = bgFlat + soft * 1.1 * u.inn;
        col = mix(col, float3(0.7, 0.8, 0.92) * (0.3 + 0.7 * frost) * u.inn + soft * 0.5, fa * 0.62);
        col = mix(col, sharp * u.inn + float3(0.03, 0.05, 0.09), la);
        col += float3(0.8, 0.92, 1.0) * saturate(gn.x - la) * 0.25 + float3(1.0) * band * la; acc = float3(0.8, 0.92, 1.0); vig = 0.5;
    } else if (st == 5) { // ===== NEON NA CEGLE =====
        float2 bq = q2 / float2(64.0, 26.0); float row = floor(bq.y); bq.x += 0.5 * fmod(row, 2.0); float2 bf = fract(bq);
        float mortar = saturate(step(bf.x, 0.04) + step(bf.y, 0.1));
        float3 brick = mix(float3(0.36, 0.14, 0.1), float3(0.52, 0.23, 0.15), hash(floor(bq))) * (0.75 + 0.35 * vnoise(q2 * 0.5));
        float3 wall = mix(brick, float3(0.16, 0.14, 0.13), mortar);
        float3 nc = mix(float3(1.0, 0.2, 0.62), float3(0.15, 0.85, 1.0), stu);
        float light = gn.x * 1.2 + gw.x * 2.4;
        col = wall * 0.1 + wall * nc * light * 1.7 * u.inn + nc * gw.x * 0.2;
        col = mix(col, mix(float3(1.0, 0.86, 0.95), float3(0.86, 1.0, 1.0), stu) * (1.0 + heat * 0.5), saturate(la));
        bgFlat = float3(0.02, 0.015, 0.015); acc = nc; vig = 0.55;
    } else if (st == 6) { // ===== GRAFFITI: spray na betonie z zaciekami =====
        float3 conc = float3(0.4, 0.4, 0.42) * (0.78 + 0.45 * fbm(q2 * 0.02)) + (hash(p) - 0.5) * 0.05;
        float3 sc = mix(mix(float3(1.0, 0.2, 0.6), float3(1.0, 0.78, 0.1), uv.x), float3(0.1, 0.9, 1.0), stu);
        float dr = 0.0;
        for (int i = 1; i <= 7; i++) { float h = hash(float2(floor(p.x / (5.0 * dpr)), 3.0)); if (h > 0.88) dr = max(dr, inkAt(p - float2(0.0, float(i) * 9.0 * dpr), u, aTex, tTex).x * (1.0 - float(i) / 8.0)); }
        float spray = saturate(la * 0.97 + gn.x * 0.28) * (0.86 + 0.14 * hash(p));
        col = mix(conc, sc, saturate(spray + dr * 0.8)); col += float3(1.0) * heat * la * 0.15;
        bgFlat = float3(0.4, 0.4, 0.42); acc = sc; vig = 0.4;
    } else if (st == 7) { // ===== DESZCZ NEONOWY: mokra ulica nocą =====
        bgFlat = float3(0.01, 0.012, 0.025);
        float3 cityb = bokehL(q2, 80.0, 0.38, 0.25, t) * 0.5 + bokehL(q2 + 30.0, 130.0, 0.4, 0.3, t) * 0.4;
        col = bgFlat + cityb * u.inn;
        float3 nc = mix(float3(0.1, 0.9, 1.0), float3(1.0, 0.2, 0.6), stu);
        col += nc * (gn.x * 1.1 + gw.x * 1.8) * u.inn * breath;
        col = mix(col, mix(float3(0.9, 1.0, 1.0), float3(1.0, 0.85, 0.95), stu) * (1.0 + heat * 0.5), saturate(la));
        float floorY = u.logoC.y + u.logoS.y * 0.55;
        if (p.y > floorY) { float fd = (p.y - floorY) / (u.logoS.y * 0.5), fa = exp(-fd * 2.0);
            float2 pr = float2(p.x + sin(p.y * 0.25 / dpr + t * 3.0) * 3.0 * dpr, 2.0 * floorY - p.y);
            col += nc * (inkAt(pr, u, aTex, tTex).x * 0.35 + bN.sample(lin, pr / u.res).x * 0.4 + bW.sample(lin, pr / u.res).x * 0.4) * fa * u.inn; }
        float rs = hash(float2(floor(p.x / (2.0 * dpr)), 0.0));
        col += float3(0.6, 0.75, 1.0) * smoothstep(0.96, 1.0, fract(p.y / (70.0 * dpr) - t * (1.4 + rs * 2.0) + rs * 10.0)) * step(0.72, rs) * 0.22 * u.inn;
        acc = nc; vig = 0.55;
    } else if (st == 8) { // ===== CRT: zielony fosfor z krzywizną =====
        float2 c = suv * 2.0 - 1.0; c *= 1.0 + 0.09 * dot(c, c);
        bgFlat = float3(0.0);
        if (abs(c.x) > 1.0 || abs(c.y) > 1.0) { col = float3(0.0); }
        else { float2 pc = (c * 0.5 + 0.5) * u.res; float2 il = inkAt(pc, u, aTex, tTex); float2 s2 = pc / u.res;
            float sl = 0.72 + 0.28 * sin(pc.y * 3.14159 / dpr); float mask = 0.85 + 0.15 * sin(pc.x * 2.1 / dpr);
            float3 ph = float3(0.25, 1.0, 0.4);
            col = float3(0.0, 0.03, 0.01) * u.inn + ph * (bN.sample(lin, s2).x * 0.6 + bW.sample(lin, s2).x * 0.9) * 0.5 * u.inn;
            col += (ph * il.x + float3(0.5, 1.0, 0.6) * il.y * 0.8) * sl * mask * (0.95 + 0.05 * sin(t * 60.0));
            col += float3(0.0, 0.08, 0.03) * smoothstep(0.02, 0.0, abs(fract(t * 0.2 + suv.y * 0.3) - 0.5) - 0.02);
            col *= 1.0 - 0.5 * pow(max(abs(c.x), abs(c.y)), 6.0); }
        acc = float3(0.3, 1.0, 0.45); tg = 0.0; nib = float3(0.5, 1.0, 0.6); vig = 0.0;
    } else if (st == 9) { // ===== MOZAIKA kolorowych kafelków =====
        bgFlat = float3(0.05, 0.05, 0.06);
        float cs = max(7.0 * dpr, u.logoS.x / 150.0); float2 cid = floor(p / cs), cf = fract(p / cs) - 0.5, cc = (cid + 0.5) * cs;
        float2 il = inkAt(cc, u, aTex, tTex); float tile = step(max(abs(cf.x), abs(cf.y)), 0.44);
        float3 pc = 0.5 + 0.5 * cos(6.2832 * (hash(cid) * 0.2 + uv.x * 0.7 + float3(0.0, 0.33, 0.67)));
        float bev = 1.0 + 0.35 * (-cf.x - cf.y) * 1.3;
        col = bgFlat + float3(0.1, 0.1, 0.12) * tile * 0.5 * (0.6 + 0.4 * hash(cid + 2.0));
        col = mix(col, pc * bev * (1.0 + il.y * 0.4), tile * il.x);
        col += float3(1.0) * band * il.x * tile * 0.4; acc = float3(1.0, 0.9, 0.7); vig = 0.5;
    } else if (st == 10) { // ===== WYPALONE W DREWNIE =====
        float grain = fbm(float2(q2.x * 0.005, q2.y * 0.08));
        float3 wood = mix(float3(0.58, 0.38, 0.21), float3(0.38, 0.22, 0.1), grain) * (0.85 + 0.3 * fbm(q2 * float2(0.01, 0.25)));
        float a = clamp((u.w - tauAt(p, u, tTex)) / 0.1, 0.0, 1.0);
        col = wood * (1.0 - 0.45 * gn.x) + float3(0.9, 0.4, 0.08) * (gn.y * 0.7 + gw.y * 0.4) * u.inn;
        col = mix(col, float3(0.05, 0.025, 0.012) * (0.8 + 0.5 * grain), la);
        col += float3(1.0, 0.42, 0.06) * (1.0 - a) * la * 1.5 * (u.w < 0.9999 ? 1.0 : 0.0);
        col += float3(0.3, 0.12, 0.02) * smoothstep(0.55, 0.9, fbm(q2 * 0.03 - float2(0, t * 0.2))) * gn.y * 0.3;
        bgFlat = float3(0.4, 0.25, 0.12); acc = float3(1.0, 0.5, 0.1); vig = 0.5;
    } else if (st == 11) { // ===== MAPA WARSTWICOWA: litery jako szczyt =====
        bgFlat = float3(0.93, 0.9, 0.8);
        float H = fbm(q2 * 0.003) * 0.6 + (gn.x * 1.3 + gw.x * 1.8);
        float d = abs(fract(H * 15.0) - 0.5), lines = smoothstep(0.455, 0.5, d), idx = smoothstep(0.43, 0.5, abs(fract(H * 3.0) - 0.5));
        col = mix(float3(0.82, 0.9, 0.72), float3(0.97, 0.86, 0.62), saturate(H * 0.8)) * (0.96 + 0.06 * fbm(q2 * 0.05));
        col = mix(col, float3(0.5, 0.34, 0.22), saturate(lines * 0.6 + idx * 0.4));
        col = mix(col, float3(0.14, 0.1, 0.09), la * 0.95); tg = 0.0; nib = float3(0.2, 0.1, 0.1); vig = 0.25;
    } else if (st == 12) { // ===== SYNTHWAVE: zachód słońca i siatka =====
        float hz = u.res.y * 0.64; float3 skyTop = float3(0.04, 0.0, 0.14), skyHz = float3(0.95, 0.25, 0.55);
        float sy = saturate(p.y / hz);
        col = mix(skyTop, skyHz, pow(sy, 2.2));
        float2 sc = float2(u.res.x * 0.5, hz - u.res.y * 0.17); float sr = u.res.y * 0.2; float ds = length(p - sc);
        float cut = step(0.0, sin((p.y - sc.y) / dpr * 0.42 * (1.6 - saturate((p.y - sc.y + sr) / (2.0 * sr)) * 1.0))) + step(p.y, sc.y);
        col = mix(col, mix(float3(1.0, 0.9, 0.3), float3(1.0, 0.2, 0.55), saturate((p.y - sc.y + sr) / (2.0 * sr))), smoothstep(sr, sr - 2.0 * dpr, ds) * saturate(cut) * u.inn);
        col += float3(1.0, 0.7, 0.9) * step(0.9985, hash(floor(p / (2.0 * dpr)))) * (1.0 - sy) * 0.8 * step(p.y, hz);
        if (p.y > hz) { float z = hz / max(p.y - hz, 1.0); float gx = (p.x - u.res.x * 0.5) / u.res.x * z * 6.0, gz = z * 1.2 - t * 1.5;
            float gl = max(smoothstep(0.46, 0.5, abs(fract(gx) - 0.5)), smoothstep(0.46, 0.5, abs(fract(gz) - 0.5)));
            col = float3(0.05, 0.0, 0.14) + float3(0.1, 0.9, 1.0) * gl * saturate(1.2 / z + 0.25) * u.inn + float3(1.0, 0.2, 0.6) * exp(-(p.y - hz) / (14.0 * dpr)) * 0.4; }
        float3 lg = mix(float3(1.0, 0.92, 0.35), float3(1.0, 0.2, 0.7), saturate(uv.y * 1.3));
        col += float3(0.2, 0.9, 1.0) * (gn.x * 0.6 + gw.x * 1.0) * u.inn;
        col = mix(col, lg * (1.0 + heat * 0.4), saturate(la)); acc = float3(1.0, 0.4, 0.8); vig = 0.5;
    } else { // ===== LUMINOFOR: świeci w ciemności i gaśnie =====
        bgFlat = float3(0.02, 0.01, 0.04);
        col = bgFlat + float3(0.1, 0.0, 0.22) * pow(fbm(q2 * 0.004 + t * 0.02), 2.0) * 0.8 * u.inn + float3(0.03) * hash(p);
        float a = clamp((u.w - tauAt(p, u, tTex)), 0.0, 1.0); float lum = 0.4 + 0.6 * exp(-a * 7.0);
        float3 ph = float3(0.45, 1.0, 0.35);
        col += ph * (gn.x * 0.6 + gw.x * 1.1) * 0.7 * u.inn * (0.65 + 0.35 * lum) * breath;
        col = mix(col, ph * lum * 1.1 + float3(0.4) * heat, saturate(la)); acc = ph; vig = 0.55;
    }
    float2 tipP = u.tip;
    if (st == 999) { float ya2 = 0.25 * sin(t * 0.42 - 0.5) * (0.35 + 0.65 * smoothstep(0.0, 2.0, t)); float fc = u.logoS.x * 2.4;
        float2 dT = u.tip - u.logoC; float s2 = fc / (fc + dT.x * sin(ya2)); tipP = u.logoC + float2(dT.x * cos(ya2) * s2, dT.y * s2); }
    if (u.tipA > 0.0) { float d = length(p - tipP) / (u.logoS.x * 0.012);
        col += (acc * exp(-d * d * 0.35) * 0.9 + float3(1.0) * exp(-d * d * 3.0)) * u.tipA * u.inn * tg; }
    if (tg < 0.5 && u.tipA > 0.0) { float d = length(p - tipP) / (u.logoS.x * 0.004); col = mix(col, nib, exp(-d * d) * u.tipA); }
    for (int i = 0; i < 32; i++) { float4 s = sparks[i]; if (s.z <= 0.0) continue;
        float d = length(p - s.xy) / s.w; if (d > 4.0) continue;
        col += mix(acc, float3(1.0), s.z) * exp(-d * d * 2.2) * s.z * 0.9 * tg; }
    col *= 1.0 - vig * smoothstep(0.55, 1.25, r);
    col += (hash(p + t * 60.0) - 0.5) * 0.014 * (1.0 - noGrain);
    float3 fadeC = (st == 0) ? float3(0.0) : bgFlat;   // Kredka: fade in/out z/do czerni
    return float4(mix(fadeC, col, u.out), 1.0);
}
// ================= FILM: kamera 3D nad kartką, makro, głębia ostrości, mokry tusz =================
constexpr sampler fRep(filter::linear, address::repeat, mip_filter::none);
static float nz(texture2d<float> nT, float2 x) { return nT.sample(fRep, x).r; }
static float inkF(float2 uv, constant U& u, texture2d<float> aTex, texture2d<float> tTex, thread float& heat) {
    constexpr sampler lin(filter::linear, address::clamp_to_edge), nea(filter::nearest, address::clamp_to_edge);
    heat = 0.0; if (any(uv < 0.0) || any(uv > 1.0)) return 0.0;
    float4 ab = aTex.sample(lin, uv); float thr = mix(0.5, 0.27, ab.g); float a = max(smoothstep(0.22, 0.78, ab.b), smoothstep(thr - 0.05, thr + 0.05, ab.r)), tau = tTex.sample(nea, uv).r;
    heat = exp(-max(u.w - tau, 0.0) / 0.05) * (u.w < 0.9999 ? 1.0 : 0.0);
    return a * smoothstep(0.0, 1.0, (u.w - tau) / u.soft);
}
static float3 fRay(float2 p, constant U& u) {
    float3 f = normalize(u.c1.xyz - u.c0.xyz); float3 r = normalize(cross(float3(0, -1, 0), f)); float3 d = cross(r, f);
    float2 s = (p - u.res * 0.5) / u.res.y; return normalize(f * u.c0.w + r * s.x + d * s.y); }
static float paperH(texture2d<float> nT, float2 pc) {
    float2 fb = float2(pc.x * 0.8 + pc.y * 0.6, pc.y * 0.8 - pc.x * 0.6);
    return nz(nT, pc * 2.6) * 0.55 + nz(nT, pc * 7.0) * 0.3 + nz(nT, fb * float2(38.0, 6.0)) * 0.12; }
// blot (kleks): zwraca pokrycie, ustawia pochyłość kopułki
static float blotF(float2 P, constant U& u, texture2d<float> nT, thread float2& slope) {
    slope = 0.0; float asp = u.c2.x;
    float2 bd = P - float2(0.375, 0.24 * asp);
    if (dot(bd, bd) > 0.01) return 0.0;
    float bt = saturate((u.p1 - 1.9) / 0.18); if (bt <= 0.0) return 0.0;
    float gro = 1.0 - pow(1.0 - bt, 3.0), R = 0.017 * (0.35 + 0.65 * gro);
    float2 q = bd / R;
    float fld = exp(-dot(q, q) * 1.1);
    for (int i = 0; i < 6; i++) { float fi = float(i);
        float an = fi * 1.047 + hash(float2(fi, 1.0)) * 0.9, ds = 0.45 + 0.45 * hash(float2(fi, 2.0)), sg = 0.28 + 0.3 * hash(float2(fi, 4.0));
        float2 e = q - float2(cos(an), sin(an)) * ds; fld += 0.75 * exp(-dot(e, e) / (sg * sg)); }
    float2 fdir = normalize(float2(0.85, 0.5));
    for (int i = 1; i <= 3; i++) { float fi = float(i); float2 e = q - fdir * (0.75 + 0.42 * fi); float sg = 0.32 - 0.07 * fi; fld += 0.8 * exp(-dot(e, e) / (sg * sg)); }
    fld += 0.22 * (nz(nT, q * 0.08 + 0.3) - 0.5);
    float blot = smoothstep(0.47, 0.53, fld);
    float spr = 0.0;
    for (int i = 0; i < 10; i++) { float fi = float(i);
        float an = atan2(fdir.y, fdir.x) + (hash(float2(fi, 11.0)) - 0.5) * 1.9, ds = 1.5 + 2.4 * hash(float2(fi, 13.0));
        float2 dv = float2(cos(an), sin(an)), e = q - dv * ds * (0.5 + 0.5 * gro);
        float rr = (0.2 - 0.04 * ds) * (0.6 + 0.6 * hash(float2(fi, 17.0)));
        spr = max(spr, smoothstep(rr + 0.03, rr - 0.03, length(float2(dot(e, dv) / 1.7, dot(e, float2(-dv.y, dv.x))))) * step(0.25, bt)); }
    slope = normalize(q + 1e-4) * (1.0 - smoothstep(0.5, 1.6, fld)) * 1.4;
    return max(blot, spr);
}
static float3 fSurf(float2 p, constant U& u, texture2d<float> aTex, texture2d<float> tTex, texture2d<float> nT, float q, thread float& depth) {
    bool hq = q > 1.5;
    float3 rd = fRay(p, u); float th = -u.c0.z / min(rd.z, -1e-3); float3 P = u.c0.xyz + rd * th; depth = th;
    float asp = u.c2.x; float2 uv = float2(P.x + 0.5, P.y / asp + 0.5);
    float3 L = normalize(float3(-0.55, -0.8, 0.55)), V = -rd;
    // papier: ciepła biel, ząbek i włókna oświetlone z boku, plama światła
    float h0 = paperH(nT, P.xy), e = 0.0012;
    float3 np = float3(0, 0, 1);
    if (q > 0.5) { float hx = paperH(nT, P.xy + float2(e, 0)), hy = paperH(nT, P.xy + float2(0, e)); np = normalize(float3(-(hx - h0) * 1.3, -(hy - h0) * 1.3, 1.0)); }
    float3 alb = float3(0.95, 0.94, 0.91) * (0.95 + 0.07 * nz(nT, P.xy * 0.35 + 3.0)) * (0.97 + 0.05 * h0);
    float pool = exp(-dot(P.xy - float2(-0.05, -0.02), P.xy - float2(-0.05, -0.02)) * 1.3);
    np = normalize(np + float3(cos(P.x * 6.0 + 1.3) * 0.035 + cos(P.y * 4.0 + P.x * 2.0) * 0.02, sin(P.y * 7.5 + P.x * 2.5) * 0.03, 0.0));   // lekkie pofalowanie kartki
    float winL = mix(0.84, 1.07, smoothstep(0.9, -0.7, P.x * 0.7 + P.y * 0.9));                                                    // światło z okna (lewa-góra)
    float3 paper = alb * (0.32 + 0.78 * saturate(dot(np, L))) * (0.62 + 0.5 * pool) * winL;
    // kartka leży lekko skośnie na ciemnym, orzechowym blacie
    float2 pr = float2x2(0.99905, 0.04362, -0.04362, 0.99905) * P.xy;
    float2 bq = abs(pr - float2(0.05, -0.03)) - float2(0.6, 0.32); float sd = length(max(bq, 0.0)) + min(max(bq.x, bq.y), 0.0) - 0.004;
    if (sd > 0.0) {
        float g = 0.5 + 0.5 * sin(pr.y * 150.0 + nz(nT, P.xy * 0.9) * 9.0 + sin(pr.x * 3.0) * 2.5);
        float3 wood = mix(float3(0.075, 0.04, 0.022), float3(0.2, 0.11, 0.055), g * 0.7 + 0.3 * nz(nT, P.xy * 2.0));
        float3 Hd = normalize(L + V); float spw = pow(saturate(Hd.z), 40.0) * 0.12;
        float3 desk = wood * (0.35 + 0.75 * saturate(L.z)) * winL + spw;
        desk *= 1.0 - 0.6 * exp(-sd / 0.007);
        return desk; }
    paper *= 1.0 - 0.06 * exp(sd / 0.0025);
    // tusz
    float heat; float la = inkF(uv, u, aTex, tTex, heat);
    float h2; float halo = hq ? inkF(uv + (float2(nz(nT, P.xy * 5.0), nz(nT, P.xy * 5.0 + 0.5)) - 0.5) * 0.0016, u, aTex, tTex, h2) : 0.0;
    paper = mix(paper, paper * float3(0.72, 0.78, 0.95), halo * 0.12 * (1.0 - la));     // wsiąkanie we włókna
    float2 bs; float bl = blotF(P.xy, u, nT, bs);
    float cov = max(la, bl);
    if (cov < 0.002) return paper;
    float2 g = float2(0.0);
    if (hq && la > 0.002) { float hh; float d = 0.0011;
        g = float2(inkF(uv + float2(d, 0), u, aTex, tTex, hh) - inkF(uv - float2(d, 0), u, aTex, tTex, hh),
                   inkF(uv + float2(0, d), u, aTex, tTex, hh) - inkF(uv - float2(0, d), u, aTex, tTex, hh)) * 1.1; }
    g = mix(g, bs, step(la, bl));
    float3 n = normalize(float3(-g, 1.0));
    float3 inkAlb = mix(float3(0.02, 0.035, 0.13), float3(0.05, 0.1, 0.34), saturate(heat) * 0.7);
    float3 ink = inkAlb * (0.35 + 0.65 * saturate(dot(n, L)));
    float wet = 0.75 + 0.25 * saturate(heat);
    float F = 0.04 + 0.96 * pow(1.0 - saturate(dot(n, V)), 5.0);
    float3 Hh = normalize(L + V); float spec = pow(saturate(dot(n, Hh)), 140.0) * 3.0;
    float3 R = reflect(rd, n);
    float win = 0.6 * smoothstep(0.7, 0.9, dot(R, normalize(float3(-0.45, -0.75, 0.5))));        // odbicie okna
    float sw = u.c2.y; float spec2 = 0.0;
    if (sw > 0.0 && sw < 1.0) { float3 L2 = normalize(float3(mix(-1.4, 1.4, sw), -0.35, 0.6)); spec2 = pow(saturate(dot(n, normalize(L2 + V))), 160.0) * 2.2; }
    ink += (float3(1.0, 0.97, 0.92) * (spec + spec2) + float3(0.75, 0.85, 1.0) * win * 0.55) * mix(0.5, 1.0, F) * wet * (hq ? 1.0 : 0.4);
    ink += float3(0.85, 0.92, 1.0) * F * 0.035 * wet;
    return mix(paper, ink, smoothstep(0.02, 0.55, cov));
}
// ---- pióro wieczne (SDF) ----
constant float3 PD = float3(0.6, 0.25, 0.75) / 1.0012;
constant float PK = 1.5, LN = 0.075;
constant float3 PUP = float3(-0.6854, -0.2856, 0.6699);
constant float3 PSD = float3(0.3812, -0.9149, 0.0);
static float penR(float s) {
    if (s < LN) return 0.0105 * PK * pow(saturate(s / LN), 0.75);
    if (s < LN + 0.06 * PK) return mix(0.0115, 0.0128, (s - LN) / (0.06 * PK)) * PK;
    if (s < LN + 0.067 * PK) return 0.0146 * PK;
    return 0.0152 * PK; }
// pióro wieczne: stalówka (zwinięta płytka ze szczeliną, otworem i kulką), podajnik z żeberkami, sekcja, pierścień, korpus
static float2 penMap(float3 x, float3 A) {
    float3 v = x - A; float s = dot(v, PD), lx = dot(v, PSD), ly = dot(v, PUP); float rho = length(float2(lx, ly));
    float d = 1e9, id = 0.0;
    { float rc = 0.0105 * PK * pow(saturate(s / LN), 0.75), ang = atan2(abs(lx), ly + 1e-6);
      float fm = mix(0.32, 1.95, smoothstep(0.0, 0.62 * LN, s)) - 0.25 * smoothstep(0.8 * LN, LN, s);
      float dn = abs(rho - rc) - 0.0005 * PK;
      dn = max(dn, (ang - fm) * max(rho, 2e-4));
      dn = max(dn, max(-s, s - LN));
      if (s < 0.6 * LN && ly > 0.0) dn = max(dn, 0.00022 * PK - abs(lx));
      dn = max(dn, 0.0014 * PK - length(float2(lx, s - 0.62 * LN)));
      dn = min(dn, length(v - PD * 0.0008 * PK) - 0.0009 * PK);
      if (dn < d) { d = dn; id = 1.0; } }
    { float rc = 0.0105 * PK * pow(saturate(s / LN), 0.75) - 0.0013 * PK;
      float df = max(rho - rc + 0.0006 * PK * step(0.5, fract(s * 260.0 / PK)) * step(ly, -0.002), ly - 0.0003 * PK);
      df = max(df, max(0.014 * PK - s, s - LN - 0.01 * PK));
      if (df < d) { d = df; id = 2.0; } }
    { float s0 = LN - 0.004 * PK, s1 = LN + 0.06 * PK;
      float r = mix(0.0115, 0.0128, saturate((s - s0) / (s1 - s0))) * PK + 0.0008 * PK * exp(-pow((s - s0 - 0.003 * PK) / (0.0018 * PK), 2.0));
      float ds = max(rho - r, max(s0 - s, s - s1)); if (ds < d) { d = ds; id = 3.0; } }
    { float s0 = LN + 0.06 * PK, s1 = s0 + 0.007 * PK; float dr = max(rho - 0.0146 * PK, max(s0 - s, s - s1)); if (dr < d) { d = dr; id = 4.0; } }
    { float s0 = LN + 0.067 * PK, s1 = 0.62 * PK; float r = 0.0152 * PK * (1.0 - 0.07 * smoothstep(s1 - 0.15 * PK, s1, s));
      float db = max(rho - r, max(s0 - s, s - s1)); if (db < d) { d = db; id = 5.0; } }
    return float2(d * 0.7, id); }
static float2 segRay(float3 O, float3 rd, float tmax, float3 A, thread float& sc) {
    float3 w0 = O - A; float b = dot(rd, PD), d = dot(rd, w0), e = dot(PD, w0), den = max(1.0 - b * b, 1e-5);
    sc = clamp((e - b * d) / den, 0.0, 0.95); float tc = clamp(dot(A + PD * sc - O, rd), 0.0, tmax);
    sc = clamp(dot(O + rd * tc - A, PD), 0.0, 0.95);
    return float2(length(O + rd * tc - (A + PD * sc)), tc); }
static float3 envC(float3 R) {
    float3 c = mix(float3(0.62, 0.6, 0.57), float3(0.04, 0.045, 0.06), saturate(R.z * 1.5 + 0.3));
    c += float3(1.0, 0.98, 0.95) * 2.4 * smoothstep(0.80, 0.95, dot(R, normalize(float3(-0.45, -0.75, 0.5))));
    c += float3(0.9, 0.95, 1.0) * 0.9 * smoothstep(0.9, 0.97, dot(R, normalize(float3(0.8, -0.2, 0.55))));
    return c; }
static float3 fShade(float2 p, constant U& u, texture2d<float> aTex, texture2d<float> tTex, texture2d<float> nT, float q, thread float& depth) {
    bool hq = q > 1.5;
    float3 O = u.c0.xyz, rd = fRay(p, u); float th = -O.z / min(rd.z, -1e-3);
    float3 A = float3(u.p2, u.p3, 0.0004) + PD * u.c2.w;
    bool penOn = u.c2.w < 1.25;
    if (penOn) { float sc; float2 dr = segRay(O, rd, th, A, sc);
        if (dr.x < 0.03) { float tt = max(dr.y - 0.16, 0.0); int N = hq ? 72 : 28;
            for (int i = 0; i < N; i++) { float3 x = O + rd * tt; float2 m = penMap(x, A);
                if (m.x < 0.00005) { // trafienie w pióro
                    float2 k = float2(1, -1) * 0.00012;
                    float3 n = normalize(k.xyy * penMap(x + k.xyy, A).x + k.yyx * penMap(x + k.yyx, A).x + k.yxy * penMap(x + k.yxy, A).x + k.xxx * penMap(x + k.xxx, A).x);
                    float3 v = x - A; float s = dot(v, PD), lx = dot(v, PSD);
                    float3 R = reflect(rd, n), L = normalize(float3(-0.55, -0.8, 0.55));
                    float nv = saturate(dot(n, -rd)), F = 0.04 + 0.96 * pow(1.0 - nv, 5.0);
                    float spk = pow(saturate(dot(n, normalize(L - rd))), 220.0) * 2.5;
                    float3 c; int id = int(m.y + 0.5);
                    if (id == 1) { bool rh = s < 0.36 * LN;
                        float3 tint = rh ? float3(0.86, 0.87, 0.9) : float3(1.0, 0.77, 0.4);
                        float eng = rh ? 0.0 : smoothstep(0.6, 0.95, sin(s * 2600.0 / PK + sin(lx * 1900.0 / PK) * 2.2)) * smoothstep(0.42 * LN, 0.5 * LN, s) * (1.0 - smoothstep(0.55 * LN, 0.68 * LN, s) * smoothstep(0.75 * LN, 0.68 * LN, s));
                        c = tint * envC(R) * (1.0 - 0.45 * eng) + tint * spk;
                        if (rh) c = mix(c, float3(0.02), smoothstep(0.35 * LN, 0.37 * LN, s) * 0.6); }
                    else if (id == 2) c = float3(0.012) * (0.4 + saturate(dot(n, L))) + envC(R) * F * 0.3;
                    else if (id == 4) c = float3(1.0, 0.78, 0.42) * envC(R) + spk;
                    else { float3 base = id == 3 ? float3(0.01) : float3(0.008, 0.014, 0.05);
                        c = base * (0.3 + saturate(dot(n, L))) + envC(R) * (0.04 + 0.96 * F) * 0.85 + float3(1.0) * spk; }
                    depth = tt; return c; }
                tt += m.x; if (tt > th) break; } } }
    float3 col = fSurf(p, u, aTex, tTex, nT, q, depth);
    if (penOn) { float3 P = O + rd * th, L = normalize(float3(-0.55, -0.8, 0.55)); float sc;
        float2 dr = segRay(P, L, 2.0, A, sc); float pr = penR(sc), pen = 0.0012 + 0.07 * dr.y;
        float occ = 1.0 - smoothstep(pr - pen, pr + pen, dr.x);
        col *= 1.0 - 0.55 * occ * (1.0 - smoothstep(0.3, 0.9, u.c2.w)); }
    return col; }
fragment float4 ffilm(VO in [[stage_in]], constant U& u [[buffer(0)]], texture2d<float> aTex [[texture(0)]], texture2d<float> tTex [[texture(1)]], texture2d<float> nT [[texture(4)]]) {
    float2 p = in.pos.xy; float dpr = u.res.y / 900.0;
    // płynna głębia ostrości: rozmycie liczone z odległości płaszczyzny papieru, faktura papieru gaśnie razem z ostrością
    float3 rd0 = fRay(p, u); float d0 = -u.c0.z / min(rd0.z, -1e-3);
    float coc0 = u.c1.w * abs(d0 - u.c2.z) / d0 * u.res.y;
    float sharp = 1.0 - smoothstep(0.4 * dpr, 3.5 * dpr, coc0);
    float depth; float3 c = fShade(p, u, aTex, tTex, nT, 2.0, depth); (void)sharp;
    float coc = min(u.c1.w * abs(depth - u.c2.z) / depth * u.res.y, 48.0 * dpr);
    float bw = smoothstep(0.4 * dpr, 2.5 * dpr, coc);
    if (bw > 0.0) { int n = int(clamp(coc / (3.4 * dpr), 4.0, 10.0)); float3 acc = float3(0.0); float rot = hash(p) * 6.2832;
        for (int i = 0; i < n; i++) { float fi = float(i) + 0.5; float rr = sqrt(fi / float(n)) * coc, an = fi * 2.39996 + rot; float dd;
            acc += fShade(p + float2(cos(an), sin(an)) * rr, u, aTex, tTex, nT, 1.0, dd); }
        c = mix(c, (acc + c) / float(n + 1), bw); }
    // obraz: ekspozycja, krzywa filmowa, gradacja, winieta, ziarno, kadr kinowy
    c *= 1.6;
    c = saturate((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14));
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    c += mix(float3(-0.012, 0.004, 0.022), float3(0.018, 0.006, -0.014), smoothstep(0.2, 0.8, lum));
    float2 vq = (p - u.res * 0.5) / u.res; float vg = dot(vq * float2(1.0, 1.15), vq * float2(1.0, 1.15));
    c *= 1.0 - 0.95 * pow(vg, 1.15);
    c += (hash(p + fract(u.t * 7.31) * 517.0) - 0.5) * 0.04 * (0.6 + 0.4 * (1.0 - lum));
    float visH = min(u.res.y, u.res.x / 2.39);
    if (u.c3.z > 0.5) c *= smoothstep(0.0, 1.0, visH * 0.5 - abs(p.y - u.res.y * 0.5) + 0.5);
    return float4(saturate(c) * u.out, 1.0);
}
"""#

private struct TMIUni { var res = SIMD2<Float>(), logoC = SIMD2<Float>(), logoS = SIMD2<Float>(), tip = SIMD2<Float>()
                     var t: Float = 0, w: Float = 0, inn: Float = 0, out: Float = 1, tipA: Float = 0, shim: Float = 0, soft: Float = 0, pad: Float = 0, style: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0
                     var c0 = SIMD4<Float>(), c1 = SIMD4<Float>(), c2 = SIMD4<Float>(), c3 = SIMD4<Float>() }

final class TMIntroView: MTKView {
    var onFinish: (() -> Void)?
    var loop = false
    var soundEnabled = true
    private let film = TMIFilmSound(); private var sndPen = SIMD2<Float>(0, 0), sndLift: Float = 1, sndTouch: Float = 0, sndT = 0.0
    /// false = po zakończeniu logo zostaje na ekranie (podgląd); true = wygaszenie (intro w grze)
    var fadeOut = true
    /// 0 Chrom 3D · 1 Blueprint · 2 Papier · 3 Żarówka · 4 Laser
    var style = 0
    var letterbox = true   // pasy kinowe 2.39:1 (w grach wyłączone)
    static let styleNames = ["Kredka", "Ołówek", "Akwarela", "Piasek", "Szron", "Neon na cegle", "Graffiti", "Deszcz", "CRT", "Mozaika", "Drewno", "Warstwice", "Synthwave", "Luminofor"]
    private let pen = TMIPenSound()
    private var lastTip = SIMD2<Float>(0, 0), speedSm: Float = 0
    /// całkowity czas animacji w sekundach
    let duration: Double
    private var pipe: MTLRenderPipelineState!, pipeInk: MTLRenderPipelineState!, pipeFilm: MTLRenderPipelineState!, noiseTex: MTLTexture!
    private var inkTex: MTLTexture?, blurN: MTLTexture?, blurW: MTLTexture?, blurSize = CGSize.zero
    private var gaussN: MPSImageGaussianBlur?, gaussW: MPSImageGaussianBlur?
    private var queue: MTLCommandQueue!
    private var texA: MTLTexture?, texT: MTLTexture?, texRG: MTLTexture?
    private var bake: LogoBake?
    private var startTime: CFTimeInterval = 0
    private var started = false, finished = false
    private var tipSm = SIMD2<Float>(0, 0), tipSmA: Float = 0, camSegs: [(Float, Float, SIMD2<Float>, SIMD2<Float>, Float)] = [], camP = SIMD3<Float>(), camT = SIMD3<Float>(), camPV = SIMD3<Float>(), camTV = SIMD3<Float>(), camLastT = -1.0, camTip = SIMD2<Float>(-0.4, 0), penTip = SIMD2<Float>(-0.45, 0)
    private struct Spark { var p: SIMD2<Float>, v: SIMD2<Float>, life: Float, max: Float }
    private var sparks: [Spark] = [], lastT = 0.0

    init(frame: CGRect, duration: Double = 19.5) {
        self.duration = duration
        let dev = MTLCreateSystemDefaultDevice()!
        super.init(frame: frame, device: dev)
        colorPixelFormat = .bgra8Unorm
        queue = dev.makeCommandQueue()
        let lib = try! dev.makeLibrary(source: tmIntroShader, options: nil)
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: "vmain"); d.fragmentFunction = lib.makeFunction(name: "fmain")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipe = try! dev.makeRenderPipelineState(descriptor: d)
        let di = MTLRenderPipelineDescriptor()
        di.vertexFunction = lib.makeFunction(name: "vmain"); di.fragmentFunction = lib.makeFunction(name: "imain")
        di.colorAttachments[0].pixelFormat = .rgba16Float
        pipeInk = try! dev.makeRenderPipelineState(descriptor: di)
        let dfm = MTLRenderPipelineDescriptor()
        dfm.vertexFunction = lib.makeFunction(name: "vmain"); dfm.fragmentFunction = lib.makeFunction(name: "ffilm")
        dfm.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeFilm = try! dev.makeRenderPipelineState(descriptor: dfm)
        var nb = [UInt8](repeating: 0, count: 256 * 256); var sd: UInt64 = 0x9E3779B97F4A7C15
        for k in 0..<nb.count { sd = sd &* 6364136223846793005 &+ 1442695040888963407; nb[k] = UInt8(truncatingIfNeeded: sd >> 56) }
        let nd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 256, height: 256, mipmapped: false)
        noiseTex = dev.makeTexture(descriptor: nd)!; noiseTex.replace(region: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0, withBytes: nb, bytesPerRow: 256)
        preferredFramesPerSecond = 60
        isPaused = true; enableSetNeedsDisplay = false
    }
    required init(coder: NSCoder) { fatalError() }
    /// Render w 64% rozdzielczości Retiny (ziarno i głębia ostrości to maskują) – stałe 60 kl./s.
    override func layout() { super.layout(); if style == 0 { autoResizeDrawable = false
        let sc = (window?.backingScaleFactor ?? 2) * 0.64; drawableSize = CGSize(width: bounds.width * sc, height: bounds.height * sc) } }

    /// Buduje tekstury (ok. 1 s w tle), potem startuje animację.
    func start() {
        finished = false; started = false
        if bake != nil { begin(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let b = bakeLogo(width: 4096)
            DispatchQueue.main.async { self.setBake(b); self.begin() }
        }
    }
    func bakeSynchronously() { if bake == nil { setBake(bakeLogo(width: 4096)) } }
    private func begin() { startTime = CACurrentMediaTime(); started = true; isPaused = false; if soundEnabled { if style == 0 { film.start(writeEnd: Float(duration - 6.6), duration: Float(duration)) } else { pen.start() } } }
    private func setBake(_ b: LogoBake) {
        bake = b; let dev = device!
        func tex(_ f: MTLPixelFormat, _ w: Int, _ h: Int, _ p: UnsafeRawPointer, _ bpr: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
            let t = dev.makeTexture(descriptor: d)!; t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: p, bytesPerRow: bpr); return t }
        texA = b.alpha.withUnsafeBytes { tex(.r8Unorm, b.w, b.h, $0.baseAddress!, b.w) }
        texRG = b.rg.withUnsafeBytes { tex(.rgba8Unorm, b.w, b.h, $0.baseAddress!, b.w * 4) }
        texT = b.tau.withUnsafeBytes { tex(.r32Float, b.w, b.h, $0.baseAddress!, b.w * 4) }
    }

    override func draw(_ rect: NSRect) {
        guard started, let drawable = currentDrawable, let rpd = currentRenderPassDescriptor else { return }
        let t = CACurrentMediaTime() - startTime
        render(t: t, rpd: rpd, size: drawableSize, present: drawable)
        if t >= duration {
            if loop { startTime = CACurrentMediaTime(); tipSmA = 0 }
            else if !finished { finished = true; if fadeOut { isPaused = true }; pen.stop(); film.stop(); onFinish?() }
        }
    }
    override func mouseDown(with e: NSEvent) { skip() }
    override func keyDown(with e: NSEvent) { skip() }
    override var acceptsFirstResponder: Bool { true }
    func skip() { if !finished { finished = true; isPaused = true; pen.stop(); film.stop(); onFinish?() } }

    private func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
    private func timeline(_ t: Double) -> (w: Float, inn: Float, out: Float, shim: Float) {
        let ws = 0.5, we = duration - 6.6                      // pisanie
        let x = min(max((t - ws) / (we - ws), 0), 1)
        let w = x * 0.7 + (x * x * (3 - 2 * x)) * 0.3
        let inn = 1 - pow(1 - min(max(t / 0.8, 0), 1), 3)
        let shim = (t - (we + 0.25)) / 0.9
        let out = Float(ease(t / 1.1)) * (fadeOut ? Float(1 - ease((t - (duration - 0.95)) / 0.85)) : 1)
        return (Float(w), Float(inn), out, Float(shim))
    }
    /// Rysuje klatkę dla czasu t (sekundy) do podanego celu.
    func render(t: Double, rpd: MTLRenderPassDescriptor, size: CGSize, present: MTLDrawable?) {
        guard let b = bake, let ta = texA, let tt = texT else { return }
        let tl = timeline(t)
        var u = TMIUni()
        let W = Float(size.width), H = Float(size.height)
        let aspect = Float(b.h) / Float(b.w)
        let lw = min(W * 0.7, H * 0.62 * Float(tmVBW / tmVBH)) * 1.08
        let push = 1 + 0.18 * Float(ease(t / duration))
        u.res = SIMD2(W, H); u.logoS = SIMD2(lw * push, lw * push * aspect); u.logoC = SIMD2(W / 2, H / 2)
        u.style = Float(style); u.p1 = Float(t - (duration - 6.6)); u.t = Float(t); u.w = tl.w * (1 + b.soft); u.inn = tl.inn; u.out = tl.out; u.soft = b.soft
        u.shim = tl.shim > 0 && tl.shim < 1 ? tl.shim : 0
        if style == 0 {   // kamera filmowa (deterministyczna – działa też w arkuszu)
            let nb = b.tipBins.count; var acc = SIMD2<Float>(0, 0), ws: Float = 0
            var ay: Float = 0, wy: Float = 0
            for k in -110...110 { let ww = min(max(tl.w + Float(k) * 0.0025, 0), 1); let bn = b.tipBins[min(nb - 1, Int(ww * Float(nb - 1)))]
                let q = SIMD2(bn.x / Float(b.w) - 0.5, (bn.y / Float(b.h) - 0.5) * aspect)
                let kx = Float(k) * 0.0025 / 0.07, ky = Float(k) * 0.0025 / 0.12
                let wt = expf(-kx * kx); acc.x += q.x * wt; ws += wt
                let wty = expf(-ky * ky); ay += q.y * wty; wy += wty }
            if ws > 0 { acc.y = ay / wy * ws }
            if ws > 0 { camTip = acc / ws }
            func binAt(_ ww: Float) -> SIMD2<Float> { let f = min(max(ww, 0), 1) * Float(nb - 1); let i0 = min(Int(f), nb - 2); let fr = f - Float(i0)
                let a = b.tipBins[i0], c = b.tipBins[i0 + 1]
                return SIMD2((a.x + (c.x - a.x) * fr) / Float(b.w) - 0.5, ((a.y + (c.y - a.y) * fr) / Float(b.h) - 0.5) * aspect) }
            func PP(_ i: Int) -> SIMD2<Float> { let bn = b.tipBins[i]; return SIMD2(bn.x / Float(b.w) - 0.5, (bn.y / Float(b.h) - 0.5) * aspect) }
            let tauF = min(max(u.w - 0.4 * b.soft, 0), 1), fi = tauF * Float(nb - 1), i0 = min(Int(fi), nb - 1)
            var prv = i0; while prv >= 0 && b.tipBins[prv].z <= 0 { prv -= 1 }
            var nxt = i0; while nxt < nb && b.tipBins[nxt].z <= 0 { nxt += 1 }
            var lift: Float = 0
            if b.tipBins[i0].z > 0 { let i1 = min(i0 + 1, nb - 1); penTip = b.tipBins[i1].z > 0 ? simd_mix(PP(i0), PP(i1), SIMD2(repeating: fi - Float(i0))) : PP(i0) }
            else if prv >= 0 && nxt < nb { let f = (fi - Float(prv)) / Float(nxt - prv); penTip = simd_mix(PP(prv), PP(nxt), SIMD2(repeating: f)); lift = 0.035 * sinf(.pi * f) }
            else if prv >= 0 { penTip = PP(prv) } else if nxt < nb { penTip = PP(nxt) }
            let weP = duration - 6.6
            if t < 0.5 { lift = 0.04 * Float(1 - ease(t / 0.5)) }
            if tl.w >= 1 { lift = 1.3 * Float(ease((t - weP - 0.75) / 1.3)) }
            u.p2 = penTip.x; u.p3 = penTip.y
            if present != nil && soundEnabled {   // dźwięk pióra z prawdziwego ruchu stalówki po papierze
                let sdt = Float(max(t - sndT, 1e-3)); sndT = t
                let v = simd_length(penTip - sndPen) / sdt; sndPen = penTip
                let onP: Float = (lift < 0.002 && tl.w > 0.0005 && tl.w < 0.9995) ? 1 : 0
                if onP > 0 && sndLift > 0.5 { sndTouch += 1; film.p[4] = sndTouch }
                sndLift = onP > 0 ? 0 : 1
                film.p[0] = onP * 0.9; film.p[1] = min(1, v / 0.12); film.p[5] = max(-1, min(1, penTip.x * 1.6))
                film.p[3] = tl.out
            }
            let foc: Float = 2.0
            let dFin = max(foc / (0.74 * W / H), foc * aspect / 0.62)
            let we = duration - 6.6
            let k = Float(ease((t - (we + 0.55)) / 3.0))
            let hand = SIMD3<Float>(0, 0, 0)
            if camSegs.isEmpty {   // odcinki pisania rozdzielone długimi przelotami pióra
                var segs: [(Float, Float, SIMD2<Float>, SIMD2<Float>, Float)] = []
                var sStart = 0, i = 0
                func Q(_ k: Int) -> SIMD2<Float> { let bn = b.tipBins[k]; return SIMD2(bn.x / Float(b.w) - 0.5, (bn.y / Float(b.h) - 0.5) * aspect) }
                func close(_ e: Int) { if e - sStart < 8 { return }
                    var ym: Float = 0; for k in sStart...e { ym += Q(k).y }; ym /= Float(e - sStart + 1)
                    let n5 = max(1, (e - sStart) / 20)
                    var a0 = SIMD2<Float>(0, 0), a1 = a0; for k in 0..<n5 { a0 += Q(sStart + k); a1 += Q(e - k) }
                    segs.append((Float(sStart) / Float(nb - 1), Float(e) / Float(nb - 1), a0 / Float(n5), a1 / Float(n5), ym)) }
                while i < nb { if b.tipBins[i].z <= 0 { var j = i; while j < nb && b.tipBins[j].z <= 0 { j += 1 }
                        if j < nb && simd_length(Q(j) - Q(max(i - 1, 0))) > 0.22 { close(i - 1); sStart = j }; i = j } else { i += 1 } }
                close(nb - 1); camSegs = segs }
            let tw = tl.w; var tg2 = SIMD2<Float>(camTip.x, camTip.y)
            func segAt(_ sg: (Float, Float, SIMD2<Float>, SIMD2<Float>, Float), _ tt: Float) -> SIMD2<Float> {
                var ax: Float = 0, ay: Float = 0, wx: Float = 0, wy: Float = 0
                let lo = Int(sg.0 * Float(nb - 1)), hi = Int(sg.1 * Float(nb - 1))
                for k in -60...60 { let ww = min(max(tt + Float(k) * 0.0015, Float(lo) / Float(nb - 1)), Float(hi) / Float(nb - 1))
                    let qq = binAt(ww); let qx = qq.x, qy = qq.y
                    let kx = Float(k) * 0.0015 / 0.045, ky = Float(k) * 0.0015 / 0.06
                    let w1 = expf(-kx * kx), w2 = expf(-ky * ky); ax += qx * w1; wx += w1; ay += qy * w2; wy += w2 }
                return SIMD2(ax / wx, ay / wy * 0.6 + sg.4 * 0.4) }
            if let first = camSegs.first {
                tg2 = segAt(first, tw)
                for (si, sg) in camSegs.enumerated() {
                    if tw >= sg.0 { tg2 = segAt(sg, tw) }
                    if si + 1 < camSegs.count { let nx = camSegs[si + 1]
                        let t0 = sg.1 - 0.03, t1 = nx.0 + 0.025
                        if tw > t0 && tw < t1 { let f = (tw - t0) / (t1 - t0); let e = f * f * (3 - 2 * f); tg2 = segAt(sg, tw) * (1 - e) + segAt(nx, tw) * e } } }
                let dv = penTip - (tg2 + SIMD2<Float>(0.03, 0.01)), dl = simd_length(dv)
                if dl > 0.07 { let x = min((dl - 0.07) / 0.1, 1); tg2 += dv / dl * (dl - 0.07) * x * x * (3 - 2 * x) }
                tg2 += SIMD2<Float>(0.03, 0.01)
            }
            if ProcessInfo.processInfo.environment["TM_CAM"] != nil { print("t", t, "tw", tl.w, "tg", tg2, "pen", penTip, "segs", camSegs.count) }
            let mT = SIMD3<Float>(tg2.x, tg2.y, 0)
            let mP = mT + SIMD3<Float>(-0.15, 0.46, 0.26) + hand
            let push = Float(1 - 0.06 * ease((t - we) / 3.0))
            let fT = SIMD3<Float>(0, 0.015, 0), fP = SIMD3<Float>(0, 0.16 * dFin * push, dFin * push) + hand * 0.4
            var cp = mP + (fP - mP) * k, ct = mT + (fT - mT) * k
            // krytycznie tłumiona sprężyna – kamera jak na wózku/steadicamie
            let cdt = Float(t - camLastT); camLastT = t
            if cdt <= 0 || cdt > 0.25 { camP = cp; camT = ct; camPV = .zero; camTV = .zero }
            else { let w: Float = 4.6
                for _ in 0..<4 { let h = cdt / 4
                    camPV += ((cp - camP) * w * w - camPV * 2 * w) * h; camP += camPV * h
                    camTV += ((ct - camT) * w * w - camTV * 2 * w) * h; camT += camTV * h } }
            cp = camP; ct = camT
            u.c0 = SIMD4(cp.x, cp.y, cp.z, foc); u.c1 = SIMD4(ct.x, ct.y, ct.z, 0.075 + (0.004 - 0.075) * k)
            let sw = Float((t - (we + 2.7)) / 1.6)
            u.c2 = SIMD4(aspect, sw, simd_length(cp - ct), lift)
            let lb = b.tipBins[nb - 1]; u.c3 = SIMD4(lb.x / Float(b.w) - 0.5, (lb.y / Float(b.h) - 0.5) * aspect, letterbox ? 1 : 0, 0)
        }
        // czubek pióra
        let bin = b.tipBins[min(b.tipBins.count - 1, max(0, Int(tl.w * Float(b.tipBins.count - 1))))]
        let active: Float = ((tl.w > 0.002 || t > 0.25) && tl.w < 0.999 && bin.z > 0) ? 1 : 0
        let target = SIMD2<Float>((bin.x / Float(b.w) - 0.5) * u.logoS.x + u.logoC.x, (bin.y / Float(b.h) - 0.5) * u.logoS.y + u.logoC.y)
        if active > 0 { tipSm = tipSmA > 0 ? tipSm + (target - tipSm) * 0.5 : target }
        tipSmA += (active - tipSmA) * 0.5
        u.tip = tipSm; u.tipA = tipSmA
        u.pad = tl.w >= 1 ? 1 + 0.07 * sinf(Float(t) * 2.4) * Float(ease((t - (duration - 6.6)) / 0.8)) : 1
        // iskry z czubka pióra
        let dt = Float(max(0, min(t - lastT, 0.1))); lastT = t
        if t < 0.05 { sparks.removeAll() }
        for i in sparks.indices { sparks[i].life -= dt; sparks[i].p += sparks[i].v * dt; sparks[i].v.y += 90 * dt * (H / 900); sparks[i].v *= 1 - 1.5 * dt }
        sparks.removeAll { $0.life <= 0 }
        if tipSmA > 0.6 && dt > 0 { let n = Int(dt * 110) + (Float.random(in: 0..<1) < dt * 110 - Float(Int(dt * 110)) ? 1 : 0)
            for _ in 0..<n where sparks.count < 32 {
                let a = Float.random(in: 0..<(2 * .pi)), sp = Float.random(in: 15...85) * (H / 900)
                sparks.append(Spark(p: tipSm, v: SIMD2(cosf(a), sinf(a) - 0.6) * sp, life: Float.random(in: 0.35...0.9), max: 0.9)) } }
        var sp4 = [SIMD4<Float>](repeating: .zero, count: 32)
        for (i, s) in sparks.enumerated() { sp4[i] = SIMD4(s.p.x, s.p.y, min(1, s.life / s.max * 1.3), (1.2 + 1.8 * s.life) * (H / 900)) }
        if present != nil && soundEnabled && style != 0 {
            let spd = simd_length(tipSm - lastTip) / (u.logoS.x * 0.012); lastTip = tipSm
            speedSm += (min(1, spd) - speedSm) * 0.15
            pen.update(active: min(1, tipSmA), speed: speedSm)
        }
        guard let cb = queue.makeCommandBuffer() else { return }
        // bufory bloomu (pół rozdzielczości)
        if blurSize != size || inkTex == nil {
            blurSize = size
            let hw = max(1, Int(size.width) / 2), hh = max(1, Int(size.height) / 2)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: hw, height: hh, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead, .shaderWrite]; d.storageMode = .private
            inkTex = device!.makeTexture(descriptor: d); blurN = device!.makeTexture(descriptor: d); blurW = device!.makeTexture(descriptor: d)
            gaussN = MPSImageGaussianBlur(device: device!, sigma: Float(u.logoS.x) * 0.0042)
            gaussW = MPSImageGaussianBlur(device: device!, sigma: Float(u.logoS.x) * 0.0150)
        }
        let ip = MTLRenderPassDescriptor(); ip.colorAttachments[0].texture = inkTex
        ip.colorAttachments[0].loadAction = .clear; ip.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1); ip.colorAttachments[0].storeAction = .store
        if let e1 = cb.makeRenderCommandEncoder(descriptor: ip) {
            e1.setRenderPipelineState(pipeInk)
            e1.setFragmentBytes(&u, length: MemoryLayout<TMIUni>.size, index: 0)
            e1.setFragmentTexture(ta, index: 0); e1.setFragmentTexture(tt, index: 1)
            e1.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e1.endEncoding()
        }
        gaussN!.encode(commandBuffer: cb, sourceTexture: inkTex!, destinationTexture: blurN!)
        gaussW!.encode(commandBuffer: cb, sourceTexture: inkTex!, destinationTexture: blurW!)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(style == 0 ? pipeFilm : pipe)
        enc.setFragmentTexture(noiseTex, index: 4)
        enc.setFragmentBytes(&u, length: MemoryLayout<TMIUni>.size, index: 0)
        enc.setFragmentBytes(&sp4, length: MemoryLayout<SIMD4<Float>>.stride * 32, index: 1)
        enc.setFragmentTexture(style == 0 ? (texRG ?? ta) : ta, index: 0); enc.setFragmentTexture(tt, index: 1)
        enc.setFragmentTexture(blurN, index: 2); enc.setFragmentTexture(blurW, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        if let d = present { cb.present(d) }
        cb.commit()
        if present == nil { cb.waitUntilCompleted() }
    }

    /// Arkusz kontaktowy do weryfikacji bez okna: kolumny × wiersze klatek w danych chwilach.
    func contactSheet(times: [Double], tile: CGSize, columns: Int, to path: String) {
        bakeSynchronously()
        if ProcessInfo.processInfo.environment["TM_BENCH"] != nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1638, height: 1024, mipmapped: false)
            d.usage = [.renderTarget]; d.storageMode = .private; let tex = device!.makeTexture(descriptor: d)!
            let rpd = MTLRenderPassDescriptor(); rpd.colorAttachments[0].texture = tex
            for tt in [2.0, 6.0, 10.0, 14.0, 16.5] { let t0 = CACurrentMediaTime()
                for k in 0..<20 { render(t: tt + Double(k) * 0.016, rpd: rpd, size: CGSize(width: 1638, height: 1024), present: nil) }
                print("t", tt, "ms/klatka", (CACurrentMediaTime() - t0) * 1000 / 20) }
        }
        let rows = (times.count + columns - 1) / columns
        let tw = Int(tile.width), th = Int(tile.height)
        var sheet = [UInt8](repeating: 0, count: tw * columns * th * rows * 4)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: tw, height: th, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .shared
        for (i, t) in times.enumerated() {
            let tex = device!.makeTexture(descriptor: d)!
            let rpd = MTLRenderPassDescriptor(); rpd.colorAttachments[0].texture = tex
            rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].storeAction = .store
            tipSmA = 0; sparks.removeAll(); lastT = 0
            // kilka klatek wstecz, żeby wygładzenie czubka pióra się ustaliło
            for k in stride(from: 150, through: 0, by: -1) { render(t: max(0, t - Double(k) * 0.016), rpd: rpd, size: tile, present: nil) }
            var row = [UInt8](repeating: 0, count: tw * th * 4)
            tex.getBytes(&row, bytesPerRow: tw * 4, from: MTLRegionMake2D(0, 0, tw, th), mipmapLevel: 0)
            let cx = (i % columns) * tw, cy = (i / columns) * th
            for y in 0..<th { for x in 0..<tw { for c in 0..<4 { sheet[(((cy + y) * tw * columns) + cx + x) * 4 + c] = row[(y * tw + x) * 4 + c] } } }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = sheet.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: tw * columns, height: th * rows, bitsPerComponent: 8, bytesPerRow: tw * columns * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)! }
        let img = ctx.makeImage()!
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
