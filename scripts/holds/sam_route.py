import cv2
import numpy as np
import sys

img = cv2.imread(sys.argv[1])
target = sys.argv[2] if len(sys.argv) > 2 else "yellow"
HUE = {"yellow": (18, 32), "green": (36, 85), "blue": (90, 130), "purple": (130, 165), "red": (0, 10)}
lo, hi = HUE[target]

holds = np.load("sam_holds.npy")
hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)

# drop composite masks: SAM sometimes emits a merged region spanning several
# holds; if a mask is mostly covered by smaller masks, its parts already
# represent it and its blended colour only misleads classification
small_masks = [m[::4, ::4] > 0 for m in holds]
order = np.argsort([s.sum() for s in small_masks])
covered = [np.zeros_like(small_masks[0])] 
keep = np.ones(len(holds), bool)
acc = np.zeros_like(small_masks[0])
for idx in order:
    s = small_masks[idx]
    if (s & acc).sum() > 0.7 * s.sum():
        keep[idx] = False
    else:
        acc |= s
holds = holds[keep]
print(f"{keep.sum()} masks after composite dedup")

stats = []
for m in holds:
    # colour from the eroded core: rim pixels are wall-contaminated and
    # dilute small chips down to near-neutral
    core = cv2.erode(m, np.ones((5, 5), np.uint8)) > 0
    if core.sum() < 20:
        core = m > 0
    hh = np.median(hsv[:, :, 0][core])
    ss = np.median(hsv[:, :, 1][core])
    vv = np.median(hsv[:, :, 2][core])
    L, a, b = (np.median(lab[:, :, c][core]) for c in range(3))
    mag = np.hypot(a - 128, b - 128)
    ang = np.degrees(np.arctan2(b - 128, a - 128))
    stats.append((m > 0, hh, ss, vv, L, mag, ang))

# confident seeds under strict thresholds
seed_angs = [ang for _, hh, ss, vv, L, mag, ang in stats if lo <= hh <= hi and ss > 140 and vv > 90]
seed = np.median(seed_angs)
print(f"{len(seed_angs)} seeds, chroma angle {seed:.0f} deg")

route = np.zeros(img.shape[:2], np.uint8)
picked = 0
yellow_masks = []
for sel, hh, ss, vv, L, mag, ang in stats:
    d = ang - seed
    if mag < 22 and L > 170:   # warm-lit white: yellow angle, weak chroma
        continue
    if mag > 15 and -10 <= d <= 18 and L > 40:
        # greener shades must be bright: lime foot chips are light (L>85),
        # olive holds are dark — that is the only thing separating them
        if d > 8 and L < 85:
            continue
        route[sel] = 255
        yellow_masks.append(sel.astype(np.uint8))
        picked += 1
cv2.imwrite("sam_route.png", cv2.bitwise_and(img, img, mask=route))
np.save("sam_yellow_masks.npy", np.stack(yellow_masks) if yellow_masks else np.zeros((0,)+img.shape[:2], np.uint8))
print(f"{target}: {picked} holds")
