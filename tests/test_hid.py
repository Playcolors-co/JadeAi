from services.hid.hid_server import HIDController


def test_hid_queue():
    controller = HIDController()
    controller.click(10, 20)
    controller.type_text("hello")
    first = controller.dequeue()
    assert first is not None and first.type == "click"
    second = controller.dequeue()
    assert second is not None and second.type == "text"
