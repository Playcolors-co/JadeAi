# Training Notes

## Detector
- Collect UI screenshots and label buttons, inputs, and icons.
- Export YOLO-format datasets and train with Ultralytics.
- Convert to TensorRT using `scripts/build_trt_engines.py`.

## OCR
- Fine-tune PaddleOCR with UI fonts where necessary.
- Use dynamic dictionaries for CLI/terminal recognition.

## Planner
- Generate synthetic dialogues of tasks and expected sequences.
- Few-shot fine-tuning of the LLM with plan JSON schema.

## Safety
- Maintain a curated list of hazardous strings in `configs/policy.yml`.
- Validate dataset prompts to avoid destructive actions.
