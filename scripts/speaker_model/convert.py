import hashlib
import math
import shutil
import sys
import urllib.request
from pathlib import Path

import coremltools as ct
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchaudio
from pyannote.audio.models.embedding.wespeaker import WeSpeakerResNet34

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "speaker-model"
OUTPUT = ROOT / "GwenMobile" / "Resources" / "Models" / "WeSpeakerResNet34LM_2s.mlpackage"
CHECKPOINT = BUILD / "pytorch_model.bin"
CHECKPOINT_SHA256 = "366edf44f4c80889a3eb7a9d7bdf02c4aede3127f7dd15e274dcdb826b143c56"
MODEL_URL = "https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM/resolve/837717ddb9ff5507820346191109dc79c958d614/pytorch_model.bin"
WINDOW_SAMPLES = 32000
FFT_SIZE = 512
FRAME_LENGTH = 400
FRAME_SHIFT = 160
MEL_BINS = 80
MEL_SCALE = 8.0
LOG_FLOOR = 1.1920928955078125e-07


class FusedFbank(nn.Module):
    def __init__(self):
        super().__init__()
        kernel = torch.zeros(FRAME_LENGTH, 1, FRAME_LENGTH)
        for index in range(FRAME_LENGTH):
            kernel[index, 0, index] = 1.0
        self.register_buffer("frame_kernel", kernel)
        self.register_buffer("window", torch.hamming_window(FRAME_LENGTH, periodic=False,
                                                            alpha=0.54, beta=0.46))
        samples = torch.arange(FFT_SIZE, dtype=torch.float32)
        bins = torch.arange(FFT_SIZE // 2 + 1, dtype=torch.float32)
        angle = 2.0 * math.pi * bins[:, None] * samples[None, :] / float(FFT_SIZE)
        self.register_buffer("dft_cos", torch.cos(angle))
        self.register_buffer("dft_sin", torch.sin(angle))
        mel, _ = torchaudio.compliance.kaldi.get_mel_banks(
            MEL_BINS, FFT_SIZE, 16000, 20.0, 0.0, 100.0, -500.0, 1.0)
        self.register_buffer("mel", F.pad(mel, (0, 1), mode="constant", value=0.0))

    def forward(self, waveform):
        frames = torch.nn.functional.conv1d(waveform.unsqueeze(1) * MEL_SCALE,
                                            self.frame_kernel, stride=FRAME_SHIFT)
        frames = frames.transpose(1, 2)
        frames = frames - frames.mean(dim=2, keepdim=True)
        previous = torch.cat([frames[:, :, :1], frames[:, :, :-1]], dim=2)
        frames = frames - 0.97 * previous
        frames = frames * self.window
        frames = torch.nn.functional.pad(frames, (0, FFT_SIZE - frames.shape[2]))
        real = torch.matmul(frames, self.dft_cos.t())
        imag = torch.matmul(frames, self.dft_sin.t())
        power = real * real + imag * imag
        mel = torch.matmul(power, self.mel.t())
        centered = torch.log(torch.clamp(mel, min=LOG_FLOOR))
        return centered - centered.mean(dim=1, keepdim=True)


class SafeStatsPool(nn.Module):
    def forward(self, sequences, weights=None):
        mean = sequences.mean(dim=-1)
        variance = ((sequences - mean.unsqueeze(-1)) ** 2).sum(dim=-1) / float(sequences.shape[-1] - 1)
        std = torch.sqrt(torch.clamp(variance, min=1.0e-8))
        return torch.cat([mean, std], dim=-1)


class FullModel(nn.Module):
    def __init__(self, resnet):
        super().__init__()
        self.fbank = FusedFbank()
        self.resnet = resnet

    def forward(self, waveform):
        embedding = self.resnet(self.fbank(waveform))[1]
        return F.normalize(embedding, p=2, dim=1)


def download():
    BUILD.mkdir(parents=True, exist_ok=True)
    if not CHECKPOINT.exists():
        with urllib.request.urlopen(MODEL_URL, timeout=120) as response, CHECKPOINT.open("wb") as target:
            target.write(response.read())
    digest = hashlib.sha256(CHECKPOINT.read_bytes()).hexdigest()
    if digest != CHECKPOINT_SHA256:
        CHECKPOINT.unlink(missing_ok=True)
        raise RuntimeError("checkpoint checksum mismatch")


def main():
    download()
    checkpoint = torch.load(CHECKPOINT, map_location="cpu", weights_only=False)
    state = checkpoint["state_dict"]
    reference = WeSpeakerResNet34()
    reference.resnet.load_state_dict({key[7:]: value for key, value in state.items()
                                      if key.startswith("resnet.")}, strict=True)
    reference.eval()
    reference.resnet.pool.stats_pool = SafeStatsPool()
    model = FullModel(reference.resnet).eval()
    with torch.no_grad():
        traced = torch.jit.trace(model, torch.zeros(1, WINDOW_SAMPLES))
    traced = torch.jit.freeze(traced.eval())
    converted = ct.convert(
        traced,
        inputs=[ct.TensorType(name="waveform", shape=(1, WINDOW_SAMPLES))],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.iOS26,
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.ALL,
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    converted.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    sys.exit(main())
