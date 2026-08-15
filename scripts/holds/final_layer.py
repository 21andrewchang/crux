import cv2
import numpy as np

CLASSIC_YELLOW = (10, 214, 255)  # BGR of #FFD60A

# sources: hybrid yellow masks (smooth SAM shapes) + classical-only holds
# (bottom foot chips the hybrid misses)
hyb = list(np.load("hybrid_yellow_masks.npy"))
h, w = hyb[0].shape if hyb else cv2.imread("route_mask.png", cv2.IMREAD_GRAYSCALE).shape
hyb_union = np.zeros((h, w), np.uint8)
for m in hyb:
    hyb_union |= m

sources = hyb[:]
union = hyb_union.copy()

# full-grid SAM yellows: everything it found that the hybrid missed
for m in np.load("sam_yellow_masks.npy"):
    if (union & m).sum() < 0.3 * m.sum():
        sources.append(m)
        union |= m

# classical route components as the last resort
route_a = cv2.imread("route_mask.png", cv2.IMREAD_GRAYSCALE)
n, labels = cv2.connectedComponents((route_a > 0).astype(np.uint8), connectivity=4)
for i in range(1, n):
    comp = (labels == i).astype(np.uint8)
    if comp.sum() < 40:
        continue
    if (union & comp).sum() < 0.3 * comp.sum():
        sources.append(comp)
        union |= comp
print(f"{len(sources)} holds to redraw ({len(hyb)} hybrid + {len(sources)-len(hyb)} recovered)")


S = 3  # supersample for clean anti-aliased edges
shape_bin = np.zeros((h * S, w * S), np.uint8)
drawn = 0
for m in sources:
    c = max(cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)[0], key=cv2.contourArea)
    area = cv2.contourArea(c)
    if area < 40:
        continue
    if area < 400:
        # tiny chips become clean circles
        (cx, cy), r = cv2.minEnclosingCircle(c)
        cv2.circle(shape_bin, (int(cx * S), int(cy * S)), max(4, int(r * 0.9 * S)), 255, cv2.FILLED)
        drawn += 1
        continue
    # vector trace: simplify faithfully (straight edges stay straight,
    # arcs keep their vertices), then Chaikin corner-cutting rounds the
    # corners without inventing curvature anywhere else
    eps = 0.012 * cv2.arcLength(c, True)
    pts = cv2.approxPolyDP(c, eps, True).reshape(-1, 2).astype(np.float64)
    for _ in range(4):
        nxt = np.empty((len(pts) * 2, 2))
        q = np.roll(pts, -1, 0)
        nxt[0::2] = 0.75 * pts + 0.25 * q
        nxt[1::2] = 0.25 * pts + 0.75 * q
        pts = nxt
    poly = np.round(pts * S).astype(np.int32)
    cv2.fillPoly(shape_bin, [poly], 255, lineType=cv2.LINE_AA)
    drawn += 1

canvas = np.zeros((h * S, w * S, 3), np.uint8)
canvas[shape_bin > 0] = CLASSIC_YELLOW

final = cv2.resize(canvas, (w, h), interpolation=cv2.INTER_AREA)
cv2.imwrite("final_route.png", final)
print(f"redrew {drawn} holds")
