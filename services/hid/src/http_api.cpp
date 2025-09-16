#include "http_api.hpp"

#include "hid_reports.hpp"

#include <yaml-cpp/yaml.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cstring>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <strings.h>

namespace {
std::string trim(std::string value)
{
    const auto notSpace = [](int ch) { return !std::isspace(static_cast<unsigned char>(ch)); };
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), notSpace));
    value.erase(std::find_if(value.rbegin(), value.rend(), notSpace).base(), value.end());
    return value;
}

std::string statusText(int status)
{
    switch (status) {
    case 200: return "OK";
    case 400: return "Bad Request";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 500: return "Internal Server Error";
    default: return "Error";
    }
}
} // namespace

HIDHttpApi::HIDHttpApi(BluetoothHIDServer& hid, const HIDConfig& config)
    : hid_(hid)
    , config_(config)
{
}

HIDHttpApi::~HIDHttpApi()
{
    stop();
}

void HIDHttpApi::start()
{
    if (running_) {
        return;
    }
    running_ = true;
    serverThread_ = std::thread([this]() { serverLoop(); });
}

void HIDHttpApi::stop()
{
    if (!running_) {
        return;
    }
    running_ = false;

    if (serverFd_ >= 0) {
        ::shutdown(serverFd_, SHUT_RDWR);
        ::close(serverFd_);
        serverFd_ = -1;
    }

    if (serverThread_.joinable()) {
        serverThread_.join();
    }
}

void HIDHttpApi::serverLoop()
{
    serverFd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (serverFd_ < 0) {
        std::cerr << "[hid] Failed to create server socket: " << std::strerror(errno) << std::endl;
        running_ = false;
        return;
    }

    int opt = 1;
    ::setsockopt(serverFd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(config_.http.port);
    if (config_.http.bindAddress == "0.0.0.0" || config_.http.bindAddress == "*") {
        addr.sin_addr.s_addr = INADDR_ANY;
    } else {
        if (::inet_pton(AF_INET, config_.http.bindAddress.c_str(), &addr.sin_addr) != 1) {
            std::cerr << "[hid] Invalid bind address: " << config_.http.bindAddress << std::endl;
            running_ = false;
            ::close(serverFd_);
            serverFd_ = -1;
            return;
        }
    }

    if (::bind(serverFd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        std::cerr << "[hid] Bind failed: " << std::strerror(errno) << std::endl;
        running_ = false;
        ::close(serverFd_);
        serverFd_ = -1;
        return;
    }

    if (::listen(serverFd_, 8) < 0) {
        std::cerr << "[hid] Listen failed: " << std::strerror(errno) << std::endl;
        running_ = false;
        ::close(serverFd_);
        serverFd_ = -1;
        return;
    }

    std::cout << "[hid] HTTP API listening on " << config_.http.bindAddress << ":" << config_.http.port << std::endl;

    while (running_) {
        sockaddr_in client{};
        socklen_t len = sizeof(client);
        const int clientFd = ::accept(serverFd_, reinterpret_cast<sockaddr*>(&client), &len);
        if (clientFd < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (running_) {
                std::cerr << "[hid] Accept failed: " << std::strerror(errno) << std::endl;
            }
            break;
        }

        handleClient(clientFd);
    }

    if (serverFd_ >= 0) {
        ::close(serverFd_);
        serverFd_ = -1;
    }

    running_ = false;
}

void HIDHttpApi::handleClient(int clientFd)
{
    std::string data;
    data.reserve(1024);

    char buffer[1024];
    ssize_t received = 0;
    while ((received = ::recv(clientFd, buffer, sizeof(buffer), 0)) > 0) {
        data.append(buffer, buffer + received);
        auto headerEnd = data.find("\r\n\r\n");
        if (headerEnd != std::string::npos) {
            // We have headers; ensure full body is read
            std::istringstream headerStream(data.substr(0, headerEnd));
            std::string requestLine;
            std::getline(headerStream, requestLine);
            if (!requestLine.empty() && requestLine.back() == '\r') {
                requestLine.pop_back();
            }

            std::map<std::string, std::string> headers;
            std::string line;
            size_t contentLength = 0;
            while (std::getline(headerStream, line)) {
                if (!line.empty() && line.back() == '\r') {
                    line.pop_back();
                }
                const auto colon = line.find(':');
                if (colon != std::string::npos) {
                    auto key = trim(line.substr(0, colon));
                    auto value = trim(line.substr(colon + 1));
                    headers[key] = value;
                    if (strcasecmp(key.c_str(), "Content-Length") == 0) {
                        try {
                            contentLength = static_cast<size_t>(std::stoul(value));
                        } catch (const std::exception&) {
                            contentLength = 0;
                        }
                    }
                }
            }

            std::string body = data.substr(headerEnd + 4);
            while (body.size() < contentLength) {
                received = ::recv(clientFd, buffer, sizeof(buffer), 0);
                if (received <= 0) {
                    break;
                }
                body.append(buffer, buffer + received);
            }

            std::istringstream requestLineStream(requestLine);
            std::string method;
            std::string target;
            std::string version;
            requestLineStream >> method >> target >> version;

            if (method == "GET" && target == "/healthz") {
                std::ostringstream bodyStream;
                bodyStream << "{\"status\":\"ok\",\"hid_running\":" << (hid_.isRunning() ? "true" : "false") << "}";
                sendResponse(clientFd, 200, statusText(200), bodyStream.str());
            } else if (method == "POST" && target == "/hid/text") {
                try {
                    const auto payload = YAML::Load(body);
                    const auto text = payload["text"].as<std::string>();
                    hid_.sendText(text);
                    sendResponse(clientFd, 200, statusText(200), buildJsonResponse("ok"));
                } catch (const std::exception& ex) {
                    sendResponse(clientFd, 400, statusText(400), buildJsonResponse("error", ex.what()));
                }
            } else if (method == "POST" && target == "/hid/click") {
                try {
                    const auto payload = YAML::Load(body);
                    const int x = payload["x"].as<int>();
                    const int y = payload["y"].as<int>();
                    const auto buttonName = payload["button"].IsDefined() ? payload["button"].as<std::string>() : std::string{"left"};
                    hid_.click(x, y, mouseButtonFromString(buttonName));
                    sendResponse(clientFd, 200, statusText(200), buildJsonResponse("ok"));
                } catch (const std::exception& ex) {
                    sendResponse(clientFd, 400, statusText(400), buildJsonResponse("error", ex.what()));
                }
            } else if (method == "POST" && target == "/hid/move") {
                try {
                    const auto payload = YAML::Load(body);
                    const int x = payload["x"].as<int>();
                    const int y = payload["y"].as<int>();
                    hid_.movePointer(x, y);
                    sendResponse(clientFd, 200, statusText(200), buildJsonResponse("ok"));
                } catch (const std::exception& ex) {
                    sendResponse(clientFd, 400, statusText(400), buildJsonResponse("error", ex.what()));
                }
            } else {
                sendResponse(clientFd, 404, statusText(404), buildJsonResponse("error", "Unknown endpoint"));
            }
            break;
        }
    }

    ::shutdown(clientFd, SHUT_RDWR);
    ::close(clientFd);
}

std::string HIDHttpApi::buildJsonResponse(const std::string& status, const std::string& detail) const
{
    std::ostringstream oss;
    oss << "{\"status\":\"" << status << "\"";
    if (!detail.empty()) {
        oss << ",\"detail\":\"";
        for (char ch : detail) {
            switch (ch) {
            case '"':
                oss << "\\\"";
                break;
            case '\\':
                oss << "\\\\";
                break;
            case '\n':
                oss << "\\n";
                break;
            case '\r':
                oss << "\\r";
                break;
            case '\t':
                oss << "\\t";
                break;
            default:
                oss << ch;
            }
        }
        oss << "\"";
    }
    oss << "}";
    return oss.str();
}

void HIDHttpApi::sendResponse(int clientFd, int statusCode, const std::string& reason, const std::string& body, const std::string& contentType) const
{
    std::ostringstream response;
    response << "HTTP/1.1 " << statusCode << ' ' << reason << "\r\n";
    response << "Content-Type: " << contentType << "\r\n";
    response << "Content-Length: " << body.size() << "\r\n";
    response << "Connection: close\r\n\r\n";
    response << body;

    const auto responseStr = response.str();
    ::send(clientFd, responseStr.data(), responseStr.size(), 0);
}
