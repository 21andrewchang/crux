# Hold detection

Prototype scripts rescued from the original session scratchpad (results in the
"Yellow Hold Mask" artifact):

- `pipeline.py` — classical stage: mean-shift + per-channel Canny edges,
  color-anomaly candidates, edges as hard walls, seeded per-hold color pass.
  Emits `hold_points.npy` (SAM prompts) and `hold_labels.npy` (kept masks).
- `hybrid.py` — SAM 1 ViT-B prompted only at the classical candidate points,
  classical mask as fallback for chips SAM declines; dedup + color pass.
- `final_layer.py` — merges hybrid yellows + full-grid SAM + classical leftovers,
  vector-traces each hold (approxPolyDP + Chaikin), flat classic yellow on black.
- `sam_holds.py` / `sam_route.py` — full-grid SAM reference (not used on device).
- `test_wall.jpg` — the reference photo (yellow route, 25 classical / 27 hybrid /
  29 final holds).

## App port

`Climb/Support/HoldDetector.mm` runs classical + hybrid + final render on device,
with SAM 2.1 Small Core ML (`Climb/ML/*.mlpackage`, from
`huggingface.co/apple/coreml-sam2.1-small`) replacing SAM 1. Differences from the
prototype, validated against the reference run with a Mac harness (Core ML SAM
picks finished by the prototype's own Python downstream):

- SAM input is the SAM2-native 1024×1024 squash (letterboxing scored worse).
- Score floor 0.5 instead of 0.7 — SAM 2.1 Small predicts lower IoU on small
  holds than SAM 1 ViT-B; at 0.7 most holds fell back to jagged classical masks.
- Picked mask logits are upscaled to working resolution before thresholding —
  binarizing at 256×256 first fattens small chips and dilutes their color.
- Color medians sample the mask ∩ chroma-anomaly map (eroded core as fallback):
  slightly-fat SAM2 masks otherwise pull chip chroma below the mag>15 gate.
- Olive-rejection cutoff L<80 (was 85): SAM2 masks read a touch darker.
- No full-grid SAM pass (too slow on device); classical route components recover
  what the prompted pass misses, as in `final_layer.py`.

Harness result on `test_wall.jpg`: 24 yellow / 25 rendered vs the reference's
27 / 29 — the misses are a couple of dim bottom chips and one mid hold, with no
junk additions.
