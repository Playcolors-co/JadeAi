#include "command_server.h"

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cstring>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

std::string decode_escape_sequences(const std::string &input) {
    std::string output;
    output.reserve(input.size());
    for (std::size_t i = 0; i < input.size(); ++i) {
        char ch = input[i];
        if (ch == '\\' && i + 1 < input.size()) {
            char next = input[++i];
            switch (next) {
                case 'n':
                    output.push_back('\n');
                    break;
                case 'r':
                    output.push_back('\r');
                    break;
                case 't':
                    output.push_back('\t');
                    break;
                case '\\':
                    output.push_back('\\');
                    break;
                default:
                    output.push_back(next);
                    break;
            }
        } else {
            output.push_back(ch);
        }
    }
    return output;
}

} // namespace

CommandServer::CommandServer(HidServer &hid_server, ShutdownCallback shutdown_cb)
    : hid_(hid_server),
      shutdown_callback_(std::move(shutdown_cb)),
      listen_fd_(-1),
      running_(false) {}

CommandServer::~CommandServer() { stop(); }

void CommandServer::start() {
    if (running_)
        return;

    listen_fd_ = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listen_fd_ < 0) {
        throw std::runtime_error("Unable to create command socket");
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, kSocketPath, sizeof(addr.sun_path) - 1);
    ::unlink(addr.sun_path);

    if (bind(listen_fd_, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
        close(listen_fd_);
        listen_fd_ = -1;
        throw std::runtime_error("Failed to bind command socket");
    }

    if (listen(listen_fd_, 5) < 0) {
        close(listen_fd_);
        listen_fd_ = -1;
        throw std::runtime_error("Failed to listen on command socket");
    }

    running_ = true;
    thread_ = std::thread(&CommandServer::run, this);
}

void CommandServer::stop() {
    if (!running_ && listen_fd_ < 0)
        return;

    running_ = false;
    if (listen_fd_ >= 0) {
        close(listen_fd_);
        listen_fd_ = -1;
    }
    ::unlink(kSocketPath);

    if (thread_.joinable()) {
        thread_.join();
    }
}

void CommandServer::run() {
    while (running_) {
        sockaddr_un addr{};
        socklen_t len = sizeof(addr);
        int client_fd = accept(listen_fd_, reinterpret_cast<sockaddr *>(&addr), &len);
        if (client_fd < 0) {
            if (errno == EINTR)
                continue;
            if (!running_)
                break;
            std::cerr << "[bthid] Error accepting command connection: " << std::strerror(errno) << std::endl;
            continue;
        }

        handle_client(client_fd);
        close(client_fd);
    }
}

void CommandServer::handle_client(int client_fd) {
    std::string buffer;
    char chunk[256];
    while (true) {
        ssize_t received = recv(client_fd, chunk, sizeof(chunk), 0);
        if (received <= 0)
            break;
        buffer.append(chunk, received);
        if (buffer.find('\n') != std::string::npos)
            break;
    }

    if (buffer.empty())
        return;

    auto newline = buffer.find('\n');
    if (newline != std::string::npos) {
        buffer.erase(newline);
    }

    // Trim trailing carriage return if present
    if (!buffer.empty() && buffer.back() == '\r') {
        buffer.pop_back();
    }

    std::istringstream iss(buffer);
    std::string command;
    if (!(iss >> command)) {
        respond(client_fd, "ERR Missing command");
        return;
    }

    std::transform(command.begin(), command.end(), command.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });

    if (command == "TYPE") {
        std::string remaining;
        std::getline(iss, remaining);
        if (!remaining.empty() && remaining.front() == ' ')
            remaining.erase(0, 1);
        if (remaining.empty()) {
            respond(client_fd, "ERR Missing text");
            return;
        }
        std::string decoded = decode_escape_sequences(remaining);
        if (!hid_.type_text(decoded)) {
            respond(client_fd, "ERR Failed to type text");
            return;
        }
        respond(client_fd, "OK");
    } else if (command == "MOVE") {
        int dx = 0;
        int dy = 0;
        int wheel = 0;
        if (!(iss >> dx >> dy)) {
            respond(client_fd, "ERR MOVE requires X and Y");
            return;
        }
        if (iss >> wheel) {
            // wheel value provided optionally
        }
        if (!hid_.move_mouse(dx, dy, wheel)) {
            respond(client_fd, "ERR Failed to move mouse");
            return;
        }
        respond(client_fd, "OK");
    } else if (command == "CLICK") {
        std::string button;
        if (!(iss >> button)) {
            respond(client_fd, "ERR CLICK requires button");
            return;
        }
        std::transform(button.begin(), button.end(), button.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        uint8_t mask = 0;
        if (button == "left" || button == "button1") {
            mask = 0x01;
        } else if (button == "right" || button == "button2") {
            mask = 0x02;
        } else if (button == "middle" || button == "button3") {
            mask = 0x04;
        } else {
            respond(client_fd, "ERR Unknown button");
            return;
        }
        if (!hid_.click(mask)) {
            respond(client_fd, "ERR Failed to click");
            return;
        }
        respond(client_fd, "OK");
    } else if (command == "STATUS") {
        bool connected = hid_.is_connected();
        uint8_t protocol = hid_.current_protocol();
        uint8_t leds = hid_.led_state();
        std::ostringstream status;
        status << "{\"connected\":" << (connected ? "true" : "false")
               << ",\"protocol\":\"" << (protocol == 0 ? "boot" : "report") << "\""
               << ",\"led_state\":" << static_cast<int>(leds)
               << "}";
        respond(client_fd, "OK " + status.str());
    } else if (command == "SHUTDOWN") {
        respond(client_fd, "OK");
        if (shutdown_callback_) {
            shutdown_callback_();
        }
    } else if (command == "DISCONNECT") {
        hid_.force_disconnect();
        respond(client_fd, "OK");
    } else {
        respond(client_fd, "ERR Unknown command");
    }
}

void CommandServer::respond(int client_fd, const std::string &message) {
    std::string payload = message;
    if (payload.find('\n') == std::string::npos)
        payload.push_back('\n');
    ssize_t written = send(client_fd, payload.c_str(), payload.size(), 0);
    if (written < 0) {
        std::cerr << "[bthid] Failed to send response: " << std::strerror(errno) << std::endl;
    }
}
