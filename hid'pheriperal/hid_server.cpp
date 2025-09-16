#include "hid_server.h"

#include "key_mapper.h"

#include <bluetooth/bluetooth.h>
#include <bluetooth/l2cap.h>

#include <chrono>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <poll.h>
#include <stdexcept>
#include <string>
#include <sys/socket.h>
#include <unistd.h>
#include <thread>

namespace {
constexpr uint16_t kControlPsm = 0x11;
constexpr uint16_t kInterruptPsm = 0x13;
constexpr uint8_t kKeyboardReportId = 0x01;
constexpr uint8_t kMouseReportId = 0x02;
constexpr uint8_t kLeftShiftMask = 0x02;
int create_listen_socket(uint16_t psm) {
    int fd = socket(AF_BLUETOOTH, SOCK_SEQPACKET, BTPROTO_L2CAP);
    if (fd < 0) {
        throw std::runtime_error("Unable to create L2CAP socket");
    }

    sockaddr_l2 addr{};
    addr.l2_family = AF_BLUETOOTH;
    bdaddr_t any = {{0, 0, 0, 0, 0, 0}};
    addr.l2_bdaddr = any;
    addr.l2_psm = htobs(psm);

    if (bind(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
        close(fd);
        throw std::runtime_error("Failed to bind L2CAP socket");
    }

    int lm = L2CAP_LM_ENCRYPT | L2CAP_LM_AUTH | L2CAP_LM_MASTER;
    if (setsockopt(fd, SOL_L2CAP, L2CAP_LM, &lm, sizeof(lm)) < 0) {
        std::cerr << "[bthid] Warning: unable to set link mode on L2CAP socket" << std::endl;
    }

    if (listen(fd, 1) < 0) {
        close(fd);
        throw std::runtime_error("Failed to listen on L2CAP socket");
    }

    return fd;
}

constexpr uint8_t HID_MSG_TYPE_HANDSHAKE = 0x00;
constexpr uint8_t HID_MSG_TYPE_CONTROL = 0x10;
constexpr uint8_t HID_MSG_TYPE_GET_REPORT = 0x40;
constexpr uint8_t HID_MSG_TYPE_SET_REPORT = 0x50;
constexpr uint8_t HID_MSG_TYPE_GET_PROTOCOL = 0x60;
constexpr uint8_t HID_MSG_TYPE_SET_PROTOCOL = 0x70;
constexpr uint8_t HID_MSG_TYPE_DATA = 0xA0;

constexpr uint8_t HID_HANDSHAKE_SUCCESS = 0x00;
constexpr uint8_t HID_HANDSHAKE_ERR_UNSUPPORTED = 0x03;

constexpr uint8_t HID_CTRL_VIRTUAL_CABLE_UNPLUG = 0x05;

} // namespace

HidServer::HidServer()
    : control_listen_fd_(-1),
      interrupt_listen_fd_(-1),
      control_client_fd_(-1),
      interrupt_client_fd_(-1),
      running_(false),
      connected_(false),
      protocol_mode_(1),
      led_status_(0) {}

HidServer::~HidServer() { stop(); }

void HidServer::start() {
    if (running_)
        return;

    control_listen_fd_ = create_listen_socket(kControlPsm);
    interrupt_listen_fd_ = create_listen_socket(kInterruptPsm);

    running_ = true;
    accept_thread_ = std::thread(&HidServer::accept_loop, this);
}

void HidServer::stop() {
    if (!running_ && control_listen_fd_ < 0 && interrupt_listen_fd_ < 0)
        return;

    running_ = false;

    if (control_listen_fd_ >= 0) {
        close(control_listen_fd_);
        control_listen_fd_ = -1;
    }
    if (interrupt_listen_fd_ >= 0) {
        close(interrupt_listen_fd_);
        interrupt_listen_fd_ = -1;
    }

    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        reset_connection_locked();
        connected_cv_.notify_all();
    }

    if (accept_thread_.joinable()) {
        accept_thread_.join();
    }
    if (control_thread_.joinable()) {
        control_thread_.join();
    }
}

bool HidServer::send_keyboard_report(const KeyboardReport &report) {
    uint8_t packet[9]{};
    packet[0] = kKeyboardReportId;
    packet[1] = report.modifiers;
    packet[2] = report.reserved;
    std::memcpy(packet + 3, report.keys, sizeof(report.keys));
    bool report_mode;
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        report_mode = protocol_mode_ != 0;
    }
    const uint8_t *data = report_mode ? packet : packet + 1;
    std::size_t length = report_mode ? sizeof(packet) : sizeof(packet) - 1;
    return send_interrupt_packet(data, length);
}

bool HidServer::send_mouse_report(const MouseReport &report) {
    uint8_t packet[5]{};
    packet[0] = kMouseReportId;
    packet[1] = report.buttons;
    packet[2] = static_cast<uint8_t>(report.dx);
    packet[3] = static_cast<uint8_t>(report.dy);
    packet[4] = static_cast<uint8_t>(report.wheel);
    bool report_mode;
    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        report_mode = protocol_mode_ != 0;
    }
    const uint8_t *data = report_mode ? packet : packet + 1;
    std::size_t length = report_mode ? sizeof(packet) : 3; // Buttons, X, Y in boot mode
    return send_interrupt_packet(data, length);
}

bool HidServer::type_text(const std::string &text) {
    for (char ch : text) {
        auto key = map_character(ch);
        if (!key.has_value()) {
            std::cerr << "[bthid] Warning: unsupported character '" << ch << "'" << std::endl;
            continue;
        }
        KeyboardReport report;
        if (key->requires_shift) {
            report.modifiers = kLeftShiftMask;
        }
        report.keys[0] = key->keycode;
        if (!send_keyboard_report(report)) {
            return false;
        }
        KeyboardReport release;
        if (!send_keyboard_report(release)) {
            return false;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(8));
    }
    return true;
}

bool HidServer::move_mouse(int dx, int dy, int wheel) {
    MouseReport report;
    if (dx > 127)
        dx = 127;
    if (dx < -127)
        dx = -127;
    if (dy > 127)
        dy = 127;
    if (dy < -127)
        dy = -127;
    if (wheel > 127)
        wheel = 127;
    if (wheel < -127)
        wheel = -127;
    report.dx = static_cast<int8_t>(dx);
    report.dy = static_cast<int8_t>(dy);
    report.wheel = static_cast<int8_t>(wheel);
    if (!send_mouse_report(report)) {
        return false;
    }
    MouseReport release;
    return send_mouse_report(release);
}

bool HidServer::click(uint8_t button_mask) {
    MouseReport press;
    press.buttons = button_mask;
    if (!send_mouse_report(press)) {
        return false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    MouseReport release;
    return send_mouse_report(release);
}

bool HidServer::is_connected() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return connected_;
}

uint8_t HidServer::current_protocol() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return protocol_mode_;
}

uint8_t HidServer::led_state() const {
    std::lock_guard<std::mutex> lock(state_mutex_);
    return led_status_;
}

void HidServer::accept_loop() {
    struct pollfd fds[2];

    while (running_) {
        fds[0].fd = control_listen_fd_;
        fds[0].events = POLLIN;
        fds[0].revents = 0;
        fds[1].fd = interrupt_listen_fd_;
        fds[1].events = POLLIN;
        fds[1].revents = 0;

        int ret = poll(fds, 2, 500);
        if (!running_)
            break;
        if (ret <= 0)
            continue;

        if ((fds[0].revents & POLLIN) && control_listen_fd_ >= 0) {
            sockaddr_l2 addr{};
            socklen_t len = sizeof(addr);
            int client = accept(control_listen_fd_, reinterpret_cast<sockaddr *>(&addr), &len);
            if (client >= 0) {
                std::lock_guard<std::mutex> lock(state_mutex_);
                close_client(control_client_fd_);
                control_client_fd_ = client;
                if (!control_thread_.joinable()) {
                    control_thread_ = std::thread(&HidServer::control_loop, this);
                }
            }
        }

        if ((fds[1].revents & POLLIN) && interrupt_listen_fd_ >= 0) {
            sockaddr_l2 addr{};
            socklen_t len = sizeof(addr);
            int client = accept(interrupt_listen_fd_, reinterpret_cast<sockaddr *>(&addr), &len);
            if (client >= 0) {
                std::lock_guard<std::mutex> lock(state_mutex_);
                close_client(interrupt_client_fd_);
                interrupt_client_fd_ = client;
                if (control_client_fd_ >= 0) {
                    connected_ = true;
                    protocol_mode_ = 1;
                    connected_cv_.notify_all();
                }
            }
        }
    }
}

void HidServer::control_loop() {
    uint8_t buffer[128];
    while (running_) {
        int fd;
        {
            std::lock_guard<std::mutex> lock(state_mutex_);
            fd = control_client_fd_;
            if (fd < 0)
                break;
        }

        ssize_t received = recv(fd, buffer, sizeof(buffer), 0);
        if (received <= 0) {
            break;
        }
        handle_control_message(buffer, static_cast<std::size_t>(received));
    }

    {
        std::lock_guard<std::mutex> lock(state_mutex_);
        reset_connection_locked();
    }
}

void HidServer::handle_control_message(const uint8_t *data, std::size_t length) {
    if (length == 0)
        return;

    uint8_t header = data[0];
    uint8_t type = header & 0xF0;
    uint8_t param = header & 0x0F;

    switch (type) {
        case HID_MSG_TYPE_CONTROL: {
            if (param == HID_CTRL_VIRTUAL_CABLE_UNPLUG) {
                uint8_t resp = HID_HANDSHAKE_SUCCESS;
                send(control_client_fd_, &resp, 1, 0);
                std::lock_guard<std::mutex> lock(state_mutex_);
                reset_connection_locked();
            } else {
                uint8_t resp = HID_HANDSHAKE_SUCCESS;
                send(control_client_fd_, &resp, 1, 0);
            }
            break;
        }
        case HID_MSG_TYPE_SET_PROTOCOL: {
            uint8_t new_mode = param & 0x01;
            {
                std::lock_guard<std::mutex> lock(state_mutex_);
                protocol_mode_ = new_mode;
            }
            uint8_t resp = HID_HANDSHAKE_SUCCESS;
            send(control_client_fd_, &resp, 1, 0);
            break;
        }
        case HID_MSG_TYPE_GET_PROTOCOL: {
            uint8_t response[2];
            response[0] = HID_MSG_TYPE_DATA | 0x03; // other report type
            {
                std::lock_guard<std::mutex> lock(state_mutex_);
                response[1] = protocol_mode_;
            }
            send(control_client_fd_, response, sizeof(response), 0);
            break;
        }
        case HID_MSG_TYPE_SET_REPORT: {
            uint8_t resp = HID_HANDSHAKE_SUCCESS;
            if (length > 1) {
                const uint8_t *payload = data + 1;
                std::size_t payload_len = length - 1;
                bool has_report_id = param & 0x08;
                uint8_t report_type = param & 0x03;
                uint8_t report_id = has_report_id && payload_len > 0 ? payload[0] : 0;
                if (has_report_id) {
                    if (payload_len > 0) {
                        payload++;
                        payload_len--;
                    }
                }
                if (report_type == 0x02 && payload_len > 0) { // output report
                    if (!has_report_id || report_id == kKeyboardReportId) {
                        std::lock_guard<std::mutex> lock(state_mutex_);
                        led_status_ = payload[0];
                    }
                }
            }
            send(control_client_fd_, &resp, 1, 0);
            break;
        }
        case HID_MSG_TYPE_GET_REPORT: {
            uint8_t resp = HID_HANDSHAKE_ERR_UNSUPPORTED;
            send(control_client_fd_, &resp, 1, 0);
            break;
        }
        case HID_MSG_TYPE_HANDSHAKE: {
            // Nothing to do; host acknowledges our previous response.
            break;
        }
        default: {
            uint8_t resp = HID_HANDSHAKE_SUCCESS;
            send(control_client_fd_, &resp, 1, 0);
            break;
        }
    }
}

bool HidServer::send_interrupt_packet(const uint8_t *data, std::size_t length) {
    std::unique_lock<std::mutex> lock(state_mutex_);
    if (!ensure_connection_locked(lock)) {
        return false;
    }
    int fd = interrupt_client_fd_;
    lock.unlock();

    ssize_t written = send(fd, data, length, 0);
    if (written < 0) {
        std::cerr << "[bthid] Failed to send interrupt report: " << std::strerror(errno) << std::endl;
        std::lock_guard<std::mutex> guard(state_mutex_);
        reset_connection_locked();
        return false;
    }
    return true;
}

bool HidServer::ensure_connection_locked(std::unique_lock<std::mutex> &lock) {
    if (!connected_) {
        if (!connected_cv_.wait_for(lock, std::chrono::seconds(30), [this]() { return !running_ || connected_; })) {
            std::cerr << "[bthid] Timeout waiting for host to connect" << std::endl;
            return false;
        }
    }
    return connected_;
}

void HidServer::reset_connection_locked() {
    close_client(control_client_fd_);
    close_client(interrupt_client_fd_);
    connected_ = false;
    protocol_mode_ = 1;
    led_status_ = 0;
}

void HidServer::close_client(int &fd) {
    if (fd >= 0) {
        close(fd);
        fd = -1;
    }
}

void HidServer::force_disconnect() {
    std::lock_guard<std::mutex> lock(state_mutex_);
    reset_connection_locked();
    connected_cv_.notify_all();
}
