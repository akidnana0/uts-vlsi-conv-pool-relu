import os

CONV_BITS  = 20   #lebar hasil konvolusi (signed)
OUT_BITS   = 8    #lebar output akhir (unsigned)
SHIFT      = 8    #requantization
OUT_DIR    = "tb/vectors"
REPORT_TXT = "results/golden_output.txt"

image = [
    [170, 249,  18, 218,   4, 172, 206,  45, 191,  76, 195,   6, 103,  89, 209, 163],
    [234, 241, 143,  93, 229, 230, 158, 119, 115, 156, 111,  20,  95,  31, 217,  94],
    [ 26,  54, 185, 164, 199, 220, 219,  90,  40, 107, 192, 212,  92, 103,  95, 202],
    [ 92,  91,  85, 180, 168, 129, 183, 231,  23,  32, 161, 184, 206,   4, 103,  45],
    [ 79, 179, 195, 219, 162, 231,  28, 167,  13,  29,  53,  25, 246, 145,  93,  76],
    [ 49, 148, 105,  42, 178, 213, 138, 247, 113, 150,  91, 186, 212,  76, 123, 235],
    [ 24, 221,  81,  72, 212, 109, 200, 162,   0,  41, 171, 154, 251,  12, 179, 192],
    [ 97,  80,  54,  30, 214,  28, 225, 131,  53, 201,   0, 165,  36, 223, 109, 211],
    [ 20,  73, 245, 167,  66,  17, 201, 114,  27,  94, 203, 117, 182, 105, 188,  86],
    [ 13, 219,  64,  40,  42, 103,  36,  71, 151, 151, 104,  37, 149, 246, 240,  57],
    [218, 119, 146, 218, 193, 238, 155, 134, 118,  34, 115,  23, 184,  64,  80, 110],
    [ 26,  51,  82,  69, 132,  52, 198, 169, 115, 127, 142, 212, 139, 131,  73,   3],
    [ 65, 222,  63, 119, 129, 151, 156, 114, 187, 150, 158, 253,  45, 125, 124,  93],
    [ 88, 199,  75,  42, 189, 147,   5,  50, 162, 214,  64, 122,  53,  33,  73, 152],
    [233, 217, 153,  83, 216, 174, 112, 111,   6, 184, 204, 169,  65,  62, 204,  76],
    [156, 215, 248, 246, 127,  75, 156,  53,  91,  50, 108, 239, 185,  92, 231, 223],
]

kernels = [
    [[ -28, -111,  125],
     [ 116,    4,   -3],
     [ -90,   76,    7]],
    [[-100,  -38,    7],
     [ -53,  -45,  -47],
     [  27,  -64,  122]],
    [[ 105,  -76,  115],
     [   2,  -40,  -40],
     [  59,   60,   16]],
]


def conv2d(x, k):
    n_out = len(x) - len(k) + 1
    y = []
    for i in range(n_out):
        row = []
        for j in range(n_out):
            acc = 0
            for m in range(len(k)):
                for n in range(len(k)):
                    acc += x[i + m][j + n] * k[m][n]
            row.append(acc)
        y.append(row)
    return y


def maxpool2x2(x):
    n_out = len(x) // 2
    y = []
    for i in range(n_out):
        row = []
        for j in range(n_out):
            row.append(max(x[2*i][2*j],     x[2*i][2*j + 1],
                           x[2*i + 1][2*j], x[2*i + 1][2*j + 1]))
        y.append(row)
    return y


def relu(x):
    return [[v if v >= 0 else 0 for v in row] for row in x]


def requantize(x):
    max_val = (1 << OUT_BITS) - 1
    return [[min(v >> SHIFT, max_val) for v in row] for row in x]

def to_hex(val, bits):
    digits = (bits + 3) // 4
    return format(val & ((1 << bits) - 1), "0" + str(digits) + "x")


def write_hex(filename, matrices, bits):
    with open(filename, "w") as f:
        for mat in matrices:
            for row in mat:
                for v in row:
                    f.write(to_hex(v, bits) + "\n")


def format_matrix(name, mat):
    width = max(len(str(v)) for row in mat for v in row)
    lines = [name]
    for row in mat:
        lines.append("  " + " ".join(str(v).rjust(width) for v in row))
    return "\n".join(lines)

conv_out  = [conv2d(image, k) for k in kernels]
pool_out  = [maxpool2x2(c) for c in conv_out]
relu_out  = [relu(p) for p in pool_out]
final_out = [requantize(r) for r in relu_out]

os.makedirs(OUT_DIR, exist_ok=True)
write_hex(OUT_DIR + "/image.hex",  [image],   8)
write_hex(OUT_DIR + "/kernel.hex", kernels,   8)
write_hex(OUT_DIR + "/conv.hex",   conv_out,  CONV_BITS)
write_hex(OUT_DIR + "/pool.hex",   pool_out,  CONV_BITS)
write_hex(OUT_DIR + "/relu.hex",   relu_out,  CONV_BITS)
write_hex(OUT_DIR + "/output.hex", final_out, OUT_BITS)

os.makedirs("results", exist_ok=True)
with open(REPORT_TXT, "w") as f:
    for c in range(len(kernels)):
        f.write(format_matrix(f"=== Conv channel {c+1} (14x14) ===", conv_out[c]) + "\n\n")
        f.write(format_matrix(f"=== Maxpool channel {c+1} (7x7) ===", pool_out[c]) + "\n\n")
        f.write(format_matrix(f"=== ReLU channel {c+1} (7x7) ===", relu_out[c]) + "\n\n")
        f.write(format_matrix(f"=== Output 8-bit channel {c+1} (7x7) ===", final_out[c]) + "\n\n")

for c in range(len(kernels)):
    flat = [v for row in conv_out[c] for v in row]
    print(f"Channel {c+1}: conv min {min(flat)}, max {max(flat)}")
    print(format_matrix(f"Output 8-bit channel {c+1}:", final_out[c]))
    print()
print("Vektor uji ditulis ke", OUT_DIR, "| matriks lengkap di", REPORT_TXT)