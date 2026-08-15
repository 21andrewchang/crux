import cv2
import numpy as np
import torch
import sys
from segment_anything import sam_model_registry, SamPredictor
from segment_anything.utils.transforms import ResizeLongestSide

# MPS has no float64; SAM's coord transform casts to float64 internally
_orig = ResizeLongestSide.apply_coords
ResizeLongestSide.apply_coords = lambda self, c, o: _orig(self, c, o).astype(np.float32)

img = cv2.imread(sys.argv[1])
target = sys.argv[2] if len(sys.argv) > 2 else "yellow"
h, w = img.shape[:2]

# candidate points from the classical layer (cheap, color+edge driven)
points = np.load("hold_points.npy")
print(f"{len(points)} prompt points from classical layer")

half = cv2.resize(img, (w // 2, h // 2), interpolation=cv2.INTER_AREA)
device = "mps" if torch.backends.mps.is_available() else "cpu"
sam = sam_model_registry["vit_b"](checkpoint="sam_vit_b.pth").to(device)
pred = SamPredictor(sam)
pred.set_image(cv2.cvtColor(half, cv2.COLOR_BGR2RGB))

hh, hw = half.shape[:2]
label_map = np.load("hold_labels.npy")
labels_half = cv2.resize(label_map, (hw, hh), interpolation=cv2.INTER_NEAREST)
masks = []
fallbacks = 0
for pi, (x, y) in enumerate(points / 2.0):
    ms, scores, _ = pred.predict(point_coords=np.array([[x, y]], dtype=np.float32),
                                 point_labels=np.array([1]), multimask_output=True)
    # smallest mask above a score floor: point prompts often offer
    # hold / hold+wall-panel / whole-wall — we want the hold
    order = np.argsort([m.sum() for m in ms])
    pick = None
    for i in order:
        if scores[i] > 0.7 and 30 < ms[i].sum() < 0.02 * hh * hw:
            pick = ms[i]
            break
    if pick is None:
        # SAM declined (usually a tiny chip) — keep the classical mask
        pick = labels_half == pi + 1
        fallbacks += 1
        if pick.sum() < 8:
            continue
    seg = pick.astype(np.uint8)
    c = max(cv2.findContours(seg, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)[0], key=cv2.contourArea)
    hull = cv2.contourArea(cv2.convexHull(c))
    if hull == 0 or seg.sum() / hull < 0.6:
        continue
    # fill interior holes (chalk cracks): keep only the outer contour
    filled = np.zeros_like(seg)
    cv2.drawContours(filled, [c], -1, 1, cv2.FILLED)
    masks.append(filled)

# dedup: two points on the same hold give near-identical masks
keep = []
for m in sorted(masks, key=lambda m: int(m.sum()), reverse=True):
    if all((m & k).sum() < 0.6 * max(m.sum(), k.sum()) for k in keep):
        keep.append(m)
print(f"{len(keep)} holds after dedup ({fallbacks} classical fallbacks)")

full = [cv2.resize(m, (w, h), interpolation=cv2.INTER_NEAREST) for m in keep]
layer = np.zeros((h, w), np.uint8)
for m in full:
    layer |= m * 255
cv2.imwrite("hybrid_layer.png", cv2.bitwise_and(img, img, mask=layer))

# seeded colour pass on eroded cores (same recipe as sam_route)
HUE = {"yellow": (18, 32), "green": (36, 85), "blue": (90, 130), "purple": (130, 165), "red": (0, 10)}
lo, hi = HUE[target]
hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
stats = []
for m in full:
    core = cv2.erode(m, np.ones((5, 5), np.uint8)) > 0
    if core.sum() < 20:
        core = m > 0
    hhue, ss, vv = (np.median(hsv[:, :, c][core]) for c in range(3))
    L, a, b = (np.median(lab[:, :, c][core]) for c in range(3))
    stats.append((m > 0, hhue, ss, vv, L, np.hypot(a - 128, b - 128),
                  np.degrees(np.arctan2(b - 128, a - 128))))
seed = np.median([ang for _, hhue, ss, vv, L, mag, ang in stats
                  if lo <= hhue <= hi and ss > 140 and vv > 90])
route = np.zeros((h, w), np.uint8)
picked = 0
yellow_masks = []
for m, hhue, ss, vv, L, mag, ang in stats:
    if mag < 22 and L > 170:
        continue
    d = ang - seed
    if mag > 15 and -10 <= d <= 18 and L > 40:
        if d > 8 and L < 85:
            continue
        route[m] = 255
        yellow_masks.append(m.astype(np.uint8))
        picked += 1
cv2.imwrite("hybrid_route.png", cv2.bitwise_and(img, img, mask=route))
np.save("hybrid_yellow_masks.npy", np.stack(yellow_masks) if yellow_masks else np.zeros((0, h, w), np.uint8))
print(f"{target}: {picked} holds")
