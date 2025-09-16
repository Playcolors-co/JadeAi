#pragma once

#include "bluetooth_hid_server.hpp"
#include "hid_config.hpp"

#include <atomic>
#include <memory>
#include <thread>

class HIDHttpApi {
public:
    HIDHttpApi(BluetoothHIDServer& hid, const HIDConfig& config);
    ~HIDHttpApi();

    void start();
    void stop();

private:
    void serverLoop();
    void handleClient(int clientFd);
    std::string buildJsonResponse(const std::string& status, const std::string& detail = {}) const;
    void sendResponse(int clientFd, int statusCode, const std::string& reason, const std::string& body, const std::string& contentType = "application/json") const;

    BluetoothHIDServer& hid_;
    HIDConfig config_;
    std::thread serverThread_;
    std::atomic<bool> running_{false};
    int serverFd_{-1};
};
