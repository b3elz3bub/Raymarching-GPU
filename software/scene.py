"""
Raymarching Scene Reference — Python
FPGA project: VGA raymarcher, Person 4 (Shader + Top)

Scene: sphere floating above reflective checkerboard ground, sky, fog
Output: scene.png (RGB888 preview) + scene_rgb565.bin (raw RGB565 for FPGA sim)

Shader pipeline stages (each = one VHDL pipeline stage):
  1. Diffuse:   dot(normal, sun_dir) — fixed-point dot product
  2. Shadow:    ray march toward sun (1-bit flag from Person 3, or simplified)
  3. Specular:  Blinn-Phong pow() — LUT on 8-bit input
  4. Fresnel:   (1 - NoV)^5 — 4 multiplications
  5. Reflection: sky_col(reflect(ray_dir, normal)) — sky LUT
  6. Fog:       1 - exp(-t * k) — LUT indexed by march distance
  7. Gamma:     sqrt(linear) — LUT linear_to_srgb[256]
  8. Pack RGB565: R[4:0] G[5:0] B[4:0] — bit manipulation
"""

import numpy as np
from PIL import Image
import struct
import time
import sys

# ── Render resolution ─────────────────────────────────────────────
W, H = 640, 480
SAVE_PNG  = True
SAVE_BIN  = True   # raw RGB444 binary for FPGA simulation comparison


# ================================================================
# Vec3 helpers (numpy arrays)
# ================================================================
def nor(v):
    """Normalize a vector. FPGA: use iterative or CORDIC normalizer."""
    return v / np.linalg.norm(v)

def dot(a, b):
    return float(np.dot(a, b))

def mx0(x):
    """max(x, 0) — FPGA: just clamp negative values to zero."""
    return max(0.0, float(x))

def cl(x, lo, hi):
    return max(lo, min(hi, float(x)))

def mix(a, b, t):
    """Linear interpolation. FPGA: multiply-accumulate."""
    return a * (1.0 - t) + b * t

def ss(lo, hi, t):
    """Smoothstep. FPGA: LUT or just use linear mix if simpler."""
    x = cl((t - lo) / (hi - lo), 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)

def refl(d, n):
    """Reflect ray direction d over surface normal n.
    r = d - 2*(d·n)*n
    FPGA: two dot products + scale + subtract = ~6 multipliers."""
    return d - 2.0 * dot(d, n) * n


# ================================================================
# Scene constants
# ================================================================
SUN      = nor(np.array([0.7,  1.0, -0.4]))   # sun direction (world space)
SPHERE_C = np.array([0.0,  0.8,  3.0])         # sphere center
SPHERE_R = 0.5                                  # sphere radius
FOG_D    = 0.028                                # fog density coefficient
FOG_C    = np.array([0.76, 0.80, 0.87])        # fog color

# Material IDs
MAT_GROUND  = 0
MAT_SPHERE  = 1


# ================================================================
# Camera setup
# ================================================================
CAM    = np.array([0.0,  1.5, -3.0])
TARGET = np.array([0.0,  0.3,  5.0])
FWD    = nor(TARGET - CAM)
RGT    = nor(np.cross(np.array([0.0, 1.0, 0.0]), FWD))   # camera right
UUP    = np.cross(FWD, RGT)                               # camera up
FOV    = 0.60   # field-of-view scale


def gen_ray(px, py):
    u = ((px / W) * 2.0 - 1.0) * (W / H) * FOV
    v = (1.0 - (py / H) * 2.0) * FOV
    return nor(RGT * u + UUP * v + FWD)


# ================================================================
# SDFs
# ================================================================
def sd_scene(p):
    sph = np.linalg.norm(p - SPHERE_C) - SPHERE_R   # sphere SDF
    gnd = float(p[1])                                # ground plane y = 0
    if sph < gnd:
        return float(sph), MAT_SPHERE
    return float(gnd), MAT_GROUND


def march(ro, rd):
    t = 0.01
    for _ in range(96):
        p = ro + rd * t
        d, m = sd_scene(p)
        if d < 0.0002:
            return True, t, m, p
        t += d
        if t > 28.0:
            break
    return False, t, 0, None


def calc_normal(p):
    e = 0.0002
    return nor(np.array([
        sd_scene(p + [e, 0, 0])[0] - sd_scene(p - [e, 0, 0])[0],
        sd_scene(p + [0, e, 0])[0] - sd_scene(p - [0, e, 0])[0],
        sd_scene(p + [0, 0, e])[0] - sd_scene(p - [0, 0, e])[0],
    ]))


def soft_shadow(ro, rd):
    res, t = 1.0, 0.02
    for _ in range(20):
        d, _ = sd_scene(ro + rd * t)
        if d < 0.001:
            return 0.0
        res = min(res, 6.0 * d / t)
        t  += cl(d, 0.02, 0.5)
        if t > 7.0:
            break
    return cl(res, 0.0, 1.0)


# ================================================================
# SHADER STAGE 1: Sky color
# Input:  ray_dir (unit vec3)
# Output: RGB float [0..1]
#
# FPGA implementation notes:
#   - rd[1] (y-component) drives a 64-entry gradient LUT
#   - sun_dot = dot(rd, SUN) — standard fixed-point dot product
#   - pow(sun_dot, 7)  → LUT_GLOW[8-bit input]
#   - pow(sun_dot, 512)→ LUT_DISC[8-bit input]  (very narrow, spike-like)
# ================================================================
def sky_col(rd):
    t    = cl(rd[1] * 0.5 + 0.5, 0.0, 1.0)
    col  = mix(np.array([0.88, 0.84, 0.76]),   # horizon: warm cream
               np.array([0.18, 0.38, 0.82]),   # zenith:  deep blue
               ss(0.0, 0.55, t))
    s    = mx0(dot(rd, SUN))
    col += np.array([1.0, 0.65, 0.20]) * (s**7  * 0.8)    # glow halo
    col += np.array([1.0, 0.97, 0.88]) * (s**512)          # sun disc
    return col


# ================================================================
# MAIN SHADER
#
# Inputs arriving from Person 3 (pipeline registers):
#   hit_flag  : std_logic
#   mat_id    : unsigned(1 downto 0)   -- 1=ground, 2=sphere
#   hit_pos   : sfixed(8 downto -7)    -- x,y,z world-space hit point
#   normal    : sfixed(1 downto -14)   -- x,y,z unit normal
#   march_t   : sfixed(8 downto -7)    -- total march distance (for fog)
#
# Inputs passed through from Person 2:
#   ray_dir   : sfixed(1 downto -14)   -- x,y,z unit ray direction
#
# Output:
#   rgb444_out : std_logic_vector(11 downto 0)
#                R[11:8] G[7:4] B[3:0]
# ================================================================
def shade(ro, rd):
    hit, t, mat, p = march(ro, rd)

    # ── Miss → sky ──────────────────────────────────────────────
    if not hit:
        return sky_col(rd)

    n    = calc_normal(p)
    pe   = p + n * 0.003       # offset point off surface (prevents self-shadow)
    diff = mx0(dot(n, SUN))    # Lambertian: how much light hits the surface
    shad = soft_shadow(pe, SUN)
    rfl  = refl(rd, n)         # reflected ray direction

    # ── Ground material (mat_id = 0) ────────────────────────────
    if mat == MAT_GROUND:
        # Checkerboard: XOR of floor(hit_x) and floor(hit_z)
        # FPGA: just take the LSB of the integer part of hit_pos.x and hit_pos.z
        # i.e. bit 0 of hit_pos_x_integer XOR bit 0 of hit_pos_z_integer
        ck   = 0.10 if (int(np.floor(p[0])) + int(np.floor(p[2]))) & 1 else 0.88
        base = np.array([ck, ck * 0.97, ck * 0.93])

        sunL = np.array([1.0, 0.88, 0.72]) * diff * shad * 0.90  # sun tint
        amb  = np.array([0.15, 0.22, 0.42]) * 0.30               # sky ambient

        col  = base * (sunL + amb)

        # Fresnel-weighted sky reflection (Schlick approximation)
        # NoV = angle between view ray and surface normal
        # At grazing angles (NoV→0): nearly full reflection
        # At direct view (NoV→1):    very low reflection (4%)
        # FPGA: pow(x, 5) = x * x * x * x * x — just 4 multiplies!
        NoV  = mx0(-dot(rd, n))
        fres = 0.04 + 0.96 * (1.0 - NoV) ** 5
        col  = mix(col, sky_col(rfl), cl(fres * 0.5 + 0.06, 0.0, 1.0))

    # ── Sphere material (mat_id = 1) ────────────────────────────
    else:
        base = np.array([0.04, 0.12, 0.42])   # deep blue metallic

        sunL = np.array([1.0, 0.88, 0.72]) * diff * shad
        amb  = np.array([0.10, 0.16, 0.40]) * 0.45
        col  = base * (sunL + amb)

        # Blinn-Phong specular
        # H = halfway vector between sun and view (negated ray_dir = view dir)
        # FPGA: pow(x, 72) → LUT on 8-bit quantized dot(n, H)
        H    = nor(SUN - rd)
        spec = mx0(dot(n, H)) ** 7 # Metallic environment reflection
        NoV  = mx0(-dot(rd, n))
        fres = 0.05 + 0.95 * (1.0 - NoV) ** 4
        col  = mix(col, sky_col(rfl), cl(fres * 0.65, 0.0, 1.0))

    # ── Fog ─────────────────────────────────────────────────────
    # fog_amt = 1 - exp(-march_t * FOG_D)
    # FPGA: LUT_FOG[march_t_8bit] pre-computes this
    fog = 1.0 - np.exp(-t * FOG_D)
    col = mix(col, FOG_C, fog)

    # ── Gamma correction ────────────────────────────────────────
    # Convert linear light → sRGB display (gamma ≈ 2.0, approx as sqrt)
    # FPGA: LUT_GAMMA[256] — 256×8-bit ROM, one lookup per channel
    col = np.sqrt(np.clip(col, 0.0, 1.0))
    return col


# ================================================================
# RGB444 packing
# This is the final output stage of your shader unit.
#
# Input:  linear float RGB [0.0 .. 1.0] (after gamma)
# Output: 12-bit word  R[11:8] G[7:4] B[3:0]
#
# VHDL equivalent:
#   r4 := to_unsigned(to_integer(r_gamma * 15), 4);
#   g4 := to_unsigned(to_integer(g_gamma * 15), 4);
#   b4 := to_unsigned(to_integer(b_gamma * 15), 4);
#   rgb444 <= std_logic_vector(r4 & g4 & b4);
# ================================================================
def to_rgb444(r, g, b):
    r5 = int(cl(r, 0.0, 1.0) * 15.0 + 0.5)   # 5 bits: 0-31
    g6 = int(cl(g, 0.0, 1.0) * 15.0 + 0.5)   # 6 bits: 0-63
    b5 = int(cl(b, 0.0, 1.0) * 15.0 + 0.5)   # 5 bits: 0-31
    return (r5 << 11) | (g6 << 5) | b5        # pack into 16-bit word

def rgb444_to_rgb888(word): 
    """Inverse — useful for previewing RGB444 output."""
    r5 = (word >> 11) & 0x1F
    g6 = (word >>  5) & 0x3F
    b5 = (word >>  0) & 0x1F
    # Expand back: replicate upper bits into lower bits (standard expansion)
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g6 << 2) | (g6 >> 4)
    b8 = (b5 << 3) | (b5 >> 2)
    return r8, g8, b8


# ================================================================
# Render loop
# ================================================================
print(f"Rendering {W}×{H}  (this is pure Python — expect ~60-120s)")
print("Tip: reduce W and H at the top of the script for a faster test render.\n")

buf_rgb888 = np.zeros((H, W, 3), dtype=np.uint8)
buf_rgb444 = []   # flat list of 12-bit words, row-major

t0 = time.time()
for y in range(H):
    for x in range(W):
        rd   = gen_ray(x + 0.5, y + 0.5)
        col  = shade(CAM, rd)
        word = to_rgb444(col[0], col[1], col[2])
        r8, g8, b8 = rgb444_to_rgb888(word)

        buf_rgb888[y, x] = [r8, g8, b8]
        buf_rgb444.append(word)

    elapsed = time.time() - t0
    eta     = (elapsed / (y + 1)) * (H - y - 1)
    print(f"\r  Row {y+1:3d}/{H}  |  {elapsed:5.1f}s elapsed  |  ETA {eta:5.1f}s  ", end='', flush=True)

elapsed = time.time() - t0
print(f"\n\nRender complete in {elapsed:.1f}s")

if SAVE_PNG:
    fname = "scene.png"
    Image.fromarray(buf_rgb888, 'RGB').save(fname)
    print(f"Saved {fname}  (RGB888 preview, gamma-corrected)")

if SAVE_BIN:
    fname = "./software/out/scene_rgb565.bin"
    with open(fname, 'wb') as f:
        for word in buf_rgb444:
            f.write(struct.pack('>H', word))   # big-endian 16-bit, row-major
    print(f"Saved {fname}  ({W*H*2} bytes, raw RGB444 for FPGA sim)")
    print(f"  Format: R[11:8] G[7:4] B[3:0], big-endian, row-major")
    print(f"  Load in VHDL sim: read 1 byte at a time, {W} words per line")