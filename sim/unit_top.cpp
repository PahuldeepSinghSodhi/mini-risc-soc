#include "Vunit_top.h"
#include "test_support.h"
#include "uart_monitor.h"
#include <deque>
#include <random>
int main() try {
    VerilatedContext context;Vunit_top d{&context};
    d.a=0;d.b=0;d.op=0;d.wen=0;d.r1=0;d.r2=0;d.rd=0;d.wdata=0;
    d.push=0;d.pop=0;d.din=0;d.rx=1;d.tx_push=0;d.rx_pop=0;d.tx_data=0;
    reset(d); int passed=0;
    auto alu=[&](int op,uint32_t a,uint32_t b,uint32_t want,bool ov=false){
        d.op=op;d.a=a;d.b=b;d.eval();
        require(d.result==want&&d.zero==(want==0)&&d.negative==(want>>31)&&d.overflow==ov,"ALU result/flag mismatch");
    };
    alu(0,0x7fffffff,1,0x80000000,true);alu(0,0xffffffff,1,0);
    alu(0,0x80000000,0xffffffff,0x7fffffff,true);
    alu(1,0x80000000,1,0x7fffffff,true);alu(1,0x7fffffff,0xffffffff,0x80000000,true);
    alu(1,5,7,0xfffffffe);alu(2,0x55,0x0f,5);alu(3,0x50,0x0f,0x5f);alu(4,0x55,0x0f,0x5a);
    alu(5,0x80000000,0x7fffffff,1);alu(5,0x7fffffff,0x80000000,0);
    alu(6,1,31,0x80000000);alu(6,1,32,1);alu(7,0x80000000,31,1);
    alu(8,0x55,0x12345678,0x12345678);alu(15,1,1,0);++passed;
    d.wen=1;d.rd=3;d.wdata=123;d.r1=3;d.r2=0;d.eval();
    require(d.rdata1==0,"Register wrote before clock edge");edge(d);require(d.rdata1==123,"Register did not write");
    d.rd=0;d.wdata=999;edge(d);require(d.rdata2==0,"R0 write protection failed");
    d.wen=0;d.r1=0;d.r2=3;d.eval();require(d.rdata1==0&&d.rdata2==123,"Asynchronous read failed");
    d.rst_n=0;d.eval();require(d.rdata2==0,"Asynchronous reset failed");d.rst_n=1;++passed;
    std::deque<int> q;std::mt19937 rng(42);uint32_t dropped=0;unsigned high=0;
    for(int cycle=0;cycle<5000;cycle++) {
        // Initial fill/full simultaneous transfer and subsequent random wraparound.
        d.push=cycle<17?1:bool(rng()&1); d.pop=cycle==16?1:(cycle<16?0:bool(rng()&1));d.din=rng()&255;
        d.eval();bool take=d.pop&&!q.empty(),accept=d.push&&(q.size()<16||take);
        require(d.accepted==accept&&d.count==q.size()&&d.full==(q.size()==16)&&d.empty==q.empty(),"FIFO interface mismatch");
        if(!q.empty())require(d.front==q.front(),"FIFO order mismatch");
        if(take)q.pop_front();if(accept)q.push_back(d.din);else if(d.push)++dropped;
        high=std::max(high,unsigned(q.size()));edge(d);
        require(d.count==q.size()&&d.dropped==dropped&&d.high_water==high,"FIFO accounting mismatch");
    }
    ++passed;d.push=0;d.pop=0;reset(d);
    uint64_t cycles=0;UartMonitor monitor;
    auto tick=[&](){edge(d);monitor.observe(d.tx,++cycles);};
    for(int value: {0x00,0xff,0x55,0xa5}) {
        d.tx_data=value;d.tx_push=1;tick();d.tx_push=0;
    }
    for(int n=0;n<700;n++)tick();
    require(monitor.bytes==std::vector<uint8_t>({0,255,0x55,0xa5})&&d.tx_idle,"UART TX bytes/order failed");++passed;
    auto send=[&](int value,bool stop=true){
        d.rx=0;for(int i=0;i<16;i++)tick();
        for(int bit=0;bit<8;bit++){d.rx=(value>>bit)&1;for(int i=0;i<16;i++)tick();}
        d.rx=stop;for(int i=0;i<16;i++)tick();d.rx=1;for(int i=0;i<8;i++)tick();
    };
    for(int value: {0x00,0xff,0x55,0xa5})send(value);
    for(int value: {0x00,0xff,0x55,0xa5}){
        require(d.rx_available&&d.rx_data==value,"UART RX value/order failed");d.rx_pop=1;tick();d.rx_pop=0;
    }
    require(!d.rx_available,"UART RX pop duplicated");++passed;
    send(0x5a,false);require(d.framing_errors==1&&!d.rx_available,"Bad stop bit not discarded");++passed;
    for(int n=0;n<20;n++)send(n);
    require(d.rx_dropped==4,"UART RX overrun count wrong");
    for(int n=0;n<16;n++){require(d.rx_data==n,"UART overrun damaged retained data");d.rx_pop=1;tick();d.rx_pop=0;}++passed;
    // Fill TX faster than serialization and check backpressure.
    for(int n=0;n<17;n++){d.tx_push=1;d.tx_data=n;tick();}d.tx_push=0;d.eval();
    require(!d.tx_space&&!d.tx_idle,"UART TX FIFO did not backpressure");
    for(int n=0;n<3000;n++)tick();require(d.tx_space&&d.tx_idle,"UART TX did not drain");++passed;
    reset(d);require(d.framing_errors==0&&d.rx_dropped==0&&d.tx_idle&&!d.rx_available,"UART reset failed");++passed;
    std::cout<<"{\"suite\":\"units\",\"passed\":"<<passed<<",\"fifo_random_cycles\":5000}\n";
    return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
