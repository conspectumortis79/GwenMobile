WeSpeaker ResNet34-LM speaker embedding model, converted to Core ML for GwenMobile.
Upstream: https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM (revision 837717dd)
WeSpeaker: https://github.com/wenet-e2e/wespeaker
License: CC BY 4.0, https://creativecommons.org/licenses/by/4.0/
Changes: fused Kaldi-compatible fbank frontend, fixed 2 s / 16 kHz mono input,
safe statistics pooling, half-precision-safe fbank gain, Core ML conversion and
half-precision weights.
