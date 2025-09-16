#include "bluetooth_manager.h"
#include "command_server.h"
#include "hid_report_map.h"
#include "hid_server.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <csignal>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <mutex>
#include <sstream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>

namespace {
std::atomic<bool> g_signal_shutdown{false};

void signal_handler(int) {
    g_signal_shutdown.store(true);
}

std::string escape_text(const std::string &input) {
    std::string output;
    output.reserve(input.size());
    for (char ch : input) {
        switch (ch) {
            case '\\':
                output.append("\\\\");
                break;
            case '\n':
                output.append("\\n");
                break;
            case '\r':
                output.append("\\r");
                break;
            case '\t':
                output.append("\\t");
                break;
            default:
                output.push_back(ch);
                break;
        }
    }
    return output;
}

int send_command(const std::string &command_line) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        std::cerr << "Unable to open command socket: " << std::strerror(errno) << std::endl;
        return 1;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, CommandServer::kSocketPath, sizeof(addr.sun_path) - 1);
    if (connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
        std::cerr << "Unable to connect to HID daemon: " << std::strerror(errno) << std::endl;
        close(fd);
        return 1;
    }

    std::string payload = command_line;
    if (payload.find('\n') == std::string::npos)
        payload.push_back('\n');
    if (send(fd, payload.c_str(), payload.size(), 0) < 0) {
        std::cerr << "Failed to send command: " << std::strerror(errno) << std::endl;
        close(fd);
        return 1;
    }

    std::string response;
    char buffer[256];
    while (true) {
        ssize_t received = recv(fd, buffer, sizeof(buffer), 0);
        if (received <= 0)
            break;
        response.append(buffer, received);
        if (response.find('\n') != std::string::npos)
            break;
    }
    close(fd);

    if (response.empty()) {
        std::cerr << "No response from daemon" << std::endl;
        return 1;
    }
    auto newline = response.find('\n');
    if (newline != std::string::npos)
        response.erase(newline);
    if (response.rfind("OK", 0) == 0) {
        std::string rest = response.substr(2);
        if (!rest.empty() && rest.front() == ' ')
            rest.erase(0, 1);
        if (!rest.empty())
            std::cout << rest << std::endl;
        return 0;
    }
    if (response.rfind("ERR", 0) == 0) {
        std::string message = response.substr(3);
        if (!message.empty() && message.front() == ' ')
            message.erase(0, 1);
        std::cerr << message << std::endl;
        return 1;
    }
    std::cout << response << std::endl;
    return 0;
}

void print_usage(const char *program) {
    std::cerr << "Usage: " << program << " --daemon | type <text> | move <dx> <dy> [wheel] | click <button> | status | shutdown" << std::endl;
}

int run_daemon() {
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    try {
        BluetoothManager bt_manager;
        bt_manager.initialize("JadeAI HID");

        SdpRegistrar registrar;
        registrar.register_hid_service(hid_report_descriptor, sizeof(hid_report_descriptor));

        HidServer hid_server;
        hid_server.start();

        std::mutex shutdown_mutex;
        std::condition_variable shutdown_cv;
        bool exit_requested = false;

        CommandServer command_server(hid_server, [&]() {
            {
                std::lock_guard<std::mutex> lock(shutdown_mutex);
                exit_requested = true;
            }
            shutdown_cv.notify_all();
        });
        command_server.start();

        {
            std::unique_lock<std::mutex> lock(shutdown_mutex);
            while (!exit_requested && !g_signal_shutdown.load()) {
                shutdown_cv.wait_for(lock, std::chrono::milliseconds(250));
            }
        }

        command_server.stop();
        hid_server.stop();
        registrar.unregister();
        bt_manager.teardown();
    } catch (const std::exception &ex) {
        std::cerr << "[bthid] Fatal error: " << ex.what() << std::endl;
        return 1;
    }
    return 0;
}

} // namespace

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    std::string command = argv[1];
    if (command == "--daemon") {
        return run_daemon();
    }

    if (command == "type") {
        if (argc < 3) {
            std::cerr << "type command requires text" << std::endl;
            return 1;
        }
        std::ostringstream oss;
        for (int i = 2; i < argc; ++i) {
            if (i > 2)
                oss << ' ';
            oss << argv[i];
        }
        return send_command("TYPE " + escape_text(oss.str()));
    }

    if (command == "move") {
        if (argc < 4) {
            std::cerr << "move command requires dx and dy" << std::endl;
            return 1;
        }
        std::ostringstream oss;
        oss << "MOVE " << argv[2] << ' ' << argv[3];
        if (argc >= 5) {
            oss << ' ' << argv[4];
        }
        return send_command(oss.str());
    }

    if (command == "click") {
        if (argc < 3) {
            std::cerr << "click command requires button" << std::endl;
            return 1;
        }
        std::ostringstream oss;
        oss << "CLICK " << argv[2];
        return send_command(oss.str());
    }

    if (command == "status") {
        return send_command("STATUS");
    }

    if (command == "shutdown") {
        return send_command("SHUTDOWN");
    }

    print_usage(argv[0]);
    return 1;
}
