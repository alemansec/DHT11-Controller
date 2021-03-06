# DHT11 Controller Project
## Intro
This project consist of a complete digital hardware design of a controller for the [DHT11 Humidity and Temperature Sensor](doc/DTH11.pdf) manufactured by D-Robotics UK:
* Specification
* Architecture design
* Development of the hardware model in VHDL
* Validation by simulation
* Synthesis for the [Zybo board](doc/zybo_rm.pdf), performance evaluation and optimization

## Authors
* Christian Palmiero
* Francesco Condemi
* Marco Coletta

## Directory Structure
The "[sim](sim)" folder contains all the files intended for the simulation of the DHT11 Controller; the "[syn](syn)" folder contains the synthesizable version of the same files plus the synthesis scripts.  
The "[syn](syn)" folder contains also two sub-directories: "[Standalone](syn/Standalone)", with the results of the standalone version synthesis, and "[AXI4Lite](syn/AXI4Lite)", with the results of the AXI4Lite version synthesis.   

# Standalone Version
## Detailed Specifications
### Global
- 4 ms Communication  
- 40 bits complete data (Most Significant Bits first)  

### To start:   
#### MCU drive:  
1. GND (meaning 0) at least 18 ms  
2. VCC (meaning 1) between (20-40) μs

#### DHT drive:  
1. GND for 80 μs  
2. VCC for 80 μs  

### To send data:
For every bit of data :  
  1. GND for 50 μs  
  2. VCC for 26-28 μs to send 0 OR VCC for 70 μs to send 1

### Inputs and Outputs  
#### Button:  
We use the push button to start to read for the sensor.  
But :   
  - After power up, the button should have no effect until 1 sec  
  - Use debouncing function to correct default of the button  

#### Switches:  
  - 1 switch to select the data to display : temperature or humidity (SW0). When the switch is set to 1, we read the humidity level, when it is 0, we read the temperature.  
  - 2 switches to select 4 bits out of the 16 bits (4-bit nibbles) of the data to display (SW1 and SW2).  

When SW1=0 and SW2=0, we display the 4 less significant bits of the data.  
When SW1=0 and SW2=1, we display the 5th to 8th less significant bits.  
When SW1=1 and SW2=0, we display the 5th to 8th most significant bits.  
When SW1=1 and SW2=1, we display the 4 most significant bits of the data.  

```
    SW1,SW2   SW1,SW2  SW1,SW2  SW1,SW2
     1   1     1  0     0  1     0  0
   +--------+--------+--------+--------+
   |  0101  |  0110  |  0001  |  1100  |  -> 16 bits to display
   +--------+--------+--------+--------+
```

  - 1 switch to put the LEDs in an "error/check state":  

```
      3      2      1      0    
   +------+------+------+------+
   |  PE  | SW0  |  B   |  CE  |
   +------+------+------+------+
```

PE (Protocol error): if this LED in on this means that there was an error in the protocol, for example the MCU is waiting for a bit of data that is not coming or the DTH is not doing what is expected.  
SW0: display the value of SW0 (when this bit is set, it means that the switch 0 is set).  
B (busy bit): indicates that the delay after the power up is not passed or that the sensor is currently sending data. When the bit is set,  we shouldn't try to read from the sensor.  
CE (Checksum error): if this bit is set, it means that the checksum sent and the one computed are different -> the data read from the sensor might be false.  

Remark: when the PE bit is set, we can use the other LED to display the kind of protocol error occurs but this may be not worthwhile and complicated.  

#### Overview
```
    SW0,SW1,SW2  
     1   1   1      1  1  0      1  0  1      1  0  0  |  0   1   1     0  1  0      0  0  1      0  0  0  |  not displayed
   +------------+------------+------------+------------+------------+------------+------------+------------+-----------------+
   |    1010    |    0110    |    0001    |    0100    |    0010    |    1110    |    0011    |    1100    |     01011001    |  -> 40 bits from the DHT11 sensor
   +------------+------------+------------+------------+------------+------------+------------+------------+-----------------+
                      Humidity data                    |                   Temperature                     |     CHECK SUM

```

#### LEDs :  
We use the 4 LEDs to display 4 bits of data (the 4 bits chosen by the switches SW1 and SW2 or the specific states specified above).  


```
      11     10     01     00
   +------+------+------+------+
   |  L3  |  L2  |  L1  |  L0  |
   +------+------+------+------+
```
## Architecture Design
### Common Interface

The DHT11 controller and the DHT11 sensor communicates with a one-bit communication line with a pull-up resistor and a drive low protocol.

![alt text][top-entity]

[top-entity]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/top_entity.png "Top Entity"

```vhdl
library ieee;
use ieee.std_logic_1164.all;
...

entity dht11_top is
  port(...
       data:    inout std_logic
       ...
  );
end entity dht11_top;

architecture rtl of dht11_top is
  signal data_in:  std_ulogic;
  signal data_drv: std_ulogic;
  ...
begin
  data    <= '0' when data_drv = '1' else 'H';
  data_in <= data;
  ...
end architecture rtl;
```

### DHT11 Controller Internals

The DHT11 controller is composed of several entities, listed according to a bottom-up approach:
* **CU.vhd**: it is the control unit, a complex finite state machine;
* **datapath.vhd**: it is a collection of functional units.
* **dht11_ctrl.vhd**: it comprises the CU and the datapath.
* **dht11_sa.vhd**: it comprises the ctrl, a debouncer, a checksum controller and two multiplexers that handle the data to be displayed on the LEDs though the switches.
* **dht11_sa_top.vhd**: it is the top level entity that models
the 3-states buffer that uses data_drv to drive the data line between the DHT11 controller and the DHT11 sensor.

#### DHT11 Controller Block Diagram
![alt text][dp]

[dp]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/new_dp.png "Datapath"

#### Datapath Technical Details

The datapath has been designed at RT-level according to a behavioral view. It consists of the following processes:
* **SIPO**: it describes a Serial In Parallel Out register, that stores input data in a serial fashion and makes it available at the output in a parallel form. The SIPO takes as input the clock, a synchronous active high reset, an input serial data and a shift enable that enables the input serial data storage and the internal data shift. The SIPO outputs a 40-bit data signal and a final counter signal, that points out that all the 40 bits have been stored inside the register.
* **MUXES**: it describes a cascade of multiplexers that, according to the value of three input switches (SW0, SW1, SW2), outputs the corresponding 4-bit nibble of the temperature/humidity data coming from the SIPO that the user wants to display.
* **CHECKSUM_CONTROLLER**: it describes a combinational block that takes as input the the 40-bit data coming from the SIPO, computes the checksum and compares it with the one that has been computed and sent by the sensor. The checksum controller outputs the checksum error bit.
* **MUX**: it describes a multiplexer that, according to the value of SW3, either displays the 4-bit nibble output by the MUXES process (check state) or gathers together and shows some error information coming from the control unit (error state). The selected output is sent to the LEDs.
* **COUNTER** : it describes a programmable up counter that is initialised with a value generated by the control unit and that counts upwards, from 0 to the programmed value. The counter has the main purpose of establishing the correct data acquisition timing depicted on the DHT11 reference manual. The COUNTER outputs the current value and a final counter signal, that points out that the final programmed value has been reached.
* **COMPARATOR**: it describes a threshold comparator that checks whether the current counter value is in between two thresholds. The thresholds are computed by adding to and subtracting from a central value a delta (margin). The comparator main purpose is to help the control unit to detect whether a new phase of the MCU-sensor communication protocol has started not at an exact instant of time, but in between two thresholds. This behavior takes into account all the factors and the conditions affecting the accuracy of the sensor and allows the design to gain a little in term of flexibility.
* **SECOND_COMPARATOR**: it describes a threshold comparator that has exactly the same function of the previous COMPARATOR, with the only difference that it is used for the last part of the communication protocol (5.3 section on the DHT11 reference manual), that consist in receiving from the sensor either a "Data 0" or a "Data 1".
* **PULSE_GEN**: it is a multiple-stage pulse generator that detects a logic value change on the "data_in" line; it generates a 1-clock cycle pulse on the falling output if there is a falling-edge on the "data_in" line and a 1-clock cycle pulse on the rising output if there is a rising-edge on the "data_in" line.


#### Control Unit Flow Diagram
![alt text][cu]

[cu]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/fsm.png "Control Unit"

## Functional Validation
The design has been validated through three simulation environments:
* [sim/dht_emul.vhd](sim/dht_emul.vhd): a complete simulation environment for dht11_sa(rtl) where a full 40-bit data transmission between the sensor and the controller is executed.
* [sim/dht11_ctrl_sim_old.vhd](sim/dht11_ctrl_sim_old.vhd): a complete simulation environment for dht11_ctrl(rtl) with two generic parameters, the margin for protocol error detection and the clock frequency.
* [sim/dht11_ctrl_sim.vhd](sim/dht11_ctrl_sim.vhd): a less aggressive simulation environment for dht11_ctrl(rtl) with no generic parameters and a fixed clock frequency equal to 2 MHz.

## Synthesis

The design has been synthesised with the Vivado tool provided by Xilinx and mapped in the programmable logic part of the Zynq core of the Zybo.
The [dht11_sa_top.syn.tcl](https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/syn/dht11_sa_top.syn.tcl) TCL script automates the synthesis.

The primary clock "clk" comes from the 125 MHz Zynq reference clock.
The synchronous active high reset "rst" comes from the press-button BTN1 of the Zybo board, the button "btn" is the press-button BTN0.
The four "sw" input signals are mapped to the Zybo board four slide switches.
The four "led" output signals are sent to the 4 LEDs of the Zybo board.
Finally, the "data" inout line is mapped to the pin JE1 of the Pmod connector J.
<center>

   | Name   |  Pin | Level    |
   |:------:|:----:|:--------:|
   | clk    |  L16 | LVCMOS33 |
   | rst    |  P16 | LVCMOS33 |
   | btn    |  R18 | LVCMOS33 |
   | sw[0]  |  G15 | LVCMOS33 |
   | sw[1]  |  P15 | LVCMOS33 |
   | sw[2]  |  W13 | LVCMOS33 |
   | sw[3]  |  T16 | LVCMOS33 |
   | data   |  V12 | LVCMOS33 |
   | led[0] |  M14 | LVCMOS33 |
   | led[1] |  M15 | LVCMOS33 |
   | led[2] |  G14 | LVCMOS33 |
   | led[3] |  D18 | LVCMOS33 |

</center>
The synthesis result is a boot image: syn/Standalone/boot.bin.
Two important reports have also been produced: the resources usage report (syn/Standalone/top_wrapper_utilization_placed.rpt);
the timing report (syn/Standalone/top_wrapper_timing_summary_routed.rpt).

## Experiments on the Zybo
An experiment in the EURECOM Campus Room 104 has been executed on July, 7th.
The following pictures and data refer to temperature and humidity measurements.
### Temperature
* Integer part: 00011001 -> 25°C
![alt text][T1]

[T1]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/T1.jpg
![alt text][T0]

[T0]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/T0.jpg
### Humidity
* Integer part: 00100101 -> 37%
![alt text][H1]

[H1]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/H1.jpg
![alt text][H0]

[H0]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/H0.jpg
# AXI4 Lite Version
## Specifications
The AXI4 lite wrapper around the dht11_ctrl(rtl) contains two 32-bits read-only registers:  

| Address |               Name  |  Description |
|:-------:|:-------------------:|:------------:|
|0x00000000-0x00000003|  DATA   | read-only, 32-bits, data register|
|0x00000004-0x00000007 | STATUS | read-only, 32-bits, status register|
|0x00000008-...        | -      | unmapped|

Writing to DATA or STATUS shall be answered with a SLVERR response. Reading or writing to the unmapped address space [0x00000008,...] shall be answered with a DECERR response.

The reset value of DATA is 0xffffffff.  
DATA(31 downto 16) = last sensed humidity level, Most Significant Bit: DATA(31).  
DATA(15 downto 0) = last sensed temperature, MSB: DATA(15).  

The reset value of STATUS is 0x00000000.  
STATUS = (2 => PE, 1 => B, 0 => CE, others => '0'), where PE, B and CE are the protocol error, busy and checksum error flags, respectively.

After the reset has been de-asserted, the wrapper waits for 1 second and sends the first start command to the controller. Then, it waits for one more second, samples DO(39 downto 8) (the sensed values) in DATA, samples the PE and CE flags in STATUS, and sends a new start command to the controller. And so on every second, until the reset is asserted. When the reset is de-asserted, every rising edge of the clock, the B output of the DHT11 controller is sampled in the B flag of STATUS.

## Architecture Design

### DHT11 Controller Internals

The DHT11 controller is composed of several entities, listed according to a bottom-up approach:
* **CU.vhd**: it is the control unit, a complex finite state machine.
* **datapath.vhd**: it is a collection of functional units.
* **dht11_ctrl.vhd**: it comprises the CU and the datapath.
* **dht11_axi.vhd**: it is the AXI4 lite wrapper around the dht11_ctrl(rtl).
* **dht11_axi_top.vhd**: it is the top level entity that models
the 3-states buffer that uses data_drv to drive the data line between the DHT11 controller and the DHT11 sensor.

#### AXI4 Lite Wrapper Technical Details

The AXI4 lite wrapper around the dht11_ctrl(rtl) handles the communication protocol between and AXI master and an AXI slave. Other than the crtl, it comprises:  
* **WRITE FSM**: it handles the write operations. The slave asserts the AWREADY and the WREADY signals after the master has asserted **both** the AWVALID and the WREADY simultaneously; then, it responds with an error. Note that the write operations have **lower** priority with respect to the read operations.
* **READ FSM**: it handles the read operations. The slave pre-asserts the ARREADY signal so that each time the AXI master issues a read request, it will be acknowledged on the next rising edge of the clock; then, it responds properly. Note that the read operations have **higher** priority with respect to the write operations.
* **CHECKSUM_CONTROLLER**: it describes a combinational block that takes as input the the 40-bit data coming from the SIPO, computes the checksum and compares it with the one that has been computed and sent by the sensor. The checksum controller outputs the checksum error bit.
* **COUNTER**: it is a counter used to count up to 1 second.
* **REGS**: it is a process that sets the values of the two internal registers, DATA and STATUS.
* **ADDRESS_SAMPLER**: it is a process that samples the read address as soon as the ARREADY signal is asserted.
* **MUX**: it is a process that retrieves the proper DATA or STATUS content depending on the sampled read address.

#### Write FSM Flow Diagram
![alt text][wfsm]

[wfsm]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/wfsm.png "Write FSM"

#### Read FSM Flow Diagram
![alt text][rfsm]

[rfsm]: https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/img/rfsm.png "Read FSM"

## Functional Validation
The design has been validated through one simulation environment:
* [sim/dht11_axi_sim.vhd](sim/dht11_axi_sim.vhd): a complete simulation environment for dht11_axi(rtl);

## Synthesis

The design has been synthesised with the Vivado tool provided by Xilinx and mapped in the programmable logic part of the Zynq core of the Zybo.
The [dht11_axi_top.syn.tcl](https://github.com/ChristianPalmiero/DHT11_Controller/blob/master/syn/dht11_axi_top.syn.tcl) TCL script automates the synthesis.

The synthesis result is a boot image: syn/AXI4Lite/axi_boot.bin.
Two important reports have also been produced: the resources usage report (syn/AXI4Lite/axi_top_wrapper_utilization_placed.rpt);
the timing report (syn/AXI4Lite/axi_top_wrapper_timing_summary_routed.rpt).

## Experiments on the Zybo
To communicate with the sensor from the software world, the devmem utility has been used to read or write at various locations. The base address of the DHT11 AXI controller is 0x4000_0000. Example:

```bash
zybo> devmem 0x40000000 32 # read temperature and humidity level
zybo> devmem 0x40000004 32 # read status (00...00 | PE | B | CE)
zybo> devmem 0x40000008 32 # read out of range, should raise error
zybo> devmem 0x40000000 32 0 # write in range, should raise error
zybo> devmem 0x40000004 32 0 # write in range, should raise error
zybo> devmem 0x40000008 32 0 # write out of range, should raise error
```

Results:  
```bash
zybo> devmem 0x40000000 32
0x24001900
```
Humidity: 36%, Temperature: 25°C
```bash
zybo> devmem 0x40000004 32
0x00000000
zybo> devmem 0x40000008 32
Unhandled fault: external abort on non-linefetch (0x018) at 0xb6f72008
pgd = dde58000
[b6f72008] *pgd=1dd6f831, *pte=40000783, *ppte=40000e33
Bus error
zybo> devmem 0x40000000 32 0
Unhandled fault: external abort on non-linefetch (0x1818) at 0xb6fc5000
pgd = ddd50000
[b6fc5000] *pgd=1dce7831, *pte=40000743, *ppte=40000c33
Bus error
zybo> devmem 0x40000004 32 0
Unhandled fault: external abort on non-linefetch (0x1818) at 0xb6f67004
pgd = dde58000
[b6f67004] *pgd=1dce7831, *pte=40000743, *ppte=40000c33
Bus error
zybo> devmem 0x40000008 32 0
Unhandled fault: external abort on non-linefetch (0x818) at 0xb6f7e008
pgd = ddd50000
[b6f7e008] *pgd=1dce7831, *pte=40000743, *ppte=40000c33
Bus error
```
