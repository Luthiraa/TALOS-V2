// Example instance of the top level module for: 
//     switch_to_led
// To include this component in your design, include: 
//     switch_to_led.qsys
// in your Quartus project and follow the template 
// below to instantiate the IP.  Alternatively, the IP core 
// can be generated from a Qsys system.

switch_to_led switch_to_led_inst (
  // Interface: clock (clock end)
  .clock         ( ), // 1-bit clk input
  // Interface: reset (reset end)
  .resetn        ( ), // 1-bit reset_n input
  // Interface: call (conduit sink)
  .start         ( ), // 1-bit valid input
  .busy          ( ), // 1-bit stall output
  // Interface: return (conduit source)
  .done          ( ), // 1-bit valid output
  .stall         ( ), // 1-bit stall input
  // Interface: returndata (conduit source)
  .returndata    ( ), // 32-bit data output
  // Interface: button_n (conduit sink)
  .button_n      ( ), // 1-bit data input
  // Interface: reset_button_n (conduit sink)
  .reset_button_n( )  // 1-bit data input
);
