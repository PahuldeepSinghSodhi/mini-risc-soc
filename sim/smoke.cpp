#include "Vsmoke.h"
#include <stdexcept>
#include <iostream>
int main() {
    Vsmoke dut;
    dut.clk=0; dut.rst_n=0; dut.eval();
    dut.clk=1; dut.eval(); dut.rst_n=1;
    for (int i=0;i<5;i++) { dut.clk=0; dut.eval(); dut.clk=1; dut.eval(); }
    if (dut.count!=5) throw std::runtime_error("smoke failed");
    std::cout << "PASS native RTL simulation smoke\n";
}
