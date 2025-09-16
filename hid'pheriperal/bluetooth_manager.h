#ifndef BLUETOOTH_MANAGER_H
#define BLUETOOTH_MANAGER_H

#include <cstdint>
#include <cstddef>
#include <string>
#include <bluetooth/sdp.h>
#include <bluetooth/sdp_lib.h>

class BluetoothManager {
public:
    BluetoothManager();
    ~BluetoothManager();

    void initialize(const std::string &device_name);
    void teardown();

    bool is_initialized() const { return initialized_; }

private:
    int dev_id_;
    bool initialized_;

    void bring_up_adapter();
    void configure_adapter(int sock, const std::string &device_name);
};

class SdpRegistrar {
public:
    SdpRegistrar();
    ~SdpRegistrar();

    void register_hid_service(const unsigned char *descriptor, std::size_t length);
    void unregister();

    bool is_registered() const { return record_ != nullptr; }

private:
    sdp_session_t *session_;
    sdp_record_t *record_;

    void add_hid_attributes(sdp_record_t *record, const unsigned char *descriptor, std::size_t length);
};

#endif // BLUETOOTH_MANAGER_H
