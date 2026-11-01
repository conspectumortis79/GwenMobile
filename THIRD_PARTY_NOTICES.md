# Third-party notices

## WeSpeaker ResNet34-LM speaker embedding model

The bundled Core ML model `WeSpeakerResNet34LM_2s.mlpackage` is a converted version of
`pyannote/wespeaker-voxceleb-resnet34-LM`, a wrapper around WeSpeaker's
`wespeaker-voxceleb-resnet34-LM` pretrained speaker embedding model.

- Upstream model: https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM (revision 837717dd)
- WeSpeaker: https://github.com/wenet-e2e/wespeaker
- License of the model weights: Creative Commons Attribution 4.0 International (CC BY 4.0)
- License text: https://creativecommons.org/licenses/by/4.0/legalcode

Changes made for GwenMobile: the waveform frontend (Kaldi-compatible 80-bin fbank with
mean subtraction) was fused into the model, the input was fixed to two seconds at
16 kHz mono, the statistics pooling was made numerically safe for half precision, and
the graph was converted to Core ML and quantized to half precision. The fbank gain was
chosen so that half-precision arithmetic stays in range; the time-mean subtraction removes
the resulting constant offset. The model output is a 256-dimensional L2-normalized speaker
embedding.

## pyannote.audio

The conversion script uses the WeSpeaker wrapper and architecture from pyannote.audio.

- Project: https://github.com/pyannote/pyannote-audio
- License: MIT

## Conversion tooling

The conversion script uses PyTorch, torchaudio and Core ML Tools. Their licenses apply to
the development tooling only and are not bundled with the app.

- PyTorch: BSD-style license, https://github.com/pytorch/pytorch/blob/main/LICENSE
- torchaudio: BSD-2-Clause license, https://github.com/pytorch/audio/blob/main/LICENSE
- Core ML Tools: BSD-3-Clause license, https://github.com/apple/coremltools/blob/main/LICENSE.txt
