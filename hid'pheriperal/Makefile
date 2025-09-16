CXX := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -O2
LDFLAGS := -lbluetooth -pthread

SRCS := main.cpp \
        bluetooth_manager.cpp \
        hid_server.cpp \
        command_server.cpp \
        key_mapper.cpp

OBJS := $(SRCS:.cpp=.o)

all: bthid

bthid: $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS) $(LDFLAGS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f bthid $(OBJS)
