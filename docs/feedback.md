Feedback:
 
Report (002).pdf:
Abstract: Remove things to do and in progress. Write the report as if your work is done.
Acknowledgement: What about Alex?
Abbreviation: What is VHSIC?
Chapter 2.1:  
move "(Figure 1)" to a sentence where it makes sense to refer to it, e.g., the sentence that ends with "without any designated bus master."
Refer to all Figures with something like this "... see Figure X" or "..., as shown in Figure X"
"body peripherals" ?
Table-3, what about CAN XL?
Chapter 2.2:
You should at least list what tools you have been using in this project.
What is GHDL? Not in the abbreviation list.
Chapter 3.2:
Could benefit from some examples, especially the MCP-server part
Chapter 4.1
Make a table of the requirement to layer mapping.
Chapter 4.2 and 4.3
Move Figure 4, 5, and 6 closer to the text describing them
"(Section 7.7, Figure 7)." There is no Figure 7 in Section 7.7
Chapter 4.4:
Figure 8, what is the non-coloured part of the Figure?
Chapter 7.2:
Figure 12 is quite useless. Turned on the side and with a million wires.
Chapter 7.2.4
Formatting error
Chapter 7.5:
"The output mux (p_crc_mux) is implemented combinatorially rather than as a registered stage ..." Sounds like a load of BS , The control logic clocks at 100 MHz, the CAN-FD runs at a much lower speed, meaning that you could have used a number of controller logic clock cycles to calculate the CRC if you wanted to.
"With the MAC submodules established, the two remaining modules - the Fault Confinement Entity and the

Physical Coding Sublayer - are described in the following subsections." Redundant, please remove.
Chapter 7.6:
Figure 17, colouring error: s_error_active is the green state, error_passive the orange and buss off the red one.
"The PCS layer, which supplies the bit-level timing strobes that drive every FSM state transition, is described

next.". Redundant, please remove.
Chapter 7.7.1
"The prior implementation (the prior implementation)" ?
"missed three of the four ISO 7.3.5.1 synchronization rules:" Is this fixed now?
Chapter 7.7.3
"The six entities described above - .." This whole paragraph is redundant, please remove.
In general:
Try to reduce the amount of describing vhdl code in text. There are to much details in the implementation Chapter-7.
Somethings are repeated too many times, e.g. the split/merge of RX-TX.
But all in all, not too bad. I liked the AI-part.
Missing:
A table of the implementation size compared to the already existing Classic CAN
 