#pragma once
#include <verilated.h>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>
#include <string>
inline void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}
inline uint32_t ins(int op, int rd, int a, int value) {
    return (uint32_t(op)<<28)|(uint32_t(rd)<<24)|(uint32_t(a)<<20)|(uint32_t(value)&0xfffff);
}
inline uint32_t reg(int fn, int rd, int a, int b) { return (rd<<24)|(a<<20)|(b<<16)|fn; }
inline uint32_t jump(int rd, int offset) { return 0x80000000u|(rd<<24)|(uint32_t(offset)&0xffffff); }
template<class T> void edge(T& dut) {
    dut.clk=0; dut.eval(); dut.contextp()->timeInc(1);
    dut.clk=1; dut.eval(); dut.contextp()->timeInc(1);
}
template<class T> void reset(T& dut) {
    dut.rst_n=0; edge(dut); edge(dut); dut.rst_n=1;
}
