#include "bluetooth_manager.h"

#include "hid_report_map.h"

#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>

#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

namespace {
constexpr int kCommandTimeout = 1000; // milliseconds
constexpr uint32_t kClassOfDevice = 0x002540; // Peripheral, combo keyboard/pointing
}

BluetoothManager::BluetoothManager() : dev_id_(-1), initialized_(false) {}

BluetoothManager::~BluetoothManager() { teardown(); }

void BluetoothManager::initialize(const std::string &device_name) {
    if (initialized_)
        return;

    dev_id_ = hci_get_route(nullptr);
    if (dev_id_ < 0) {
        throw std::runtime_error("Unable to find a Bluetooth adapter");
    }

    bring_up_adapter();

    int sock = hci_open_dev(dev_id_);
    if (sock < 0) {
        throw std::runtime_error("Failed to open HCI device");
    }

    try {
        configure_adapter(sock, device_name);
    } catch (...) {
        close(sock);
        throw;
    }

    close(sock);
    initialized_ = true;
}

void BluetoothManager::teardown() {
    if (!initialized_)
        return;
    // Keep adapter powered up for quicker reconnection; nothing to do here.
    initialized_ = false;
}

void BluetoothManager::bring_up_adapter() {
    int ctl = socket(AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI);
    if (ctl < 0) {
        throw std::runtime_error("Failed to open control socket for Bluetooth adapter");
    }

    if (ioctl(ctl, HCIDEVUP, dev_id_) < 0) {
        if (errno != EALREADY) {
            close(ctl);
            throw std::runtime_error("Failed to power Bluetooth adapter");
        }
    }

    close(ctl);
}

void BluetoothManager::configure_adapter(int sock, const std::string &device_name) {
    if (hci_write_local_name(sock, device_name.c_str(), kCommandTimeout) < 0) {
        std::cerr << "[bthid] Warning: unable to set adapter name" << std::endl;
    }

    if (hci_write_class_of_dev(sock, kClassOfDevice, kCommandTimeout) < 0) {
        std::cerr << "[bthid] Warning: unable to set class of device" << std::endl;
    }

    uint8_t simple_pairing_mode = 0x01;
    if (hci_write_simple_pairing_mode(sock, simple_pairing_mode, kCommandTimeout) < 0) {
        std::cerr << "[bthid] Warning: unable to enable simple pairing" << std::endl;
    }

    uint8_t scan_enable = SCAN_PAGE | SCAN_INQUIRY;
    if (hci_send_cmd(sock, OGF_HOST_CTL, OCF_WRITE_SCAN_ENABLE, sizeof(scan_enable), &scan_enable) < 0) {
        std::cerr << "[bthid] Warning: unable to enable discoverable mode" << std::endl;
    }
}

SdpRegistrar::SdpRegistrar() : session_(nullptr), record_(nullptr) {}

SdpRegistrar::~SdpRegistrar() { unregister(); }

void SdpRegistrar::register_hid_service(const unsigned char *descriptor, std::size_t length) {
    if (record_ != nullptr)
        return;

    bdaddr_t any = {{0, 0, 0, 0, 0, 0}};
    bdaddr_t local = {{0, 0, 0, 0xff, 0xff, 0xff}};
    session_ = sdp_connect(&any, &local, SDP_RETRY_IF_BUSY);
    if (!session_) {
        throw std::runtime_error("Failed to connect to local SDP server");
    }

    record_ = sdp_record_alloc();
    if (!record_) {
        sdp_close(session_);
        session_ = nullptr;
        throw std::runtime_error("Failed to allocate SDP record");
    }

    try {
        add_hid_attributes(record_, descriptor, length);
    } catch (...) {
        sdp_record_free(record_);
        record_ = nullptr;
        sdp_close(session_);
        session_ = nullptr;
        throw;
    }

    if (sdp_record_register(session_, record_, 0) < 0) {
        sdp_record_free(record_);
        record_ = nullptr;
        sdp_close(session_);
        session_ = nullptr;
        throw std::runtime_error("Failed to register HID SDP record");
    }
}

void SdpRegistrar::unregister() {
    if (record_) {
        sdp_record_unregister(session_, record_);
        sdp_record_free(record_);
        record_ = nullptr;
    }
    if (session_) {
        sdp_close(session_);
        session_ = nullptr;
    }
}

namespace {

sdp_list_t *create_uuid_list(uint16_t uuid16) {
    uuid_t *uuid = static_cast<uuid_t *>(std::malloc(sizeof(uuid_t)));
    if (!uuid)
        throw std::bad_alloc();
    sdp_uuid16_create(uuid, uuid16);
    return sdp_list_append(nullptr, uuid);
}

} // namespace

void SdpRegistrar::add_hid_attributes(sdp_record_t *record, const unsigned char *descriptor, std::size_t length) {
    // Service class
    sdp_list_t *service_class_list = create_uuid_list(HID_SVCLASS_ID);
    sdp_set_service_classes(record, service_class_list);

    // Profile descriptor
    static sdp_profile_desc_t profile;
    static bool profile_initialized = false;
    if (!profile_initialized) {
        std::memset(&profile, 0, sizeof(profile));
        sdp_uuid16_create(&profile.uuid, HID_PROFILE_ID);
        profile.version = 0x0100;
        profile_initialized = true;
    }
    sdp_list_t *profile_list = sdp_list_append(nullptr, &profile);
    sdp_set_profile_descs(record, profile_list);

    // Browse group
    sdp_list_t *browse_list = create_uuid_list(PUBLIC_BROWSE_GROUP);
    sdp_set_browse_groups(record, browse_list);

    // Protocol descriptor for control channel
    uint16_t control_psm = 0x0011;
    sdp_data_t *control_psm_data = sdp_data_alloc(SDP_UINT16, &control_psm);

    sdp_list_t *l2cap_list = create_uuid_list(L2CAP_UUID);
    l2cap_list = sdp_list_append(l2cap_list, control_psm_data);

    sdp_list_t *hidp_list = create_uuid_list(HIDP_UUID);

    sdp_list_t *control_proto = sdp_list_append(nullptr, l2cap_list);
    control_proto = sdp_list_append(control_proto, hidp_list);

    sdp_list_t *access_proto_list = sdp_list_append(nullptr, control_proto);
    sdp_set_access_protos(record, access_proto_list);

    // Additional protocol descriptor for interrupt channel
    uint16_t interrupt_psm = 0x0013;
    sdp_data_t *interrupt_psm_data = sdp_data_alloc(SDP_UINT16, &interrupt_psm);

    sdp_list_t *l2cap_list_interrupt = create_uuid_list(L2CAP_UUID);
    l2cap_list_interrupt = sdp_list_append(l2cap_list_interrupt, interrupt_psm_data);

    sdp_list_t *hidp_list_interrupt = create_uuid_list(HIDP_UUID);

    sdp_list_t *interrupt_proto = sdp_list_append(nullptr, l2cap_list_interrupt);
    interrupt_proto = sdp_list_append(interrupt_proto, hidp_list_interrupt);

    sdp_list_t *additional_proto_list = sdp_list_append(nullptr, interrupt_proto);
    sdp_set_add_access_protos(record, additional_proto_list);

    // Service info
    sdp_set_info_attr(record, "JadeAI HID", "JadeAI", "Combined keyboard and mouse");

    uint16_t release_number = 0x0100;
    uint16_t parser_version = 0x0111;
    uint8_t device_subclass = 0xC0; // Keyboard + pointing device
    uint8_t country_code = 0x00;
    uint8_t virtual_cable = 0x01;
    uint8_t reconnect_initiate = 0x01;
    uint8_t battery_power = 0x01;
    uint8_t remote_wakeup = 0x01;
    uint16_t profile_version = 0x0100;
    uint16_t supervision_timeout = 0x0C80; // 4 seconds
    uint8_t normally_connectable = 0x00;
    uint8_t boot_device = 0x01;

    sdp_attr_add_new(record, SDP_ATTR_HID_DEVICE_RELEASE_NUMBER, SDP_UINT16, &release_number);
    sdp_attr_add_new(record, SDP_ATTR_HID_PARSER_VERSION, SDP_UINT16, &parser_version);
    sdp_attr_add_new(record, SDP_ATTR_HID_DEVICE_SUBCLASS, SDP_UINT8, &device_subclass);
    sdp_attr_add_new(record, SDP_ATTR_HID_COUNTRY_CODE, SDP_UINT8, &country_code);
    sdp_attr_add_new(record, SDP_ATTR_HID_VIRTUAL_CABLE, SDP_BOOL, &virtual_cable);
    sdp_attr_add_new(record, SDP_ATTR_HID_RECONNECT_INITIATE, SDP_BOOL, &reconnect_initiate);
    sdp_attr_add_new(record, SDP_ATTR_HID_BATTERY_POWER, SDP_BOOL, &battery_power);
    sdp_attr_add_new(record, SDP_ATTR_HID_REMOTE_WAKEUP, SDP_BOOL, &remote_wakeup);
    sdp_attr_add_new(record, SDP_ATTR_HID_PROFILE_VERSION, SDP_UINT16, &profile_version);
    sdp_attr_add_new(record, SDP_ATTR_HID_SUPERVISION_TIMEOUT, SDP_UINT16, &supervision_timeout);
    sdp_attr_add_new(record, SDP_ATTR_HID_NORMALLY_CONNECTABLE, SDP_BOOL, &normally_connectable);
    sdp_attr_add_new(record, SDP_ATTR_HID_BOOT_DEVICE, SDP_BOOL, &boot_device);

    // HID descriptor list
    uint8_t descriptor_type = 0x22; // Report descriptor
    sdp_data_t *descriptor_sequence = nullptr;
    descriptor_sequence = sdp_seq_append(descriptor_sequence, sdp_data_alloc(SDP_UINT8, &descriptor_type));
    descriptor_sequence = sdp_seq_append(
        descriptor_sequence,
        sdp_data_alloc_with_length(SDP_TEXT_STR8, descriptor, static_cast<uint32_t>(length)));

    sdp_data_t *descriptor_list = sdp_data_alloc(SDP_SEQ8, descriptor_sequence);
    sdp_attr_add(record, SDP_ATTR_HID_DESCRIPTOR_LIST, descriptor_list);

    // Language base list (English - UTF-8)
    uint16_t lang_id = 0x0409;
    uint16_t char_enc = 0x0100;
    uint16_t base_id = 0x0100;
    sdp_data_t *lang_seq = nullptr;
    lang_seq = sdp_seq_append(lang_seq, sdp_data_alloc(SDP_UINT16, &lang_id));
    lang_seq = sdp_seq_append(lang_seq, sdp_data_alloc(SDP_UINT16, &char_enc));
    lang_seq = sdp_seq_append(lang_seq, sdp_data_alloc(SDP_UINT16, &base_id));

    sdp_data_t *lang_base_list = sdp_data_alloc(SDP_SEQ8, lang_seq);
    sdp_attr_add(record, SDP_ATTR_HID_LANG_ID_BASE_LIST, lang_base_list);

    // The SDP library takes ownership of allocated nodes for the duration of the
    // registered record, so we intentionally do not free the intermediate lists
    // here to avoid invalidating pointers.
}
