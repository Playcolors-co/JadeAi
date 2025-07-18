all: bthid

bthid: main.c hid_report_map.h
\tgcc -o bthid main.c -lbluetooth -pthread

clean:
\trm -f bthid
