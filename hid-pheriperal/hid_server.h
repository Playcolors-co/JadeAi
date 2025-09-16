#ifndef HID_SERVER_H
#define HID_SERVER_H

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

struct KeyboardReport {
    uint8_t modifiers{0};
    uint8_t reserved{0};
    uint8_t keys[6]{0, 0, 0, 0, 0, 0};
};

struct MouseReport {
    uint8_t buttons{0};
    int8_t dx{0};
    int8_t dy{0};
    int8_t wheel{0};
};

class HidServer {
public:
    HidServer();
    ~HidServer();

    void start();
    void stop();

    bool send_keyboard_report(const KeyboardReport &report);
    bool send_mouse_report(const MouseReport &report);

    bool type_text(const std::string &text);
    bool move_mouse(int dx, int dy, int wheel = 0);
    bool click(uint8_t button_mask);

    void force_disconnect();

    bool is_connected() const;
    uint8_t current_protocol() const;
    uint8_t led_state() const;

private:
    int control_listen_fd_;
    int interrupt_listen_fd_;
    int control_client_fd_;
    int interrupt_client_fd_;

    std::thread accept_thread_;
    std::thread control_thread_;

    mutable std::mutex state_mutex_;
    std::condition_variable connected_cv_;
    std::atomic<bool> running_;
    bool connected_;
    uint8_t protocol_mode_;
    uint8_t led_status_;

    void accept_loop();
    void control_loop();
    void handle_control_message(const uint8_t *data, std::size_t length);

    bool send_interrupt_packet(const uint8_t *data, std::size_t length);
    bool ensure_connection_locked(std::unique_lock<std::mutex> &lock);
    void reset_connection_locked();
    void close_client(int &fd);
};

#endif // HID_SERVER_H
