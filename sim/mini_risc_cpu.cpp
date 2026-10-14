#include "Vmini_risc_cpu.h"
#include "test_support.h"
#include <array>
#include <random>
#include <memory>

struct Machine {
    VerilatedContext context;
    Vmini_risc_cpu dut{&context};
    std::array<uint32_t,256> rom{}, ram{};
    std::mt19937 rng;
    int max_delay, icount=-1, dcount=-1, stores=0, retired=0;
    uint32_t ia=0, da=0, wd=0; bool wr=false;
    Machine(int delay=0,int seed=42):rng(seed),max_delay(delay) {
        rom.fill(0xf0000000); ram.fill(0);
        dut.imem_ready=0; dut.imem_error=0; dut.imem_rdata=0;
        dut.dmem_ready=0; dut.dmem_error=0; dut.dmem_rdata=0;
        reset(dut);
    }
    void tick() {
        dut.clk=0; dut.imem_ready=0; dut.dmem_ready=0; dut.eval();
        if(dut.imem_req) {
            if(icount<0) {ia=dut.imem_addr; icount=int(rng()%(max_delay+1));}
            require(ia==dut.imem_addr,"Instruction address changed during wait");
            if(icount==0) {dut.imem_ready=1; dut.imem_error=ia>=256; dut.imem_rdata=ia<256?rom[ia]:0;}
            else --icount;
        }
        if(dut.dmem_req) {
            if(dcount<0) {da=dut.dmem_addr;wd=dut.dmem_wdata;wr=dut.dmem_write;dcount=int(rng()%(max_delay+1));}
            require(da==dut.dmem_addr&&wd==dut.dmem_wdata&&wr==bool(dut.dmem_write),"Data request changed during wait");
            if(dcount==0) {dut.dmem_ready=1; dut.dmem_error=da>=256; dut.dmem_rdata=da<256?ram[da]:0;}
            else --dcount;
        }
        dut.eval(); bool iack=dut.imem_req&&dut.imem_ready, dack=dut.dmem_req&&dut.dmem_ready;
        if(dack&&wr&&da<256) {ram[da]=wd;++stores;}
        dut.contextp()->timeInc(1);dut.clk=1;dut.eval();dut.contextp()->timeInc(1);
        if(iack) icount=-1; if(dack) dcount=-1;
        if(dut.retire_valid) ++retired;
    }
    void load(std::initializer_list<uint32_t> words) {std::copy(words.begin(),words.end(),rom.begin());}
    void run() {for(int n=0;n<100000&&!dut.halted;n++)tick(); require(dut.halted,"CPU timeout");}
    uint32_t r(int i) {return dut.debug_regs[i];}
    void stopped() {
        auto pc=dut.pc; auto bank=dut.debug_regs;int writes=stores;
        for(int n=0;n<20;n++)tick();
        require(dut.pc==pc&&stores==writes,"Stopped CPU changed state");
        for(int n=0;n<16;n++)require(dut.debug_regs[n]==bank[n],"Stopped register changed");
    }
};

int main() try {
    int passed=0;
    for(int seed: {0,1,14,42}) {
        Machine m(7,seed);
        m.load({ins(1,1,0,5),ins(1,2,0,7),reg(0,3,1,2),reg(1,4,1,2),
            reg(2,5,1,2),reg(3,6,1,2),reg(4,7,1,2),reg(5,8,4,1),
            ins(1,9,0,1),reg(6,10,1,9),reg(7,11,2,9),
            ins(2,12,4,-1),ins(3,13,0,0x55),ins(10,14,4,0),
            0x9f0abcdeu,ins(5,3,0,10),ins(4,2,0,10),ins(1,0,0,99),0xf0000000u});
        m.run();require(m.dut.fault_cause==0,"Unexpected arithmetic fault");
        std::array<uint32_t,16> want={0,5,12,12,0xfffffffe,5,7,2,1,1,10,3,0xfffffffe,0x55,1,0xabcde000};
        for(int r=0;r<16;r++)require(m.r(r)==want[r],"Arithmetic register mismatch R"+std::to_string(r));
        require(m.stores==1&&m.ram[10]==12&&m.retired==19,"Store duplicated or retirement count wrong");
        m.stopped();++passed;
    }
    {
        Machine m(5);m.load({ins(1,1,0,3),ins(1,2,0,0),ins(1,2,2,1),ins(1,1,1,-1),
            ins(7,0,1,-2),ins(6,2,2,2),ins(1,3,0,999),ins(6,2,0,2),ins(7,2,2,2),
            jump(4,2),ins(1,3,0,999),0xf0000000});m.run();
        require(m.r(2)==3&&m.r(3)==0&&m.r(4)==10,"Branch routing/PC-relative/link failure");++passed;
    }
    {
        Machine m; m.load({ins(1,1,0,1),reg(5,2,0,1),reg(6,3,1,0),ins(1,4,0,32),
            reg(6,5,1,4),ins(1,6,0,-1),reg(7,7,6,1),reg(5,8,6,1),0xf0000000});m.run();
        require(m.r(2)==1&&m.r(3)==1&&m.r(5)==1&&m.r(7)==0x7fffffff&&m.r(8)==1,"Signed/shift boundary failure");++passed;
    }
    {
        Machine m(7);m.load({ins(1,1,0,-524288),ins(1,2,0,524287),ins(3,3,0,-1),0xf0000000});m.run();
        require(m.r(1)==0xfff80000&&m.r(2)==0x7ffff&&m.r(3)==0xffffffff,"Immediate boundary/sign extension failure");++passed;
    }
    for(uint32_t word: {0xb0000000u,0xc0000000u,0xd0000000u,0xe0000000u,
                       0x01000008u,0x0100000fu,0x01000010u}) {
        Machine m(7);m.load({ins(1,1,0,123),word,ins(5,1,0,0)});m.run();
        require(m.dut.fault_cause==1&&m.dut.fault_pc==1&&m.r(1)==123&&m.stores==0&&m.retired==1,"Illegal instruction side effect");
        m.stopped();++passed;
    }
    for(bool store: {false,true}) {
        Machine m(7); m.load({ins(1,1,0,42),ins(store?5:4,1,0,256),0xf0000000});m.run();
        require(m.dut.fault_cause==3&&m.dut.fault_pc==1&&m.r(1)==42&&m.stores==0,"Data fault side effect");++passed;
    }
    for(int offset: {256,-1}) {
        Machine m(7); m.load({jump(0,offset)});m.run();
        require(m.dut.fault_cause==2&&m.dut.fault_pc==uint32_t(offset)&&m.retired==1,"Fetch bounds/aliasing failure");++passed;
    }
    {
        Machine m(7);m.load({ins(1,1,0,123),0xf0000000});m.run();m.stopped();
        reset(m.dut); require(!m.dut.halted&&m.dut.pc==0&&m.dut.fault_cause==0,"Reset did not restart CPU");
        for(int r=0;r<16;r++) require(m.r(r)==0,"Reset did not clear register");++passed;
    }
    {
        Machine m(7);m.load({ins(1,1,0,99),ins(5,1,0,0),0xf0000000});
        while(!m.dut.dmem_req)m.tick();
        m.dut.rst_n=0;m.dut.eval();
        require(!m.dut.dmem_req&&!m.dut.imem_req,"Reset did not cancel pending bus request");
        edge(m.dut);m.icount=m.dcount=-1;m.rom[0]=0xf0000000;m.dut.rst_n=1;m.run();
        require(m.stores==0&&m.ram[0]==0&&m.r(1)==0,"Reset allowed stale pending store");++passed;
    }
    std::cout<<"{\"suite\":\"cpu\",\"passed\":"<<passed<<"}\n";
    return 0;
} catch(const std::exception& e) {std::cerr<<e.what()<<"\n";return 1;}
