# Models and Acceleration

## Vision
- Default detector: YOLOv8/11 nano exported to TensorRT (`.engine`).
- OCR: PaddleOCR English lightweight model.
- Optional segmentation heads for cursor detection.

## LLM
- Recommended: Llama 3.1 8B or Mistral 7B Q4-K GGUF for llama.cpp server.
- Alternative: TensorRT-LLM engines (see `scripts/export_llm_trtllm.sh`).

## Conversion

1. Export ONNX from training pipeline.
2. Run `scripts/build_trt_engines.py --model detector.onnx` to generate `.engine` files.
3. For GGUF: `scripts/export_llm_gguf.sh /path/to/model`.
4. Update `configs/models.yml` with the new paths.

## Jetson Specifics
- Ensure JetPack 6.x with CUDA 12 is installed.
- Install TensorRT Python bindings via the Jetson SDK Manager.
- Use swap space when converting large models on 8 GB devices.
