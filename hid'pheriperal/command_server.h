#ifndef COMMAND_SERVER_H
#define COMMAND_SERVER_H

#include "hid_server.h"

#include <atomic>
#include <functional>
#include <string>
#include <thread>

class CommandServer {
public:
    using ShutdownCallback = std::function<void()>;
    static constexpr const char *kSocketPath = "/tmp/jadeai-bthid.sock";

    CommandServer(HidServer &hid_server, ShutdownCallback shutdown_cb);
    ~CommandServer();

    void start();
    void stop();

private:
    HidServer &hid_;
    ShutdownCallback shutdown_callback_;
    int listen_fd_;
    std::thread thread_;
    std::atomic<bool> running_;

    void run();
    void handle_client(int client_fd);
    void respond(int client_fd, const std::string &message);
};

#endif // COMMAND_SERVER_H
