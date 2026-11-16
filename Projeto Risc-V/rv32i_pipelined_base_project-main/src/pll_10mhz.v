// =============================================================================
// pll_10mhz.v
// ALTPLL wrapper — 50 MHz → 10 MHz for Cyclone IV E (DE2-115)
//
// Equivalent to what the Quartus IP Catalog wizard generates for:
//   Input  : inclk0 = 50 MHz  (period = 20 000 ps)
//   Output : c0     = 10 MHz  (divide_by=5, multiply_by=1)
//   locked : asserts when PLL has acquired lock (~1 ms after power-on)
//
// Use locked to gate the CPU reset so the design only starts running
// after the output clock is stable.
// =============================================================================

module pll_10mhz (
    input  wire inclk0,   // 50 MHz board clock (CLOCK_50)
    output wire c0,       // 10 MHz output clock
    output wire locked    // 1 = PLL locked and output stable
);

    wire [4:0] sub_wire0;              // ALTPLL clk[] bus (5 outputs)
    wire       sub_wire1 = 1'b0;      // unused second inclk

    assign c0 = sub_wire0[0];

    altpll altpll_component (
        // ---- inputs --------------------------------------------------------
        .inclk          ({sub_wire1, inclk0}),  // [1]=unused, [0]=50 MHz
        .areset         (1'b0),
        .clkena         ({6{1'b1}}),
        .clkswitch      (1'b0),
        .configupdate   (1'b0),
        .extclkena      ({4{1'b1}}),
        .fbin           (1'b1),
        .pfdena         (1'b1),
        .phasecounterselect ({4{1'b1}}),
        .phasestep      (1'b1),
        .phaseupdown    (1'b1),
        .pllena         (1'b1),
        .scanaclr       (1'b0),
        .scanclk        (1'b0),
        .scanclkena     (1'b1),
        .scandata       (1'b0),
        .scanread       (1'b0),
        .scanwrite      (1'b0),
        // ---- outputs -------------------------------------------------------
        .clk            (sub_wire0),
        .locked         (locked),
        // ---- unused outputs (left open) ------------------------------------
        .activeclock    (),
        .clkbad         (),
        .clkloss        (),
        .enable0        (),
        .enable1        (),
        .extclk         (),
        .fbmimicbidir   (),
        .fbout          (),
        .fref           (),
        .icdrclk        (),
        .phasedone      (),
        .sclkout0       (),
        .sclkout1       (),
        .vcooverrange   (),
        .vcounderrange  ()
    );

    defparam
        // ---- device / family -----------------------------------------------
        altpll_component.intended_device_family  = "Cyclone IV E",
        altpll_component.lpm_type                = "altpll",
        altpll_component.lpm_hint                = "CBX_MODULE_PREFIX=pll_10mhz",
        altpll_component.operation_mode          = "NORMAL",
        altpll_component.pll_type                = "AUTO",
        altpll_component.bandwidth_type          = "AUTO",
        altpll_component.self_reset_on_loss_lock = "OFF",
        altpll_component.width_clock             = 5,
        // ---- input clock ---------------------------------------------------
        altpll_component.inclk0_input_frequency  = 20000,   // 20 000 ps = 50 MHz
        altpll_component.compensate_clock        = "CLK0",
        // ---- output c0 : 10 MHz (÷5) ---------------------------------------
        altpll_component.clk0_divide_by          = 5,
        altpll_component.clk0_multiply_by        = 1,
        altpll_component.clk0_duty_cycle         = 50,
        altpll_component.clk0_phase_shift        = "0",
        // ---- port declarations ---------------------------------------------
        altpll_component.port_inclk0             = "PORT_USED",
        altpll_component.port_inclk1             = "PORT_UNUSED",
        altpll_component.port_locked             = "PORT_USED",
        altpll_component.port_clk0               = "PORT_USED",
        altpll_component.port_clk1               = "PORT_UNUSED",
        altpll_component.port_clk2               = "PORT_UNUSED",
        altpll_component.port_clk3               = "PORT_UNUSED",
        altpll_component.port_clk4               = "PORT_UNUSED",
        altpll_component.port_clk5               = "PORT_UNUSED",
        altpll_component.port_areset             = "PORT_UNUSED",
        altpll_component.port_activeclock        = "PORT_UNUSED",
        altpll_component.port_clkbad0            = "PORT_UNUSED",
        altpll_component.port_clkbad1            = "PORT_UNUSED",
        altpll_component.port_clkloss            = "PORT_UNUSED",
        altpll_component.port_clkswitch          = "PORT_UNUSED",
        altpll_component.port_configupdate       = "PORT_UNUSED",
        altpll_component.port_fbin               = "PORT_UNUSED",
        altpll_component.port_pfdena             = "PORT_UNUSED",
        altpll_component.port_phasecounterselect = "PORT_UNUSED",
        altpll_component.port_phasedone          = "PORT_UNUSED",
        altpll_component.port_phasestep          = "PORT_UNUSED",
        altpll_component.port_phaseupdown        = "PORT_UNUSED",
        altpll_component.port_pllena             = "PORT_UNUSED",
        altpll_component.port_scanaclr           = "PORT_UNUSED",
        altpll_component.port_scanclk            = "PORT_UNUSED",
        altpll_component.port_scanclkena         = "PORT_UNUSED",
        altpll_component.port_scandata           = "PORT_UNUSED",
        altpll_component.port_scandataout        = "PORT_UNUSED",
        altpll_component.port_scandone           = "PORT_UNUSED",
        altpll_component.port_scanread           = "PORT_UNUSED",
        altpll_component.port_scanwrite          = "PORT_UNUSED";

endmodule
