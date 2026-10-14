#include "Vmini_risc_soc.h"
#include "test_support.h"
#include "uart_monitor.h"
#include <fstream>
#include <deque>
#include <map>

struct Sample {int id,value;uint64_t arrival;};
int main(int argc,char** argv) try {
    VerilatedContext context;context.commandArgs(argc,argv);Vmini_risc_soc d{&context};
    std::map<std::string,std::string> options;
    for(int a=1;a<argc;a++){std::string arg=argv[a];auto eq=arg.find('=');if(eq!=std::string::npos)options[arg.substr(0,eq)]=arg.substr(eq+1);}
    bool stream=options["--mode"]!="halt",loopback=options["--loopback"]=="1";
    int interval=options.count("--interval")?std::stoi(options["--interval"]):1024;
    int start_delay=options.count("--start-delay")?std::stoi(options["--start-delay"]):0;
    require(interval>0&&start_delay>=0,"Invalid sample timing");
    std::vector<int> samples;
    if(options.count("--samples")){std::ifstream input(options["--samples"]);require(bool(input),"Missing sample file");int value;while(input>>value){require(value>=0&&value<4096,"Sample outside 12-bit range");samples.push_back(value);}}
    std::ofstream trace;
    if(options.count("--trace")){trace.open(options["--trace"]);require(bool(trace),"Cannot open trace");trace<<"event,cycle,index,value,extra\n";}
    auto record=[&](const char*event,uint64_t cycle,int id,int value,int extra=0){if(trace)trace<<event<<","<<cycle<<","<<id<<","<<value<<","<<extra<<"\n";};
    d.sample_valid=0;d.sample_data=0;d.uart_rx=1;d.debug_mem_addr=32;reset(d);
    uint64_t cycle=0,next_offer=0,ready_cycle=0,last_processed=0;
    bool started=false,completed=false;int offered=0,accepted=0,processed=0,previous_alarm=0,stopped_cycles=0;
    UartMonitor monitor;size_t uart_seen=0;
    std::deque<Sample> fifo,processing;
    for(cycle=1;cycle<=2000000;cycle++) {
        d.clk=0;d.sample_valid=0;d.uart_rx=loopback?d.uart_tx:1;d.eval();
        if(!started&&(d.gpio&2)){started=true;ready_cycle=cycle;next_offer=cycle+uint64_t(start_delay);}
        if(started&&offered<int(samples.size())&&cycle>=next_offer){
            d.sample_valid=1;d.sample_data=samples[offered];d.eval();
        }
        // Pop uses the old FIFO front, even during a simultaneous full push/pop.
        if(d.debug_sample_pop){
            require(!fifo.empty(),"Unexpected/duplicated sensor pop");
            auto sample=fifo.front();fifo.pop_front();
            require(sample.value==d.debug_sample_value,"Sensor FIFO corrupted/reordered sample");
            processing.push_back(sample);record("pop",cycle,sample.id,sample.value);
        }
        if(d.sample_valid){
            bool take=d.debug_sample_accepted;
            record("offer",cycle,offered,samples[offered],take);
            if(take){fifo.push_back({offered,samples[offered],cycle});++accepted;}
            ++offered;next_offer+=uint64_t(interval);
        }
        d.contextp()->timeInc(1);d.clk=1;d.eval();d.contextp()->timeInc(1);
        monitor.observe(d.uart_tx,cycle);
        while(uart_seen<monitor.bytes.size()){record("uart",cycle,int(uart_seen),monitor.bytes[uart_seen]);++uart_seen;}
        int alarm=d.gpio&1;
        if(alarm!=previous_alarm){
            require(!processing.empty(),"Alarm not attributable to a sample");
            record("alarm",cycle,processing.front().id,alarm);previous_alarm=alarm;
        }
        if(stream&&started){
            d.debug_mem_addr=32;d.eval();auto count=d.debug_mem_data;
            if(count!=uint32_t(processed)){
                require(count==uint32_t(processed+1)&&!processing.empty(),"Processed sample skipped or duplicated");
                auto sample=processing.front();processing.pop_front();
                d.debug_mem_addr=33;d.eval();record("processed",cycle,sample.id,d.debug_mem_data,alarm);
                ++processed;last_processed=cycle;
            }
        }
        if(d.halted||(!stream&&d.fault_cause)) {
            // Allow the registered retirement pulse (including HALT) to reach its counter.
            if(++stopped_cycles>=3&&d.debug_uart_idle){completed=true;break;}
        }
        if(stream&&started&&offered==int(samples.size())&&processed==accepted&&fifo.empty()&&processing.empty()&&d.debug_uart_idle&&cycle>last_processed+20){completed=true;break;}
    }
    require(completed,"SoC simulation timeout");
    if(stream)require(!d.halted&&d.fault_cause==0,"Firmware halted/faulted unexpectedly");
    std::cout<<"{\"cycles\":"<<cycle<<",\"ready_cycle\":"<<ready_cycle<<",\"last_processed_cycle\":"<<last_processed
        <<",\"offered\":"<<offered<<",\"accepted\":"<<accepted<<",\"processed\":"<<processed
        <<",\"dropped\":"<<d.debug_dropped<<",\"high_water\":"<<int(d.debug_high_water)
        <<",\"retired\":"<<d.debug_retired<<",\"halted\":"<<int(d.halted)
        <<",\"fault\":"<<int(d.fault_cause)<<",\"fault_pc\":"<<d.fault_pc<<",\"gpio\":"<<d.gpio<<",\"memory\":{";
    for(int address=32;address<48;address++){d.debug_mem_addr=address;d.eval();if(address!=32)std::cout<<",";std::cout<<"\""<<address<<"\":"<<d.debug_mem_data;}
    std::cout<<"},\"uart\":[";
    for(size_t i=0;i<monitor.bytes.size();i++){if(i)std::cout<<",";std::cout<<unsigned(monitor.bytes[i]);}
    std::cout<<"]}\n";return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}
