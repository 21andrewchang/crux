import cv2
import numpy as np
import sys

src_path = sys.argv[1]
img = cv2.imread(src_path)
h, w = img.shape[:2]

# --- layer 1: monochrome ---
gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
cv2.imwrite("mono.png", gray)

# --- layer 2: edge detection ---
# Color edges for hold outlines: a yellow hold on teal wall has no luminance
# edge but a big chroma edge, so Canny runs per Lab channel and ORs.
# Mean-shift at half res posterizes the wall into flat regions first —
# chalk/texture noise flattens out, hold boundaries survive.
half = cv2.pyrMeanShiftFiltering(cv2.resize(img, (w // 2, h // 2), interpolation=cv2.INTER_AREA), sp=12, sr=24)
lab8 = cv2.cvtColor(half, cv2.COLOR_BGR2LAB)
edges = np.zeros(half.shape[:2], np.uint8)
for c in range(3):
    edges = cv2.bitwise_or(edges, cv2.Canny(lab8[:, :, c], 30, 90))
edges = cv2.resize(edges, (w, h), interpolation=cv2.INTER_NEAREST)
cv2.imwrite("edges.png", edges)
edge_near = cv2.dilate(edges, np.ones((5, 5), np.uint8))  # tolerance band

# Clutter map stays on luminance edges: wall texture is chroma-noisy but
# luminance-quiet, while ceiling beams and the climber are busy in luminance.
smooth = cv2.bilateralFilter(gray, 9, 60, 60)
v = np.median(smooth)
edges_mono = cv2.Canny(smooth, int(0.66 * v), int(1.6 * v))
density = cv2.blur((edges_mono > 0).astype(np.float32), (121, 121))

# --- layer 3: hold candidates = local color anomalies vs the wall ---
lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.int16)
small = cv2.resize(lab.astype(np.uint8), None, fx=0.25, fy=0.25, interpolation=cv2.INTER_AREA)
bg_small = np.stack([cv2.medianBlur(small[:, :, c], 61) for c in range(3)], axis=2)
bg = cv2.resize(bg_small, (w, h), interpolation=cv2.INTER_LINEAR).astype(np.int16)
d = (lab - bg).astype(np.float32)
dist = np.sqrt((0.35 * d[:, :, 0]) ** 2 + d[:, :, 1] ** 2 + d[:, :, 2] ** 2)
cand = (dist > 16).astype(np.uint8) * 255
cand = cv2.morphologyEx(cand, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
cand = cv2.morphologyEx(cand, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13)))

# Second candidate source: closed contours in the edge map itself, so holds
# whose color hugs the wall (weak chroma anomaly) still get proposed.
closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
cnts, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
edge_cand = np.zeros((h, w), np.uint8)
for c in cnts:
    a = cv2.contourArea(c)
    if 30 < a < 0.04 * h * w:
        cv2.drawContours(edge_cand, [c], -1, 255, cv2.FILLED)
edge_cand = cv2.morphologyEx(edge_cand, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
cand = cv2.bitwise_or(cand, edge_cand)

# --- layer 4: keep only blobs that behave like holds ---
# Cut candidate blobs along real edges before labeling: two touching holds
# merged by morphology get separated again by the boundary the edge map drew
# between them. Kept blobs are re-grown to reclaim the cut pixels.
cut = cv2.bitwise_and(cand, cv2.bitwise_not(edges))

chroma_cand = cv2.morphologyEx((dist > 16).astype(np.uint8) * 255, cv2.MORPH_OPEN,
                               cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
n, labels, stats, cents = cv2.connectedComponentsWithStats(cut, connectivity=4)
clean = np.zeros_like(cand)
hold_masks = []
kept = 0
prompt_pts = []
for i in range(1, n):
    area = stats[i, cv2.CC_STAT_AREA]
    if not (40 < area < 0.04 * h * w):
        continue
    # every size-gated candidate becomes a SAM prompt, even ones the shape
    # tests below reject — the hybrid filters junk better than we can here
    prompt_pts.append((cents[i][0], cents[i][1]))
    blob = (labels == i).astype(np.uint8)
    c = max(cv2.findContours(blob, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)[0], key=cv2.contourArea)
    hull_area = cv2.contourArea(cv2.convexHull(c))
    solidity = area / hull_area if hull_area > 0 else 0
    (_, (rw, rh), _) = cv2.minAreaRect(c)
    elong = max(rw, rh) / max(min(rw, rh), 1)

    # edge support: how much of the blob outline lies on a real image edge
    outline = c.reshape(-1, 2)
    on_edge = np.mean(edge_near[outline[:, 1], outline[:, 0]] > 0)
    # clutter: edge density around the blob centre
    cx, cy = int(cents[i][0]), int(cents[i][1])
    clutter = density[cy, cx]

    # edge-only candidates (no chroma anomaly backing) face stricter tests
    chroma_backed = cv2.countNonZero(cv2.bitwise_and(blob * 255, chroma_cand)) > 0.3 * area
    if chroma_backed:
        ok = solidity > 0.5 and elong < 5 and on_edge > 0.30 and clutter < 0.12
    else:
        ok = solidity > 0.6 and elong < 4 and on_edge > 0.55 and clutter < 0.08
    if ok:
        # regrow inside the original candidate, but never across an edge
        # line — edges are walls, so touching holds stay separate
        grown = cv2.bitwise_and(cv2.dilate(blob * 255, np.ones((5, 5), np.uint8)),
                                cv2.bitwise_and(cand, cv2.bitwise_not(edges)))
        clean = cv2.bitwise_or(clean, grown)
        hold_masks.append((len(prompt_pts) - 1, grown))
        kept += 1

cv2.imwrite("holds_mask.png", clean)
cv2.imwrite("holds_layer.png", cv2.bitwise_and(img, img, mask=clean))
print(f"kept {kept} hold candidates")

# prompts (all size-gated candidates) + label map of kept holds, keyed by
# prompt index so the hybrid can fall back to the classical mask
label_map = np.zeros((h, w), np.uint16)
for pidx, hm in hold_masks:
    label_map[hm > 0] = pidx + 1
np.save("hold_points.npy", np.array(prompt_pts))
np.save("hold_labels.npy", label_map)

# --- layer 5: color classification per whole hold ---
# Iterates the split holds directly (not re-labeled pixels), so two touching
# holds of different colors stay separate decisions.
target = sys.argv[2] if len(sys.argv) > 2 else "yellow"
HUE = {"yellow": (18, 32), "green": (36, 85), "blue": (90, 130), "purple": (130, 165), "red": (0, 10)}
lo, hi = HUE[target]
hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
lab8 = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)

# colour from the eroded core: rim pixels are wall-contaminated and dilute
# small chips toward neutral
cstats = []
for _, hm in hold_masks:
    core = cv2.erode(hm, np.ones((5, 5), np.uint8)) > 0
    if core.sum() < 20:
        core = hm > 0
    hh, ss, vv = (np.median(hsv[:, :, c][core]) for c in range(3))
    L, a, b = (np.median(lab8[:, :, c][core]) for c in range(3))
    cstats.append((hm > 0, hh, ss, vv, L, np.hypot(a - 128, b - 128),
                   np.degrees(np.arctan2(b - 128, a - 128))))

seed_angs = [ang for _, hh, ss, vv, L, mag, ang in cstats if lo <= hh <= hi and ss > 140 and vv > 90]
seed = np.median(seed_angs)
route = np.zeros_like(clean)
picked = 0
for m, hh, ss, vv, L, mag, ang in cstats:
    if mag < 22 and L > 170:      # warm-lit white: yellow angle, weak chroma
        continue
    d = ang - seed
    if mag > 15 and -10 <= d <= 18 and L > 40:
        if d > 8 and L < 85:      # lime chips are light; olive holds are dark
            continue
        route[m] = 255
        picked += 1
cv2.imwrite("route_mask.png", route)
cv2.imwrite("route_layer.png", cv2.bitwise_and(img, img, mask=route))
print(f"{target}: {picked} holds")
