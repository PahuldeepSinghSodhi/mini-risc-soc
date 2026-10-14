#pragma once
#include "test_support.h"
struct UartMonitor {
    int bit=-1; uint64_t due=0; uint8_t value=0;
    std::vector<uint8_t> bytes;
    void observe(bool line,uint64_t cycle) {
        if(bit<0) {if(!line){bit=0;value=0;due=cycle+24;}return;}
        if(cycle!=due)return;
        if(bit<8) {value|=uint8_t(line)<<bit;bit++;due+=16;}
        else {require(line,"UART TX stop bit invalid");bytes.push_back(value);bit=-1;}
    }
};
