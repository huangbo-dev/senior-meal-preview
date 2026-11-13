"""App-only photo edit methods (not the CE7454 research policy).

The research editor blanks the painted area and regenerates it, which on user-painted areas
often draws a new bowl or plate. These two methods keep the user's pixels where possible:

  recolour_rice      colour transfer in CIELAB inside the painted area; the real grains stay.
                     No generative model is involved.
  BlendedEditor      masked SDXL image-to-image with latent blending, used to add broccoli on a
                     small painted patch. It reuses the weights the research editor has loaded.

They were chosen by eye on one public photograph (13 November 2026). That is a development
check, not an evaluation, and nothing here may be reported as a CE7454 result.
"""

from __future__ import annotations

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, gaussian_filter

METHOD_VERSION = "app-v1"

# Cooked brown rice as a CIELAB (L*, a*, b*) target for the median rice pixel, and the gain on
# lightness differences (bran makes single grains stand out a little more than polished rice).
BROWN_RICE_LAB = (56.0, 11.0, 29.0)
BROWN_RICE_GAIN = 1.35

BROCCOLI_PROMPT = (
    "food photo, a few bright green cooked broccoli florets resting on a mound of steamed white rice"
)
BROCCOLI_NEGATIVE = "bowl, plate, dish, cup, saucer, blurry, cartoon, text"
BROCCOLI_STRENGTH = 0.95
BROCCOLI_STEPS = 20
BROCCOLI_GUIDANCE = 7.5

_RGB_TO_XYZ = np.array(
    [
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ]
)
_WHITE = np.array([0.95047, 1.0, 1.08883])


def rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB uint8 (..., 3) to CIELAB (D65)."""
    a = rgb.astype("float64") / 255
    a = np.where(a > 0.04045, ((a + 0.055) / 1.055) ** 2.4, a / 12.92)
    xyz = a @ _RGB_TO_XYZ.T / _WHITE
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack(
        [116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1
    )


def lab_to_rgb(lab: np.ndarray) -> np.ndarray:
    """CIELAB (D65) to sRGB uint8, clipped to gamut."""
    fy = (lab[..., 0] + 16) / 116
    f = np.stack([fy + lab[..., 1] / 500, fy, fy - lab[..., 2] / 200], -1)
    xyz = np.where(f**3 > 0.008856, f**3, (f - 16 / 116) / 7.787) * _WHITE
    a = np.clip(xyz @ np.linalg.inv(_RGB_TO_XYZ).T, 0, 1)
    a = np.where(a > 0.0031308, 1.055 * a ** (1 / 2.4) - 0.055, 12.92 * a)
    return np.clip(np.rint(a * 255), 0, 255).astype("uint8")


def _disk(radius: int) -> np.ndarray:
    y, x = np.ogrid[-radius : radius + 1, -radius : radius + 1]
    return x * x + y * y <= radius * radius


def recolour_rice(image: Image.Image, mask: np.ndarray) -> Image.Image:
    """Shift the painted rice to a cooked-brown-rice colour, keeping every grain.

    The painted area is trusted and feathered at its edge. Pixels much darker than the rice
    (shadow, sauce, a leaf) are left alone. A white plate under a sloppy brush stroke cannot be
    told from rice by colour and will be tinted too, so the user is asked to paint the rice only.
    """
    rgb = np.asarray(image.convert("RGB"))
    mask = mask.astype(bool)
    lab = rgb_to_lab(rgb)
    centre = np.median(lab[mask], 0)
    out = lab.copy()
    out[..., 0] = np.clip(
        BROWN_RICE_LAB[0] + (lab[..., 0] - centre[0]) * BROWN_RICE_GAIN, 0, 100
    )
    out[..., 1] = BROWN_RICE_LAB[1] + (lab[..., 1] - centre[1])
    out[..., 2] = BROWN_RICE_LAB[2] + (lab[..., 2] - centre[2])
    rice_like = np.clip((lab[..., 0] - (centre[0] - 30)) / 15, 0, 1)
    near = binary_dilation(mask, _disk(6))
    weight = np.clip(gaussian_filter(mask.astype("float64"), 2.5), 0, 1) * np.where(near, rice_like, 0)
    weight = weight[..., None]
    mixed = weight * lab_to_rgb(out).astype("float64") + (1 - weight) * rgb
    return Image.fromarray(np.clip(np.rint(mixed), 0, 255).astype("uint8"))


class BlendedEditor:
    """Masked SDXL image-to-image that keeps everything outside the painted patch.

    Unlike the research editor, the patch is not blanked first: generation starts from the
    photo's own latents, and after every denoising step the latents outside the patch are reset
    to the (noised) original. The model therefore sees the surrounding rice and has no empty
    disc to fill with a bowl.
    """

    def __init__(self, editor) -> None:
        import diffusers

        base = editor.pipe
        self._editor = editor
        self._pipe = diffusers.StableDiffusionXLImg2ImgPipeline(
            vae=base.vae,
            text_encoder=base.text_encoder,
            text_encoder_2=base.text_encoder_2,
            tokenizer=base.tokenizer,
            tokenizer_2=base.tokenizer_2,
            unet=base.unet,
            scheduler=diffusers.DPMSolverMultistepScheduler.from_config(base.scheduler.config),
        )
        self._pipe.set_progress_bar_config(disable=True)

    def _generate(self, source: Image.Image, mask: np.ndarray, seed: int) -> Image.Image:
        import torch

        with torch.inference_mode():
            vae, device = self._editor.vae, self._editor.device
            scale = vae.config.scaling_factor
            pixels = np.array(source.convert("RGB"), dtype="float32") / 127.5 - 1
            x = torch.from_numpy(pixels).permute(2, 0, 1)[None].to(device)
            generator = torch.Generator("cpu").manual_seed(int(seed))
            # The editor's VAE runs in fp32 and hands back fp16 samples (see sgedit.editor).
            init = (vae.encode(x).latent_dist.sample(generator) * scale).half()
            grown = binary_dilation(mask, _disk(8)).astype("float32")
            keep = torch.nn.functional.max_pool2d(torch.from_numpy(grown)[None, None].to(device), 8).half()
            noise = torch.randn(init.shape, generator=generator).to(device).half()
            scheduler = self._pipe.scheduler

            def blend(_pipe, step, _timestep, tensors):
                steps = scheduler.timesteps
                original = (
                    scheduler.add_noise(init, noise, steps[step + 1 : step + 2])
                    if step + 1 < len(steps)
                    else init
                )
                latents = tensors["latents"]
                tensors["latents"] = keep * latents + (1 - keep) * original.to(latents.dtype)
                return tensors

            latents = self._pipe(
                prompt=BROCCOLI_PROMPT,
                negative_prompt=BROCCOLI_NEGATIVE,
                image=init,
                strength=BROCCOLI_STRENGTH,
                num_inference_steps=BROCCOLI_STEPS,
                guidance_scale=BROCCOLI_GUIDANCE,
                generator=generator,
                output_type="latent",
                callback_on_step_end=blend,
                callback_on_step_end_tensor_inputs=["latents"],
            ).images
            if torch.isnan(latents).any():
                raise FloatingPointError("NaN latents")
            decoded = vae.decode(latents.float() / scale).sample
            return self._pipe.image_processor.postprocess(decoded, output_type="pil")[0].convert("RGB")

    def add_broccoli(self, image: Image.Image, mask: np.ndarray, seed: int, research_editor) -> Image.Image:
        """Generate on a square crop around the patch and paste it back inside the feathered patch."""
        mask = mask.astype(bool)
        box = research_editor.crop_box(mask, 0.25, 384, image.size[0])
        side = (1024, 1024)
        source = image.crop(box).resize(side, Image.LANCZOS)
        crop_mask = Image.fromarray(mask[box[1] : box[3], box[0] : box[2]].astype("uint8") * 255)
        small = np.asarray(crop_mask.resize(side, Image.NEAREST)) > 127
        generated = self._generate(source, small, seed).resize(
            (box[2] - box[0], box[3] - box[1]), Image.LANCZOS
        )
        raw = image.copy()
        raw.paste(generated, box[:2])
        alpha = research_editor.feather_alpha(mask)[..., None]
        mixed = alpha * np.asarray(raw, "float64") + (1 - alpha) * np.asarray(image.convert("RGB"), "float64")
        return Image.fromarray(np.clip(np.rint(mixed), 0, 255).astype("uint8"))
