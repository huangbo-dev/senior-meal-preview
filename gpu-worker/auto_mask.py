"""Find the rice in a meal photo automatically (app-only; not part of the CE7454 research code).

Two public models do the work, so nobody has to paint the photo by hand:

  CLIPSeg (CIDAS/clipseg-rd64-refined)  a coarse "where is the rice" heat map from a text prompt
  SAM     (facebook/sam-vit-base)       a crisp outline of the region CLIPSeg points at

The thresholds below were set by eye on five photographs on 15 November 2026. That is a
development check, not an evaluation: the mask is a best guess and can be wrong.
"""

from __future__ import annotations

import os
import threading

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

VERSION = "automask-v1"
CLIPSEG_ID = "CIDAS/clipseg-rd64-refined"
SAM_ID = "facebook/sam-vit-base"
RICE_PROMPTS = ("white rice", "steamed rice")

# Below this CLIPSeg peak the photo is treated as having no visible rice.
MIN_PEAK = 0.45
# Share of the photo a rice mask may cover; outside this the answer is not trusted.
MIN_COVERAGE = 0.005
MAX_COVERAGE = 0.6
# SAM must broadly agree with the CLIPSeg region (intersection over union).
MIN_AGREEMENT = 0.35

_LOCK = threading.Lock()
_MODELS = None


class RiceNotFound(Exception):
    """No region of the photo could be confidently identified as rice."""


def is_available() -> bool:
    """True when both models can be loaded from the local cache (never downloads)."""
    try:
        from huggingface_hub import try_to_load_from_cache

        return all(
            isinstance(try_to_load_from_cache(repo, "config.json", cache_dir=_cache_dir()), str)
            for repo in (CLIPSEG_ID, SAM_ID)
        )
    except Exception:
        return False


def _cache_dir() -> str | None:
    """`WORKER_SEGMENTER_CACHE` is a Hugging Face hub cache directory holding both models."""
    return os.environ.get("WORKER_SEGMENTER_CACHE", "").strip() or None


def _models():
    global _MODELS
    if _MODELS is None:
        import torch
        from transformers import (
            CLIPSegForImageSegmentation,
            CLIPSegProcessor,
            SamModel,
            SamProcessor,
        )

        device = "cuda" if torch.cuda.is_available() else "cpu"
        kwargs = {"cache_dir": _cache_dir(), "local_files_only": True}
        _MODELS = (
            torch,
            device,
            CLIPSegProcessor.from_pretrained(CLIPSEG_ID, **kwargs),
            CLIPSegForImageSegmentation.from_pretrained(CLIPSEG_ID, **kwargs).to(device).eval(),
            SamProcessor.from_pretrained(SAM_ID, **kwargs),
            SamModel.from_pretrained(SAM_ID, **kwargs).to(device).eval(),
        )
    return _MODELS


def warm() -> None:
    """Load both models now so the first request does not pay for it."""
    with _LOCK:
        _models()


def _heat(image: Image.Image) -> np.ndarray:
    torch, device, clip_proc, clip_model, _, _ = _models()
    with torch.inference_mode():
        inputs = clip_proc(
            text=list(RICE_PROMPTS),
            images=[image] * len(RICE_PROMPTS),
            padding=True,
            return_tensors="pt",
        ).to(device)
        prob = torch.sigmoid(clip_model(**inputs).logits.float())
        prob = torch.nn.functional.interpolate(
            prob[:, None], size=image.size[::-1], mode="bilinear"
        )[:, 0]
    return prob.mean(0).cpu().numpy()


def _outline(image: Image.Image, region: np.ndarray) -> tuple[np.ndarray, float]:
    """SAM's mask for `region`, and how well it agrees with it."""
    torch, device, _, _, sam_proc, sam_model = _models()
    ys, xs = np.nonzero(region)
    box = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
    cy, cx = np.unravel_index(np.argmax(ndi.distance_transform_edt(region)), region.shape)
    with torch.inference_mode():
        inputs = sam_proc(
            image,
            input_boxes=[[box]],
            input_points=[[[[int(cx), int(cy)]]]],
            input_labels=[[[1]]],
            return_tensors="pt",
        ).to(device)
        out = sam_model(**inputs)
        masks = sam_proc.image_processor.post_process_masks(
            out.pred_masks.cpu(),
            inputs["original_sizes"].cpu(),
            inputs["reshaped_input_sizes"].cpu(),
        )[0][0].numpy()
    best, agreement = None, -1.0
    for mask in masks:
        iou = float((mask & region).sum()) / max(float((mask | region).sum()), 1.0)
        if iou > agreement:
            best, agreement = mask, iou
    return best.astype(bool), agreement


def find_rice(image: Image.Image) -> tuple[np.ndarray, dict[str, float]]:
    """Boolean rice mask the size of `image`, plus the numbers behind the decision.

    Raises RiceNotFound when the photo shows no confident rice region.
    """
    image = image.convert("RGB")
    with _LOCK:
        heat = _heat(image)
        peak = float(heat.max())
        if peak < MIN_PEAK:
            raise RiceNotFound(f"rice heat-map peak {peak:.2f} is below {MIN_PEAK}")
        seed = heat > 0.5 * peak
        labels, count = ndi.label(seed)
        sizes = ndi.sum(seed, labels, range(1, count + 1))
        region = labels == (1 + int(np.argmax(sizes)))
        mask, agreement = _outline(image, region)
    # Drop specks and pinholes so the edit has one clean area.
    mask = ndi.binary_opening(mask, iterations=2)
    labels, count = ndi.label(mask)
    if count:
        sizes = ndi.sum(mask, labels, range(1, count + 1))
        mask = np.isin(labels, 1 + np.flatnonzero(sizes >= 0.05 * sizes.max()))
    mask = ndi.binary_fill_holes(mask)
    coverage = float(mask.mean())
    if agreement < MIN_AGREEMENT or not MIN_COVERAGE <= coverage <= MAX_COVERAGE:
        raise RiceNotFound(
            f"rice outline not trusted (agreement {agreement:.2f}, coverage {coverage:.3f})"
        )
    return mask, {"peak": round(peak, 3), "agreement": round(agreement, 3), "coverage": round(coverage, 4)}


def broccoli_patch(rice: np.ndarray) -> np.ndarray:
    """One round patch well inside the rice where broccoli is added.

    Centred on the point of the rice farthest from its edge, so the patch stays on the rice
    and the rest of the rice is left as photographed.
    """
    rice = rice.astype(bool)
    depth = ndi.distance_transform_edt(rice)
    cy, cx = np.unravel_index(np.argmax(depth), depth.shape)
    radius = float(min(0.75 * depth[cy, cx], 0.12 * rice.shape[0]))
    yy, xx = np.ogrid[: rice.shape[0], : rice.shape[1]]
    return ((yy - cy) ** 2 + (xx - cx) ** 2 <= radius * radius) & rice
