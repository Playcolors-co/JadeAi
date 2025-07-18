from pydbus import SystemBus

def setup_bluetooth():
    # Enable and set discoverable via D-Bus
    bus = SystemBus()
    adapter = bus.get('org.bluez', '/org/bluez/hci0')
    adapter.Powered = True
    adapter.Discoverable = True

def get_status():
    bus = SystemBus()
    adapter = bus.get('org.bluez', '/org/bluez/hci0')
    return {
        "powered": adapter.Powered,
        "discoverable": adapter.Discoverable
    }

def disconnect():
    # Optional: clear paired devices or reset interface
    pass
