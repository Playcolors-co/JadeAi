#include "bluetooth_hid_server.hpp"
#include "hid_config.hpp"
#include "http_api.hpp"

#include <atomic>
#include <csignal>
#include <cstdlib>
#include <exception>
#include <future>
#include <iostream>

namespace {
std::promise<void> shutdownPromise;
std::atomic<bool> signalHandled{false};

void handleSignal(int)
{
    if (!signalHandled.exchange(true)) {
        shutdownPromise.set_value();
    }
}
} // namespace

int main(int argc, char** argv)
{
    (void)argc;
    (void)argv;

    try {
        std::string configPath = "/app/config/hid.yml";
        if (const char* envPath = std::getenv("JADEAI_HID_CONFIG")) {
            configPath = envPath;
        }

        auto config = loadHIDConfig(configPath);

        BluetoothHIDServer hid(config);
        hid.start();

        HIDHttpApi httpServer(hid, config);
        httpServer.start();

        std::signal(SIGINT, handleSignal);
        std::signal(SIGTERM, handleSignal);

        shutdownPromise.get_future().wait();

        httpServer.stop();
        hid.stop();

    } catch (const std::exception& ex) {
        std::cerr << "[hid] Fatal error: " << ex.what() << std::endl;
        return 1;
    }

    return 0;
}
