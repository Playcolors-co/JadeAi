import time
import requests
from supervisor_client import get_next_action

BTHID_API = "http://jadeai-bthid:5001"

def dispatch_action(action):
    kind = action.get("type")
    
    if kind == "type":
        requests.post(f"{BTHID_API}/hid/text", json={"text": action["text"]})
    elif kind == "move":
        requests.post(f"{BTHID_API}/hid/move", json={"x": action["x"], "y": action["y"]})
    elif kind == "click":
        requests.post(f"{BTHID_API}/hid/click", json={"button": action.get("button", "left")})
    else:
        print(f"Unknown action: {kind}")

if __name__ == "__main__":
    while True:
        action = get_next_action()
        if action:
            dispatch_action(action)
        time.sleep(0.5)
