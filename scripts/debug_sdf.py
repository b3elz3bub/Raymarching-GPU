"""
Debug: Simulate VHDL raymarch fixed-point SDF pipeline. No dependencies.
"""
import math

def quantize(val, int_bits, frac_bits):
    scale = 2**frac_bits
    total_bits = int_bits + frac_bits
    max_val = (2**(total_bits-1) - 1) / scale
    min_val = -(2**(total_bits-1)) / scale
    q = math.floor(val * scale) / scale
    rang = 2**int_bits
    while q > max_val: q -= rang
    while q < min_val: q += rang
    return q

def q_pos(v): return quantize(v, 6, 12)
def q_sos(v): return quantize(v, 12, 6)
def q_inv(v): return quantize(v, 4, 14)

SPHERE_CX, SPHERE_CY, SPHERE_CZ, SPHERE_R = 0.0, 0.5, 3.0, 0.5
HIT_DIST = q_pos(0.005)
MAX_DIST = q_pos(20.0)
FAR_SPHERE = q_pos(20.0)
SOS_LO = q_sos(7.0)
SOS_HI = q_sos(448.0)

def hw_invsqrt(x_sos):
    if x_sos <= 0: return q_inv(0.0)
    x_q36 = quantize(x_sos, 3, 6)
    if x_q36 <= 0: return q_inv(0.0)
    result = 1.0 / math.sqrt(x_q36)
    result_q49 = quantize(result, 4, 9)
    return q_inv(result_q49)

def vhdl_sum_of_sq(px, py, pz):
    dx = q_pos(px - SPHERE_CX)
    dy = q_pos(py - SPHERE_CY)
    dz = q_pos(pz - SPHERE_CZ)
    return q_sos(dx*dx + dy*dy + dz*dz)

def compute_d_sphere(sum_sq):
    if sum_sq > SOS_HI:
        return FAR_SPHERE, "FAR"
    elif sum_sq > SOS_LO:
        shifted = q_sos(sum_sq / 64.0)
        v_inv_raw = hw_invsqrt(shifted)
        v_inv = q_inv(v_inv_raw / 8.0)
        d = q_pos(sum_sq * v_inv - SPHERE_R)
        return d, "SCALED"
    else:
        v_inv = hw_invsqrt(sum_sq)
        d = q_pos(sum_sq * v_inv - SPHERE_R)
        return d, "DIRECT"

def true_sdf(px, py, pz):
    dx = px - SPHERE_CX; dy = py - SPHERE_CY; dz = pz - SPHERE_CZ
    return math.sqrt(dx*dx + dy*dy + dz*dz) - SPHERE_R

def simulate_ray(ox, oy, oz, dx, dy, dz, label=""):
    mag = math.sqrt(dx*dx+dy*dy+dz*dz)
    dx, dy, dz = dx/mag, dy/mag, dz/mag
    print(f"\n{'='*80}")
    print(f"Ray: o=({ox},{oy},{oz}) d=({dx:.4f},{dy:.4f},{dz:.4f})  {label}")
    print(f"{'Step':>4} {'t':>7} {'cx':>7} {'cy':>7} {'cz':>7} "
          f"{'ssq':>7} {'d_sph':>8} {'d_pln':>7} {'d_min':>8} "
          f"{'TRUE':>8} {'ERR':>8} {'path':>6}")

    cx, cy, cz = q_pos(ox), q_pos(oy), q_pos(oz)
    t = q_pos(0.0)

    for step in range(64):
        sq = vhdl_sum_of_sq(cx, cy, cz)
        dp = q_pos(cy)  # sdf_plane
        ds, path = compute_d_sphere(sq)
        d_min = ds if ds < dp else dp
        obj = "sph" if ds < dp else "pln"
        td = true_sdf(cx, cy, cz)
        err = ds - td

        print(f"{step:4d} {t:7.3f} {cx:7.3f} {cy:7.3f} {cz:7.3f} "
              f"{sq:7.3f} {ds:8.4f} {dp:7.4f} {d_min:8.4f} "
              f"{td:8.4f} {err:+8.4f} {path:>6}")

        if d_min < HIT_DIST:
            print(f"  >>> HIT {obj} at t={t:.4f}")
            return
        if t > MAX_DIST or t < 0:
            print(f"  >>> MISS (t exceeded)")
            return
        cx = q_pos(cx + q_pos(dx * d_min))
        cy = q_pos(cy + q_pos(dy * d_min))
        cz = q_pos(cz + q_pos(dz * d_min))
        t  = q_pos(t + d_min)

    print(f"  >>> MISS (max steps)")

# ── SCAN: SDF values vs true along z-axis ─────────────────────
print("="*80)
print("SCAN: d_sphere(VHDL) vs d_sphere(true) along z from sphere center")
print(f"{'dist':>6} {'ssq':>8} {'vhdl':>8} {'true':>8} {'err':>8} {'path':>6}")
for i in range(1, 100):
    dist = i * 0.05
    pz = SPHERE_CZ + dist
    sq = vhdl_sum_of_sq(0.0, 0.5, pz)
    ds, path = compute_d_sphere(sq)
    td = true_sdf(0.0, 0.5, pz)
    err = ds - td
    flag = " <<<" if abs(err) > 0.1 else ""
    print(f"{dist:6.2f} {sq:8.4f} {ds:8.4f} {td:8.4f} {err:+8.4f} {path:>6}{flag}")

# ── Ray tests ─────────────────────────────────────────────────
# Test from default camera
simulate_ray(0, 2.5, -20, 0, -0.0869, 0.9962, "far camera, toward sphere")
# Test from close camera
simulate_ray(0, 2.5, 0, 0, -0.5547, 0.8321, "close camera, toward sphere")
# Test ray that should MISS sphere but passes nearby
simulate_ray(0, 0.5, 0, 0.03, 0, 1.0, "near-miss ray")
