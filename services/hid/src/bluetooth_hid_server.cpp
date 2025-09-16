#include "bluetooth_hid_server.hpp"

#include "hid_reports.hpp"

#include <sdbus-c++/sdbus-c++.h>

#include <algorithm>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <utility>
#include <vector>

namespace {

constexpr std::string_view kBluezService{"org.bluez"};
constexpr std::string_view kPropertiesInterface{"org.freedesktop.DBus.Properties"};
constexpr std::string_view kObjectManagerInterface{"org.freedesktop.DBus.ObjectManager"};
constexpr std::string_view kGattManagerInterface{"org.bluez.GattManager1"};
constexpr std::string_view kLEAdvertisingManagerInterface{"org.bluez.LEAdvertisingManager1"};
constexpr std::string_view kAdapterInterface{"org.bluez.Adapter1"};
constexpr std::string_view kGattServiceInterface{"org.bluez.GattService1"};
constexpr std::string_view kGattCharacteristicInterface{"org.bluez.GattCharacteristic1"};
constexpr std::string_view kGattDescriptorInterface{"org.bluez.GattDescriptor1"};
constexpr std::string_view kLEAdvertisementInterface{"org.bluez.LEAdvertisement1"};

constexpr std::string_view kAppRoot{ "/org/jadeai/hid" };
constexpr std::string_view kServicePath{ "/org/jadeai/hid/service0" };
constexpr std::string_view kHidInfoPath{ "/org/jadeai/hid/service0/char0" };
constexpr std::string_view kReportMapPath{ "/org/jadeai/hid/service0/char1" };
constexpr std::string_view kControlPointPath{ "/org/jadeai/hid/service0/char2" };
constexpr std::string_view kProtocolModePath{ "/org/jadeai/hid/service0/char3" };
constexpr std::string_view kKeyboardInputReportPath{ "/org/jadeai/hid/service0/char4" };
constexpr std::string_view kKeyboardInputReportRefPath{ "/org/jadeai/hid/service0/char4/desc0" };
constexpr std::string_view kMouseInputReportPath{ "/org/jadeai/hid/service0/char5" };
constexpr std::string_view kMouseInputReportRefPath{ "/org/jadeai/hid/service0/char5/desc0" };
constexpr std::string_view kBootKeyboardInputPath{ "/org/jadeai/hid/service0/char6" };
constexpr std::string_view kBootMouseInputPath{ "/org/jadeai/hid/service0/char7" };

constexpr std::string_view kDeviceInfoServicePath{ "/org/jadeai/hid/service1" };
constexpr std::string_view kManufacturerCharPath{ "/org/jadeai/hid/service1/char0" };
constexpr std::string_view kPnPIdCharPath{ "/org/jadeai/hid/service1/char1" };

constexpr std::string_view kAdvertisementPath{ "/org/jadeai/hid/advertisement0" };

constexpr std::string_view kHidServiceUuid{ "00001812-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kDeviceInfoServiceUuid{ "0000180a-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kHidInfoUuid{ "00002a4a-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kReportMapUuid{ "00002a4b-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kControlPointUuid{ "00002a4c-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kProtocolModeUuid{ "00002a4e-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kReportUuid{ "00002a4d-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kReportReferenceUuid{ "00002908-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kBootKeyboardInputUuid{ "00002a22-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kBootMouseInputUuid{ "00002a33-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kManufacturerNameUuid{ "00002a29-0000-1000-8000-00805f9b34fb" };
constexpr std::string_view kPnPIdUuid{ "00002a50-0000-1000-8000-00805f9b34fb" };

constexpr uint8_t kProtocolBootMode = 0x00;
constexpr uint8_t kProtocolReportMode = 0x01;

std::vector<uint8_t> hidReportMap()
{
    // Keyboard (Report ID 1) + Mouse (Report ID 2)
    return {
        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x06,       // Usage (Keyboard)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x01,       //   Report ID (1)
        0x05, 0x07,       //   Usage Page (Key Codes)
        0x19, 0xE0,
        0x29, 0xE7,
        0x15, 0x00,
        0x25, 0x01,
        0x75, 0x01,
        0x95, 0x08,
        0x81, 0x02,       //   Input (Data, Var, Abs) Modifier byte
        0x95, 0x01,
        0x75, 0x08,
        0x81, 0x01,       //   Input (Const) Reserved
        0x95, 0x06,
        0x75, 0x08,
        0x15, 0x00,
        0x25, 0x65,
        0x05, 0x07,
        0x19, 0x00,
        0x29, 0x65,
        0x81, 0x00,       //   Input (Data, Array)
        0xC0,             // End Collection

        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x02,       // Usage (Mouse)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x02,       //   Report ID (2)
        0x09, 0x01,       //   Usage (Pointer)
        0xA1, 0x00,       //   Collection (Physical)
        0x05, 0x09,       //     Usage Page (Buttons)
        0x19, 0x01,
        0x29, 0x03,
        0x15, 0x00,
        0x25, 0x01,
        0x95, 0x03,
        0x75, 0x01,
        0x81, 0x02,       //     Input (Data, Var, Abs)
        0x95, 0x01,
        0x75, 0x05,
        0x81, 0x01,       //     Input (Const)
        0x05, 0x01,
        0x09, 0x30,       //     Usage (X)
        0x09, 0x31,       //     Usage (Y)
        0x09, 0x38,       //     Usage (Wheel)
        0x15, 0x81,       //     Logical minimum (-127)
        0x25, 0x7F,       //     Logical maximum (127)
        0x75, 0x08,
        0x95, 0x03,
        0x81, 0x06,       //     Input (Data, Var, Rel)
        0xC0,
        0xC0
    };
}

std::vector<uint8_t> hidInformation()
{
    return {0x11, 0x01, 0x00, 0x02}; // bcdHID 1.11, country 0, flags: remote wake + normally connectable
}

std::vector<uint8_t> makePnPId()
{
    // Vendor ID Source (0x02: USB), Vendor ID, Product ID, Product Version
    return {0x02, 0xD4, 0x04, 0x34, 0x12, 0x01, 0x00};
}

class ManagedObject {
public:
    virtual ~ManagedObject() = default;
    virtual const std::string& path() const = 0;
    virtual std::map<std::string, std::map<std::string, sdbus::Variant>> properties() const = 0;
};

class GattDescriptor : public ManagedObject, public std::enable_shared_from_this<GattDescriptor> {
public:
    GattDescriptor(sdbus::IConnection& connection,
                   std::string path,
                   std::string uuid,
                   std::string characteristicPath,
                   std::vector<std::string> flags,
                   std::vector<uint8_t> value)
        : path_(std::move(path))
        , uuid_(std::move(uuid))
        , characteristicPath_(std::move(characteristicPath))
        , flags_(std::move(flags))
        , value_(std::move(value))
        , object_(sdbus::createObject(connection, path_))
    {
        object_->registerMethod("ReadValue")
            .onInterface(kGattDescriptorInterface.data())
            .withInputParamNames("options")
            .withOutputParamNames("value")
            .implementedAs([this](const std::map<std::string, sdbus::Variant>&) {
                return value_;
            });

        object_->registerProperty("UUID")
            .onInterface(kGattDescriptorInterface.data())
            .withGetter([this]() { return uuid_; });

        object_->registerProperty("Characteristic")
            .onInterface(kGattDescriptorInterface.data())
            .withGetter([this]() { return sdbus::ObjectPath{characteristicPath_}; });

        object_->registerProperty("Value")
            .onInterface(kGattDescriptorInterface.data())
            .withGetter([this]() { return value_; });

        object_->registerProperty("Flags")
            .onInterface(kGattDescriptorInterface.data())
            .withGetter([this]() { return flags_; });

        object_->finishRegistration();
    }

    const std::string& path() const override { return path_; }

    std::map<std::string, std::map<std::string, sdbus::Variant>> properties() const override
    {
        std::map<std::string, sdbus::Variant> props;
        props.insert({"UUID", uuid_});
        props.insert({"Characteristic", sdbus::ObjectPath{characteristicPath_}});
        props.insert({"Value", value_});
        props.insert({"Flags", flags_});
        return {{std::string{kGattDescriptorInterface}, std::move(props)}};
    }

private:
    std::string path_;
    std::string uuid_;
    std::string characteristicPath_;
    std::vector<std::string> flags_;
    std::vector<uint8_t> value_;
    std::unique_ptr<sdbus::IObject> object_;
};

class GattCharacteristic : public ManagedObject, public std::enable_shared_from_this<GattCharacteristic> {
public:
    using ReadHandler = std::function<std::vector<uint8_t>(const std::map<std::string, sdbus::Variant>&)>;
    using WriteHandler = std::function<void(const std::vector<uint8_t>&, const std::map<std::string, sdbus::Variant>&)>;
    using NotifyHandler = std::function<void(bool)>;

    GattCharacteristic(sdbus::IConnection& connection,
                       std::string path,
                       std::string uuid,
                       std::string servicePath,
                       std::vector<std::string> flags,
                       ReadHandler readHandler,
                       WriteHandler writeHandler,
                       NotifyHandler notifyHandler)
        : connection_(connection)
        , path_(std::move(path))
        , uuid_(std::move(uuid))
        , servicePath_(std::move(servicePath))
        , flags_(std::move(flags))
        , readHandler_(std::move(readHandler))
        , writeHandler_(std::move(writeHandler))
        , notifyHandler_(std::move(notifyHandler))
        , object_(sdbus::createObject(connection, path_))
    {
        object_->registerMethod("ReadValue")
            .onInterface(kGattCharacteristicInterface.data())
            .withInputParamNames("options")
            .withOutputParamNames("value")
            .implementedAs([this](const std::map<std::string, sdbus::Variant>& options) {
                if (readHandler_) {
                    return readHandler_(options);
                }
                std::lock_guard<std::mutex> lock(valueMutex_);
                return value_;
            });

        object_->registerMethod("WriteValue")
            .onInterface(kGattCharacteristicInterface.data())
            .withInputParamNames("value", "options")
            .implementedAs([this](const std::vector<uint8_t>& value, const std::map<std::string, sdbus::Variant>& options) {
                if (writeHandler_) {
                    writeHandler_(value, options);
                } else {
                    std::lock_guard<std::mutex> lock(valueMutex_);
                    value_ = value;
                }
            });

        object_->registerMethod("StartNotify")
            .onInterface(kGattCharacteristicInterface.data())
            .implementedAs([this]() {
                notifying_ = true;
                if (notifyHandler_) {
                    notifyHandler_(true);
                }
            });

        object_->registerMethod("StopNotify")
            .onInterface(kGattCharacteristicInterface.data())
            .implementedAs([this]() {
                notifying_ = false;
                if (notifyHandler_) {
                    notifyHandler_(false);
                }
            });

        object_->registerProperty("UUID")
            .onInterface(kGattCharacteristicInterface.data())
            .withGetter([this]() { return uuid_; });

        object_->registerProperty("Service")
            .onInterface(kGattCharacteristicInterface.data())
            .withGetter([this]() { return sdbus::ObjectPath{servicePath_}; });

        object_->registerProperty("Flags")
            .onInterface(kGattCharacteristicInterface.data())
            .withGetter([this]() { return flags_; });

        object_->registerProperty("Descriptors")
            .onInterface(kGattCharacteristicInterface.data())
            .withGetter([this]() { return descriptorPaths_; });

        object_->registerProperty("Value")
            .onInterface(kGattCharacteristicInterface.data())
            .withGetter([this]() {
                std::lock_guard<std::mutex> lock(valueMutex_);
                return value_;
            });

        object_->finishRegistration();
    }

    const std::string& path() const override { return path_; }

    std::map<std::string, std::map<std::string, sdbus::Variant>> properties() const override
    {
        std::map<std::string, sdbus::Variant> props;
        props.insert({"UUID", uuid_});
        props.insert({"Service", sdbus::ObjectPath{servicePath_}});
        props.insert({"Flags", flags_});
        props.insert({"Descriptors", descriptorPaths_});
        {
            std::lock_guard<std::mutex> lock(valueMutex_);
            props.insert({"Value", value_});
        }
        return {{std::string{kGattCharacteristicInterface}, std::move(props)}};
    }

    void setInitialValue(const std::vector<uint8_t>& value)
    {
        std::lock_guard<std::mutex> lock(valueMutex_);
        value_ = value;
    }

    void addDescriptor(const std::shared_ptr<GattDescriptor>& descriptor)
    {
        descriptors_.push_back(descriptor);
        descriptorPaths_.push_back(sdbus::ObjectPath{descriptor->path()});
    }

    void updateValue(const std::vector<uint8_t>& value, bool notify)
    {
        {
            std::lock_guard<std::mutex> lock(valueMutex_);
            value_ = value;
        }
        if (notify && notifying_) {
            auto signal = object_->createSignal(kPropertiesInterface.data(), "PropertiesChanged");
            std::map<std::string, sdbus::Variant> changed;
            changed.insert({"Value", value});
            std::vector<std::string> invalidated;
            signal << std::string{kGattCharacteristicInterface} << changed << invalidated;
            object_->emitSignal(signal);
        }
    }

    void notifyValue(const std::vector<uint8_t>& value)
    {
        updateValue(value, true);
    }

    bool notifying() const { return notifying_; }

private:
    sdbus::IConnection& connection_;
    std::string path_;
    std::string uuid_;
    std::string servicePath_;
    std::vector<std::string> flags_;
    ReadHandler readHandler_;
    WriteHandler writeHandler_;
    NotifyHandler notifyHandler_;
    std::unique_ptr<sdbus::IObject> object_;

    std::vector<sdbus::ObjectPath> descriptorPaths_;
    std::vector<std::weak_ptr<GattDescriptor>> descriptors_;

    mutable std::mutex valueMutex_;
    std::vector<uint8_t> value_;
    std::atomic<bool> notifying_{false};
};

class GattService : public ManagedObject, public std::enable_shared_from_this<GattService> {
public:
    GattService(sdbus::IConnection& connection,
                std::string path,
                std::string uuid,
                bool primary)
        : path_(std::move(path))
        , uuid_(std::move(uuid))
        , primary_(primary)
        , object_(sdbus::createObject(connection, path_))
    {
        object_->registerProperty("UUID")
            .onInterface(kGattServiceInterface.data())
            .withGetter([this]() { return uuid_; });

        object_->registerProperty("Primary")
            .onInterface(kGattServiceInterface.data())
            .withGetter([this]() { return primary_; });

        object_->registerProperty("Includes")
            .onInterface(kGattServiceInterface.data())
            .withGetter([this]() { return includes_; });

        object_->finishRegistration();
    }

    const std::string& path() const override { return path_; }

    std::map<std::string, std::map<std::string, sdbus::Variant>> properties() const override
    {
        std::map<std::string, sdbus::Variant> props;
        props.insert({"UUID", uuid_});
        props.insert({"Primary", primary_});
        props.insert({"Includes", includes_});
        return {{std::string{kGattServiceInterface}, std::move(props)}};
    }

private:
    std::string path_;
    std::string uuid_;
    bool primary_;
    std::vector<sdbus::ObjectPath> includes_;
    std::unique_ptr<sdbus::IObject> object_;
};

class Advertisement {
public:
    Advertisement(sdbus::IConnection& connection, const HIDConfig& config)
        : config_(config)
        , object_(sdbus::createObject(connection, std::string{kAdvertisementPath}))
    {
        object_->registerMethod("Release")
            .onInterface(kLEAdvertisementInterface.data())
            .implementedAs([]() {});

        object_->registerProperty("Type")
            .onInterface(kLEAdvertisementInterface.data())
            .withGetter([]() { return std::string{"peripheral"}; });

        object_->registerProperty("ServiceUUIDs")
            .onInterface(kLEAdvertisementInterface.data())
            .withGetter([]() {
                return std::vector<std::string>{std::string{kHidServiceUuid}, std::string{kDeviceInfoServiceUuid}};
            });

        object_->registerProperty("LocalName")
            .onInterface(kLEAdvertisementInterface.data())
            .withGetter([this]() { return config_.device.deviceName; });

        object_->registerProperty("Appearance")
            .onInterface(kLEAdvertisementInterface.data())
            .withGetter([this]() { return config_.device.appearance; });

        object_->registerProperty("Includes")
            .onInterface(kLEAdvertisementInterface.data())
            .withGetter([]() { return std::vector<std::string>{}; });

        object_->registerProperty("Discoverable")
            .onInterface(kLEAdvertisementInterface.data())
            .withGetter([]() { return true; });

        object_->finishRegistration();
    }

    const std::string& path() const { return path_; }

private:
    HIDConfig config_;
    std::string path_{std::string{kAdvertisementPath}};
    std::unique_ptr<sdbus::IObject> object_;
};

std::vector<uint8_t> toVector(const std::array<uint8_t, 9>& array)
{
    return std::vector<uint8_t>(array.begin(), array.end());
}

std::vector<uint8_t> toVector(const std::array<uint8_t, 5>& array)
{
    return std::vector<uint8_t>(array.begin(), array.end());
}

} // namespace

class BluetoothHIDServer::Impl {
public:
    explicit Impl(HIDConfig config)
        : config_(std::move(config))
    {
    }

    ~Impl()
    {
        stop();
    }

    void start()
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        if (running_) {
            return;
        }

        connection_ = sdbus::createSystemBusConnection();
        connection_->requestName("io.jadeai.hid");

        setupApplication();
        setupAdvertisement();
        registerWithBlueZ();

        running_ = true;
        eventThread_ = std::thread([this]() {
            try {
                connection_->enterEventLoop();
            } catch (const std::exception& ex) {
                std::cerr << "[hid] D-Bus event loop terminated: " << ex.what() << std::endl;
            }
        });
    }

    void stop()
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        if (!running_) {
            return;
        }

        try {
            unregisterFromBlueZ();
        } catch (const std::exception& ex) {
            std::cerr << "[hid] Failed to unregister from BlueZ: " << ex.what() << std::endl;
        }

        if (connection_) {
            connection_->leaveEventLoop();
        }
        if (eventThread_.joinable()) {
            eventThread_.join();
        }

        advertisement_.reset();
        managedObjects_.clear();
        appRoot_.reset();
        connection_.reset();

        running_ = false;
    }

    bool isRunning() const noexcept
    {
        return running_;
    }

    void sendText(const std::string& text)
    {
        if (!config_.keyboard.enabled) {
            throw std::runtime_error("Keyboard input is disabled in configuration");
        }
        std::lock_guard<std::mutex> lock(executionMutex_);
        for (char ch : text) {
            if (ch == '\r') {
                continue; // treat CR as newline handled by '\n'
            }
            auto stroke = lookupKeyboardStroke(ch);
            if (!stroke) {
                std::cerr << "[hid] Unsupported character: '" << ch << "'" << std::endl;
                continue;
            }
            auto report = makeKeyboardReport(stroke->modifiers, stroke->usage);
            keyboardInput_->notifyValue(toVector(report));
            bootKeyboardInput_->notifyValue(std::vector<uint8_t>(report.begin() + 1, report.end()));
            std::this_thread::sleep_for(std::chrono::milliseconds(config_.safety.keypressDelayMs));
            keyboardInput_->notifyValue(toVector(makeKeyboardReleaseReport()));
            bootKeyboardInput_->notifyValue(std::vector<uint8_t>(makeKeyboardReleaseReport().begin() + 1,
                                                                 makeKeyboardReleaseReport().end()));
            std::this_thread::sleep_for(std::chrono::milliseconds(config_.safety.keypressDelayMs));
        }
    }

    void movePointer(int x, int y)
    {
        if (!config_.mouse.enabled) {
            throw std::runtime_error("Mouse input is disabled in configuration");
        }
        std::lock_guard<std::mutex> lock(executionMutex_);
        movePointerInternal(x, y);
    }

    void click(int x, int y, MouseButton button)
    {
        if (!config_.mouse.enabled) {
            throw std::runtime_error("Mouse input is disabled in configuration");
        }
        std::lock_guard<std::mutex> lock(executionMutex_);
        movePointerInternal(x, y);
        sendMouseButton(button, true);
        std::this_thread::sleep_for(std::chrono::milliseconds(config_.safety.mouseMoveDelayMs));
        sendMouseButton(button, false);
    }

private:
    void setupApplication()
    {
        appRoot_ = sdbus::createObject(*connection_, std::string{kAppRoot});
        appRoot_->registerMethod("GetManagedObjects")
            .onInterface(kObjectManagerInterface.data())
            .withOutputParamNames("objects")
            .implementedAs([this]() {
                std::map<sdbus::ObjectPath, std::map<std::string, std::map<std::string, sdbus::Variant>>> managed;
                for (const auto& obj : managedObjects_) {
                    managed.insert({sdbus::ObjectPath{obj->path()}, obj->properties()});
                }
                return managed;
            });

        auto hidService = std::make_shared<GattService>(*connection_, std::string{kServicePath}, std::string{kHidServiceUuid}, true);
        managedObjects_.push_back(hidService);

        hidInformation_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kHidInfoPath}, std::string{kHidInfoUuid}, std::string{kServicePath}, std::vector<std::string>{"read"}, nullptr, nullptr, nullptr);
        hidInformation_->setInitialValue(hidInformation());
        managedObjects_.push_back(hidInformation_);

        reportMap_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kReportMapPath}, std::string{kReportMapUuid}, std::string{kServicePath}, std::vector<std::string>{"read"}, nullptr, nullptr, nullptr);
        reportMap_->setInitialValue(hidReportMap());
        managedObjects_.push_back(reportMap_);

        controlPoint_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kControlPointPath}, std::string{kControlPointUuid}, std::string{kServicePath}, std::vector<std::string>{"write-without-response"}, nullptr,
                                                             [this](const std::vector<uint8_t>& value, const std::map<std::string, sdbus::Variant>&) {
                                                                 if (!value.empty()) {
                                                                     controlPointValue_ = value[0];
                                                                 }
                                                             },
                                                             nullptr);
        controlPoint_->setInitialValue({0x00});
        managedObjects_.push_back(controlPoint_);

        protocolMode_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kProtocolModePath}, std::string{kProtocolModeUuid}, std::string{kServicePath}, std::vector<std::string>{"read", "write-without-response"},
                                                             nullptr,
                                                             [this](const std::vector<uint8_t>& value, const std::map<std::string, sdbus::Variant>&) {
                                                                 if (!value.empty()) {
                                                                     protocolModeValue_ = value[0];
                                                                 }
                                                             },
                                                             nullptr);
        protocolMode_->setInitialValue({kProtocolReportMode});
        managedObjects_.push_back(protocolMode_);

        keyboardInput_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kKeyboardInputReportPath}, std::string{kReportUuid}, std::string{kServicePath}, std::vector<std::string>{"read", "notify"}, nullptr, nullptr, nullptr);
        keyboardInput_->setInitialValue(toVector(makeKeyboardReleaseReport()));
        managedObjects_.push_back(keyboardInput_);

        auto keyboardReportRef = std::make_shared<GattDescriptor>(*connection_, std::string{kKeyboardInputReportRefPath}, std::string{kReportReferenceUuid}, std::string{kKeyboardInputReportPath}, std::vector<std::string>{"read"}, std::vector<uint8_t>{0x01, 0x01});
        keyboardInput_->addDescriptor(keyboardReportRef);
        managedObjects_.push_back(keyboardReportRef);

        mouseInput_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kMouseInputReportPath}, std::string{kReportUuid}, std::string{kServicePath}, std::vector<std::string>{"read", "notify"}, nullptr, nullptr, nullptr);
        mouseInput_->setInitialValue(toVector(makeMouseReport(0x00, 0x00, 0x00)));
        managedObjects_.push_back(mouseInput_);

        auto mouseReportRef = std::make_shared<GattDescriptor>(*connection_, std::string{kMouseInputReportRefPath}, std::string{kReportReferenceUuid}, std::string{kMouseInputReportPath}, std::vector<std::string>{"read"}, std::vector<uint8_t>{0x02, 0x01});
        mouseInput_->addDescriptor(mouseReportRef);
        managedObjects_.push_back(mouseReportRef);

        bootKeyboardInput_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kBootKeyboardInputPath}, std::string{kBootKeyboardInputUuid}, std::string{kServicePath}, std::vector<std::string>{"read", "notify"}, nullptr, nullptr, nullptr);
        bootKeyboardInput_->setInitialValue(std::vector<uint8_t>(makeKeyboardReleaseReport().begin() + 1, makeKeyboardReleaseReport().end()));
        managedObjects_.push_back(bootKeyboardInput_);

        bootMouseInput_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kBootMouseInputPath}, std::string{kBootMouseInputUuid}, std::string{kServicePath}, std::vector<std::string>{"read", "notify"}, nullptr, nullptr, nullptr);
        bootMouseInput_->setInitialValue({0x00, 0x00, 0x00});
        managedObjects_.push_back(bootMouseInput_);

        auto deviceInfoService = std::make_shared<GattService>(*connection_, std::string{kDeviceInfoServicePath}, std::string{kDeviceInfoServiceUuid}, true);
        managedObjects_.push_back(deviceInfoService);

        manufacturer_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kManufacturerCharPath}, std::string{kManufacturerNameUuid}, std::string{kDeviceInfoServicePath}, std::vector<std::string>{"read"},
                                                              [this](const std::map<std::string, sdbus::Variant>&) {
                                                                  std::vector<uint8_t> value(config_.device.manufacturer.begin(), config_.device.manufacturer.end());
                                                                  return value;
                                                              },
                                                              nullptr, nullptr);
        managedObjects_.push_back(manufacturer_);

        pnpId_ = std::make_shared<GattCharacteristic>(*connection_, std::string{kPnPIdCharPath}, std::string{kPnPIdUuid}, std::string{kDeviceInfoServicePath}, std::vector<std::string>{"read"},
                                                       [](const std::map<std::string, sdbus::Variant>&) { return makePnPId(); }, nullptr, nullptr);
        managedObjects_.push_back(pnpId_);

        appRoot_->finishRegistration();
    }

    void setupAdvertisement()
    {
        advertisement_ = std::make_unique<Advertisement>(*connection_, config_);
    }

    void registerWithBlueZ()
    {
        auto adapterPath = config_.adapterPath();

        auto adapterProxy = sdbus::createProxy(*connection_, std::string{kBluezService}, adapterPath);
        try {
            sdbus::Variant powered = true;
            adapterProxy->callMethod("Set")
                .onInterface(kPropertiesInterface.data())
                .withArguments(std::string{kAdapterInterface}, std::string{"Powered"}, powered);
        } catch (const std::exception& ex) {
            std::cerr << "[hid] Unable to power adapter: " << ex.what() << std::endl;
        }

        gattManager_ = sdbus::createProxy(*connection_, std::string{kBluezService}, adapterPath);
        auto options = std::map<std::string, sdbus::Variant>{};
        gattManager_->callMethod("RegisterApplication")
            .onInterface(kGattManagerInterface.data())
            .withArguments(std::string{kAppRoot}, options);

        advertisingManager_ = sdbus::createProxy(*connection_, std::string{kBluezService}, adapterPath);
        advertisingManager_->callMethod("RegisterAdvertisement")
            .onInterface(kLEAdvertisingManagerInterface.data())
            .withArguments(std::string{kAdvertisementPath}, options);
    }

    void unregisterFromBlueZ()
    {
        auto adapterPath = config_.adapterPath();
        auto options = std::map<std::string, sdbus::Variant>{};
        if (gattManager_) {
            try {
                gattManager_->callMethod("UnregisterApplication")
                    .onInterface(kGattManagerInterface.data())
                    .withArguments(std::string{kAppRoot});
            } catch (const std::exception& ex) {
                std::cerr << "[hid] UnregisterApplication failed: " << ex.what() << std::endl;
            }
            gattManager_.reset();
        }
        if (advertisingManager_) {
            try {
                advertisingManager_->callMethod("UnregisterAdvertisement")
                    .onInterface(kLEAdvertisingManagerInterface.data())
                    .withArguments(std::string{kAdvertisementPath});
            } catch (const std::exception& ex) {
                std::cerr << "[hid] UnregisterAdvertisement failed: " << ex.what() << std::endl;
            }
            advertisingManager_.reset();
        }
    }

    void movePointerInternal(int targetX, int targetY)
    {
        const int maxStep = std::min<int>(config_.safety.mouseStepLimit, 127);
        int dx = targetX - lastPointerX_;
        int dy = targetY - lastPointerY_;

        while (dx != 0 || dy != 0) {
            int stepX = std::clamp(dx, -maxStep, maxStep);
            int stepY = std::clamp(dy, -maxStep, maxStep);
            auto report = makeMouseReport(0x00, static_cast<int8_t>(stepX), static_cast<int8_t>(stepY));
            mouseInput_->notifyValue(toVector(report));
            bootMouseInput_->notifyValue({static_cast<uint8_t>(report[1]), static_cast<uint8_t>(report[2]), static_cast<uint8_t>(report[3])});
            std::this_thread::sleep_for(std::chrono::milliseconds(config_.safety.mouseMoveDelayMs));
            lastPointerX_ += stepX;
            lastPointerY_ += stepY;
            dx -= stepX;
            dy -= stepY;
        }
    }

    void sendMouseButton(MouseButton button, bool pressed)
    {
        uint8_t mask = pressed ? mouseButtonMask(button) : 0x00;
        auto report = makeMouseReport(mask, 0, 0);
        mouseInput_->notifyValue(toVector(report));
        bootMouseInput_->notifyValue({mask, 0x00, 0x00});
    }

    HIDConfig config_;

    std::unique_ptr<sdbus::IConnection> connection_;
    std::unique_ptr<sdbus::IObject> appRoot_;
    std::unique_ptr<Advertisement> advertisement_;
    std::unique_ptr<sdbus::IProxy> gattManager_;
    std::unique_ptr<sdbus::IProxy> advertisingManager_;

    std::vector<std::shared_ptr<ManagedObject>> managedObjects_;

    std::shared_ptr<GattCharacteristic> hidInformation_;
    std::shared_ptr<GattCharacteristic> reportMap_;
    std::shared_ptr<GattCharacteristic> controlPoint_;
    std::shared_ptr<GattCharacteristic> protocolMode_;
    std::shared_ptr<GattCharacteristic> keyboardInput_;
    std::shared_ptr<GattCharacteristic> mouseInput_;
    std::shared_ptr<GattCharacteristic> bootKeyboardInput_;
    std::shared_ptr<GattCharacteristic> bootMouseInput_;
    std::shared_ptr<GattCharacteristic> manufacturer_;
    std::shared_ptr<GattCharacteristic> pnpId_;

    uint8_t protocolModeValue_{kProtocolReportMode};
    uint8_t controlPointValue_{0x00};

    int lastPointerX_{0};
    int lastPointerY_{0};

    std::thread eventThread_;
    std::atomic<bool> running_{false};
    mutable std::mutex stateMutex_;
    std::mutex executionMutex_;
};

BluetoothHIDServer::BluetoothHIDServer(HIDConfig config)
    : impl_(std::make_unique<Impl>(std::move(config)))
{
}

BluetoothHIDServer::~BluetoothHIDServer() = default;

void BluetoothHIDServer::start()
{
    impl_->start();
}

void BluetoothHIDServer::stop()
{
    impl_->stop();
}

void BluetoothHIDServer::sendText(const std::string& text)
{
    impl_->sendText(text);
}

void BluetoothHIDServer::click(int x, int y, MouseButton button)
{
    impl_->click(x, y, button);
}

void BluetoothHIDServer::movePointer(int x, int y)
{
    impl_->movePointer(x, y);
}

bool BluetoothHIDServer::isRunning() const noexcept
{
    return impl_->isRunning();
}
