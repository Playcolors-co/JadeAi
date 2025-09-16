from services.perception.service import PerceptionService


def test_perception_pipeline():
    service = PerceptionService()
    frame = service.capture()
    detections = service.run_inference(frame)
    assert detections, "expected at least one detection"
    overlay = service.annotate(detections)
    assert "Rendered" in overlay
