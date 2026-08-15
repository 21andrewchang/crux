import cv2
import numpy as np
import torch
import sys
from segment_anything import sam_model_registry, SamAutomaticMaskGenerator
from segment_anything.utils.transforms import ResizeLongestSide

# MPS has no float64; SAM's coord transform casts to float64 internally
_orig_apply_coords = ResizeLongestSide.apply_coords
ResizeLongestSide.apply_coords = lambda self, coords, orig: _orig_apply_coords(self, coords, orig).astype(np.float32)

img = cv2.imread(sys.argv[1])
h, w = img.shape[:2]
# half res keeps auto mask generation tractable; holds are plenty big
half = cv2.resize(img, (w // 2, h // 2), interpolation=cv2.INTER_AREA)
rgb = cv2.cvtColor(half, cv2.COLOR_BGR2RGB)

device = "mps" if torch.backends.mps.is_available() else "cpu"
sam = sam_model_registry["vit_b"](checkpoint="sam_vit_b.pth").to(device)
gen = SamAutomaticMaskGenerator(
    sam,
    points_per_side=64,
    pred_iou_thresh=0.8,
    stability_score_thresh=0.87,
    min_mask_region_area=25,
)
masks = gen.generate(rgb)
print(f"SAM produced {len(masks)} masks")

hh, hw = half.shape[:2]
holds = []
for m in masks:
    a = m["area"]
    # hold-sized: not wall panels, not specks
    if not (35 < a < 0.02 * hh * hw):
        continue
    seg = m["segmentation"].astype(np.uint8)
    c = max(cv2.findContours(seg, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)[0], key=cv2.contourArea)
    hull = cv2.contourArea(cv2.convexHull(c))
    if hull == 0 or a / hull < 0.6:
        continue
    holds.append(seg)
print(f"{len(holds)} hold-sized compact masks")

mask_all = np.zeros((hh, hw), np.uint8)
for s in holds:
    mask_all |= s * 255
mask_full = cv2.resize(mask_all, (w, h), interpolation=cv2.INTER_NEAREST)
cv2.imwrite("sam_mask.png", mask_full)
cv2.imwrite("sam_layer.png", cv2.bitwise_and(img, img, mask=mask_full))

# save per-hold masks at full res for the color pass
np.save("sam_holds.npy", np.stack([cv2.resize(s, (w, h), interpolation=cv2.INTER_NEAREST) for s in holds]) if holds else np.zeros((0, h, w), np.uint8))
