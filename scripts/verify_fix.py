"""Verify fix: SOS_LO = 3.9 should eliminate the bubble."""
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

SPHERE_R = 0.5
SOS_LO = q_sos(3.9)   # FIXED!
SOS_HI = q_sos(448.0)
FAR_SPHERE = q_pos(20.0)

def hw_invsqrt(x_sos):
    x_q36 = quantize(x_sos, 3, 6)
    if x_q36 <= 0: return q_inv(0.0)
    result = 1.0 / math.sqrt(x_q36)
    result_q49 = quantize(result, 4, 9)
    return q_inv(result_q49)

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

def true_sdf(dist): return dist - SPHERE_R

print(f"SOS_LO = {SOS_LO}")
print(f"{'dist':>6} {'ssq':>8} {'vhdl':>8} {'true':>8} {'err':>8} {'path':>6}")
all_ok = True
for i in range(1, 100):
    dist = i * 0.05
    ssq = q_sos(dist * dist)
    ds, path = compute_d_sphere(ssq)
    td = true_sdf(dist)
    err = ds - td
    flag = " <<<BUG" if abs(err) > 0.2 else ""
    if abs(err) > 0.2: all_ok = False
    if i <= 40 or abs(err) > 0.05:
        print(f"{dist:6.2f} {ssq:8.4f} {ds:8.4f} {td:8.4f} {err:+8.4f} {path:>6}{flag}")

print(f"\n{'='*60}")
print(f"RESULT: {'ALL CLEAR - no bubble!' if all_ok else 'STILL HAS ISSUES'}")
