#pragma once

#include "hid_config.hpp"
#include "hid_reports.hpp"

#include <memory>
#include <string>

class BluetoothHIDServer {
public:
    explicit BluetoothHIDServer(HIDConfig config);
    ~BluetoothHIDServer();

    void start();
    void stop();

    void sendText(const std::string& text);
    void click(int x, int y, MouseButton button = MouseButton::Left);
    void movePointer(int x, int y);

    [[nodiscard]] bool isRunning() const noexcept;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};
