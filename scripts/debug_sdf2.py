"""Focused debug: trace the invsqrt pipeline for sum_sq values 1.0 to 7.0"""
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
def q_q36(v): return quantize(v, 3, 6)  # what invsqrt_in(2 downto -6) sees
def q_q49(v): return quantize(v, 4, 9)  # what hw_out(3 downto -9) keeps

print(f"{'ssq':>6} {'q36':>8} {'1/sq(q36)':>10} {'q49':>8} {'q_inv':>8} "
      f"{'ssq*inv':>8} {'d_sph':>8} {'true_d':>8} {'err':>8}")
for i in range(10, 80):
    ssq = i * 0.1
    ssq_q = q_sos(ssq)
    
    # What the hw input mapping does
    x_q36 = q_q36(ssq_q)  # invsqrt_in(2 downto -6)
    
    if x_q36 <= 0:
        inv_true = 0
        inv_q49 = 0
        inv_final = 0
    else:
        inv_true = 1.0 / math.sqrt(x_q36)
        inv_q49 = q_q49(inv_true)
        inv_final = q_inv(inv_q49)
    
    product = ssq_q * inv_final
    product_q = q_pos(product)
    d_sph = q_pos(product_q - 0.5)
    true_d = math.sqrt(ssq) - 0.5
    err = d_sph - true_d
    
    flag = " <<<" if abs(err) > 0.1 else ""
    print(f"{ssq:6.1f} {x_q36:8.4f} {inv_true:10.4f} {inv_q49:8.4f} {inv_final:8.6f} "
          f"{product_q:8.4f} {d_sph:8.4f} {true_d:8.4f} {err:+8.4f}{flag}")

print("\n--- Checking Q3.6 quantization of key values ---")
for v in [3.9, 3.95, 4.0, 4.05, 4.5, 5.0, 6.0, 7.0]:
    q = q_q36(v)
    print(f"  q_q36({v}) = {q}  (3 int bits means: max = {2**2 - 2**-6:.4f}, "
          f"bit2_set={v >= 4.0})")

print("\n--- The issue: Q3.6 can only represent 0 to 3.984375 ---")
print("   Values >= 4.0 OVERFLOW and wrap to negative range!")
print(f"   q_q36(4.0) = {q_q36(4.0)}")
print(f"   q_q36(5.0) = {q_q36(5.0)}")
print(f"   q_q36(6.0) = {q_q36(6.0)}")
print(f"   q_q36(7.0) = {q_q36(7.0)}")
