//============================================================================
//  HT1080Z port to MiSTer
//  Renamed to TRS-80 after Cassette and CMD loading support
//  
//  Copyright (c) 2019 Alan Steremberg - alanswx
//
//
//============================================================================

localparam NBDRIV=5;
localparam VD = NBDRIV-1;

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	output	USER_OSD,
	// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: per-pin push-pull mask
	output	[7:0] USER_PP,
	// [MiSTer-DB9 END]
	input	[7:0] USER_IN,
	output	[7:0] USER_OUT,

	input         OSD_STATUS
);


// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: USER_PP default (port_batch replaces with USER_PP_DRIVE)
assign USER_PP = USER_PP_DRIVE;
// [MiSTer-DB9 END]
// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joydb wrapper
// CLK_JOY gated on mt32_disable (TRS-80 MT32 anti-contention pattern, see CLAUDE.md):
// when MT32 is enabled (mt32_disable=0) the wrapper helpers see a stopped clock
// so they cannot scan or drive the shared USER_IO pins.
wire         CLK_JOY = CLK_50M & mt32_disable; // 40-50MHz, gated by mt32_disable
wire   [1:0] joy_type        = status[127:126]; // 0=Off, 1=Saturn, 2=DB9MD, 3=DB15
wire         joy_2p          = status[125];
wire         joy_saturn_en   = (joy_type == 2'd1);
wire         joy_db9md_en    = (joy_type == 2'd2);
wire         joy_db15_en     = (joy_type == 2'd3);
wire         joy_any_en      = |joy_type;
// Legacy 3-bit alias for fork-specific MT32 / SNAC fallback code.
wire   [2:0] JOY_FLAG        = {joy_db9md_en, joy_db15_en, joy_2p};
// [MiSTer-DB9 END]

// [MiSTer-DB9-Pro BEGIN] - Saturn key gate
wire         saturn_unlocked;                   // driven by hps_io UIO_DB9_KEY (0xFE)
// [MiSTer-DB9-Pro END]

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joydb wrapper wires + instance
wire   [7:0] USER_OUT_DRIVE;
wire   [7:0] USER_PP_DRIVE;
wire  [15:0] joydb_1, joydb_2;
wire         joydb_1ena, joydb_2ena;
wire  [15:0] joy_raw_payload;

joydb joydb (
  .clk             ( CLK_JOY         ),
  .USER_IN         ( USER_IN         ),
  .joy_type        ( joy_type        ),
  .joy_2p          ( joy_2p          ),
  .saturn_unlocked ( saturn_unlocked ),
  .USER_OUT_DRIVE  ( USER_OUT_DRIVE  ),
  .USER_PP_DRIVE   ( USER_PP_DRIVE   ),
  .USER_OSD        ( USER_OSD        ),
  .joydb_1         ( joydb_1         ),
  .joydb_2         ( joydb_2         ),
  .joydb_1ena      ( joydb_1ena      ),
  .joydb_2ena      ( joydb_2ena      ),
  .joy_raw         ( joy_raw_payload )
);
// USER_OUT driven by always_comb below (composes wrapper output with MT32 fallback).
// [MiSTer-DB9 END]

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: USER_OUT compose with MT32 anti-contention
// TRS-80 MT32 anti-contention pattern (see CLAUDE.md "MT32-pi and USER_IO Pin
// Contention", TRS-80 section): gate every USER_OUT branch on mt32_disable so
// at boot (mt32_disable=0 by default until status loads) the MT32 fallback is
// not driven into shared USER_IO. When mt32_disable=1 the wrapper drives the
// joystick mode (DB9MD/DB15/Saturn/Off → USER_OUT_DRIVE).
always_comb begin
	USER_OUT = 8'hFF;
	if (~mt32_disable) begin
		USER_OUT[6:0] = USER_OUT_MT32;
	end else begin
		USER_OUT = USER_OUT_DRIVE;
	end
end
// [MiSTer-DB9 END]

// [MiSTer-DB9-Pro BEGIN] - DB controllers muted while OSD is open
wire [31:0] joystick_0 = joydb_1ena ? (OSD_STATUS ? 32'b0 : {16'b0, joydb_1}) : joystick_0_USB;
wire [31:0] joystick_1 = joydb_2ena ? (OSD_STATUS ? 32'b0 : {16'b0, joydb_2}) : joydb_1ena ? joystick_0_USB : joystick_1_USB;
// [MiSTer-DB9-Pro END]

assign VGA_F1=0;
assign HDMI_FREEZE = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;

// assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign DDRAM_CLK =  clk_sys ;
assign ADC_BUS  = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign BUTTONS = 0;

assign AUDIO_MIX = 0;

assign LED_DISK  = LED;				/* later add disk motor on/off */
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;

// Status Bit Map:
//             Upper                             Lower              
// 0         1         2         3          4         5         6   
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXXX        XXXXXXXXXX

`include "build_id.v"
localparam CONF_STR = {
	"TRS-80;SS3E000000:10000,UART31250:9600:4800:2400:1200:300:110,MIDI;",
	"S1,DSKJV1,Mount Disk 0:;",  // Don't use slot0 because it gets overwritten when using file FS3 below. Probably a MisterMain bug.
 	"S2,DSKJV1,Mount Disk 1:;",
 	"S3,DSKJV1,Mount Disk 2:;",
 	"S4,DSKJV1,Mount Disk 3:;",
	"-;",
	"F2,CMDBAS,Load Program;",
	"F1,CAS,Load Cassette;",
	"OLM,CMD Exec Method,CAS,JMP,NONE;",
	"-;",
	"FS3,SAV,Snapshot;",
	"D1OJK,Savestate Slot,1,2,3,4;",
	"D1RH,Load State;",
	"D1RI,Save State;",
	"-;",
	"P1,Display and MT32 Options;",
	"P1-,Display Options;",
	"P1-;",
	"P1O56,Screen Color,White,Green,Amber;",
	"P1OE,Video Flicker,Off,On;",
	"P1O7,Lowercase Type,Normal,Symbol;",
	"P1OCD,Overscan,None,Partial,Full;",
	"P1OF,Overscan Status Line,Off,On;",
	"P1O13,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1ON,TRS80 Skin,Off,On;",
	"P1-;",
	
	"P1o1,Use MT32-pi,No,Yes;",
	"P1o89,Show Info,No,Yes,LCD-On(non-FB),LCD-Auto(non-FB);",
	"P1o2,Synth,Munt,FluidSynth;",
	"P1o34,Munt ROM,MT-32 v1,MT-32 v2,CM-32L;",
	"P1o57,SoundFont,0,1,2,3,4,5,6,7;",
	"P1-;",
	"P1r0,Reset Hanging Notes;",
	
	"-;",
	// [MiSTer-DB9-Pro BEGIN] - Saturn-first joy_type (canonical bit notation)
	"O[127:126],UserIO Joystick,Off,Saturn,DB9MD,DB15;",
	"O[125],UserIO Players, 1 Player,2 Players;",
	// [MiSTer-DB9-Pro END]
	"-;",
	"O4,Kbd Layout,TRS-80,PC;",
	"OAB,TRISSTICK,None,BIG5,ALPHA;",
	"O89,Clockspeed (MHz),1.78(1x),3.56(2x),5.34(3x),21.29(12x);",
	"OO,Omikron CP/M,Off,On;",
//	"OP,Omikron Write,Off,On;",
	"-;",
	"RG,Erase memory and reset;",
	"R0,Reset;",
	"J,Fire;",
	"I,",
	"MT32-pi: SoundFont #0,",
	"MT32-pi: SoundFont #1,",
	"MT32-pi: SoundFont #2,",
	"MT32-pi: SoundFont #3,",
	"MT32-pi: SoundFont #4,",
	"MT32-pi: SoundFont #5,",
	"MT32-pi: SoundFont #6,",
	"MT32-pi: SoundFont #7,",
	"MT32-pi: MT-32 v1,",
	"MT32-pi: MT-32 v2,",
	"MT32-pi: CM-32L,",
	"MT32-pi: Unknown mode;",
	"V,v",`BUILD_DATE
};

wire clk_sys;
pll pll
(
	.refclk   (CLK_50M),
	.rst      (0),
	.outclk_0 (clk_sys) // 42 MHz
);

// [MiSTer-DB9 BEGIN] - widened to 128 bits for joy_type at [127:126] and joy_2p at [125]
wire [127:0] status;
// [MiSTer-DB9 END]
wire [15:0] menumask ;
wire  [1:0] buttons;
wire			cpum1;
wire        ioctl_download;
wire        ioctl_wr;
wire [15:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire  [15:0] ioctl_index;
wire	    ioctl_wait;
wire [31:0] sd_lba[NBDRIV];
wire [31:0] sd_lba_0;
wire  [VD:0] sd_rd;
wire  [VD:0] sd_wr;
wire  [VD:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din_0;
wire  [7:0] sd_buff_din[NBDRIV];
wire        sd_buff_wr;
wire  [4:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire        forced_scandoubler;
wire [10:0] ps2_key;

wire [21:0] gamma_bus;

wire [15:0] joystick_0_USB, joystick_1_USB;
wire [31:0] uart_speed;
wire [7:0] uart_mode;


hps_io #(.CONF_STR(CONF_STR), .WIDE(0), .VDNUM(NBDRIV) ) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joy_raw
	.joy_raw(OSD_STATUS ? joy_raw_payload : 16'b0),
	// [MiSTer-DB9 END]
	// [MiSTer-DB9-Pro BEGIN] - Saturn key gate
	.saturn_unlocked(saturn_unlocked),
	// [MiSTer-DB9-Pro END]
	.ps2_key(ps2_key),

	.joystick_0(joystick_0_USB),
	.joystick_1(joystick_1_USB),
	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.status(status),
	.status_menumask(menumask),
	.info_req(info_req),
	.info(info),
	
	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),
	.ioctl_index(ioctl_index),
	
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	
	 .uart_mode(uart_mode),
	 .uart_speed(uart_speed)
);

wire rom_download = ioctl_download && ioctl_index==0;
wire CPMreset = RESET | rom_download | omkr_reset;
wire reset = status[0] | buttons[1] | CPMreset ;

// signals from loader
wire loader_wr;		
wire loader_download;
wire [15:0] loader_addr;
wire [7:0] loader_data;
wire [15:0] execute_addr;
wire execute_enable;
wire loader_wait;
wire debug_select_line ; 
wire prev_status_15 ;
wire [15:0] dgb_min_addr;
wire [15:0] dgb_max_addr;
wire [15:0] prev_execute_addr;
wire old_omikron ;
wire omkr_reset ;
wire [3:0] omkr_ctr ; 


//(* preserve *) wire [31:0] iterations;
always_ff @(posedge clk_sys or posedge reset) begin
	if (reset) begin
		debug_select_line <= 1'b0 ; 
		prev_execute_addr <= execute_addr ;
		if (rom_download) menumask <= 16'h0002 ; // menumask[1]=1
	end else
	begin
		prev_status_15 <= status[15] ;
		prev_execute_addr <= execute_addr ;
		if ( (status[15] != prev_status_15) && (status[15] == 1'b0) ) begin // reset status line if OSD request to see debug
			debug_select_line <= ! debug_select_line  ;
		end
		if (execute_addr != prev_execute_addr) debug_select_line <= 1'b1 ;  // if exec_addr change, see it.
		if (ioctl_download && ioctl_wr && ioctl_index==3 && ioctl_addr[0] == 1'b1 ) menumask[1] <= 1'b0 ;
	end
end

always_ff @(posedge clk_sys) begin
		old_omikron <= status[24];
		if (old_omikron != status[24]) omkr_ctr <= 4'hf ;
		if (omkr_ctr != 4'h0) begin
			omkr_ctr <= omkr_ctr - 1 ;
			omkr_reset <= 1'b1 ;
		end  else omkr_reset <= 1'b0 ;
end

cmd_loader cmd_loader
(
	.clock(clk_sys),
	.reset(reset),
	.cpum1(cpum1),
	.erase_mem(status[16]),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_dout(ioctl_data),
	.ioctl_addr(ioctl_addr),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),
	
	.loader_wr(loader_wr),
	.loader_download(loader_download),
	.loader_addr(loader_addr),
	.loader_data(loader_data),
	.loader_din(trsram_din),
	.execute_addr(execute_addr),
	.execute_enable(execute_enable),
	.execute_method(status[22:21]),
	.exec_stack(exec_stack),
	.dbg_min_addr(dgb_min_addr),
	.dbg_max_addr(dgb_max_addr)
	
	
//	.iterations(iterations)		// Debugging only
);

wire trsram_wr;			// Writing loader data to ram 
wire trsram_rd;			// Reading loader data from ram 
wire trsram_download;	// Download in progress (active high)
wire [16:0] trsram_addr;
wire [7:0] trsram_data;
wire [7:0] trsram_din;

wire [15:0] dbg_min_addr ;
wire [15:0] dbg_max_addr ;
wire [15:0] exec_stack ;

assign trsram_wr = loader_download ? loader_wr : |ioctl_index[7:1]==1'b0 ?  ioctl_wr : 1'b0 ; // we don't want a spurious write if loader_download is late
assign trsram_rd = loader_download ;
assign trsram_download = loader_download ? loader_download : ioctl_index == 1 ? ioctl_download : 1'b0;
assign trsram_addr = loader_download ? {1'b0, loader_addr} : {|ioctl_index[7:0],ioctl_addr};
assign trsram_data = loader_download ? loader_data : ioctl_data;

wire LED;

// wire [1:0] fdc_wp = 2'b0;
wire       fdc_irq;
wire       fdc_drq;
wire [1:0] fdc_addr;
wire       fdc_sel;
wire       fdc_rw;
wire [7:0] fdc_din;
wire [7:0] fdc_dout;

wire [13:0] omkr_addr ;
wire [7:0]  omkr_data ;

// Map all such broken accesses to drive A only
//wire [1:0] floppy_sel = 2'b10;	// ** Need to change from code

//wire [1:0] floppy_sel_exclusive = (floppy_sel == 2'b00)?2'b10:floppy_sel;

//  Omikron alternate ROM loading 
dpram #(.DATA(8), .ADDR(11)) omikron_rom
(
    .a_clk(clk_sys),
    .a_wr(ioctl_wr & (ioctl_index[7:0]==8'h40)),  // file 0, rom 01 = Omikron
    .a_addr(ioctl_addr[10:0]),
    .a_din(ioctl_data),
   // .a_dout(),

    // Port B
    .b_clk(clk_sys),
    //.b_wr(omkr_wr),
    .b_wr(1'b0),
    .b_addr(omkr_addr[10:0]),
    .b_din(8'h00),
    .b_dout(omkr_data)
);

trs80 trs80
(
	.reset(reset),
	.clk42m(clk_sys),
	.cpum1_out(cpum1),
	.omikron(status[24]),
	.omkr_addr(omkr_addr),
	.omkr_data(omkr_data),
//	.omkr_wr(omkr_wr),
//	.omkr_write(status[25]),
	.reset_mapper(CPMreset),

	.joy0(joystick_0),
	.joy1(joystick_1),
	.joytype(status[11:10]),

	.RGB(RGB),
	.HSYNC(HSync),
	.VSYNC(VSync),
	.hblank(HBlank),
	.vblank(VBlank),
	.ce_pix(ce_pix),
	.skin(status[23]),

	.LED(LED),
	.audiomix(audiomix),

	.ps2_key(ps2_key),
	.kybdlayout(status[4]),
	.disp_color(status[6:5]),
	.lcasetype(status[7]),
	.overscan(status[13:12]),
	.overclock(status[9:8]),
	.flicker(status[14]),
	.debug(status[15]),
	
	.dn_clk(clk_sys),
	.dn_go(trsram_download),
	.dn_wr(trsram_wr),
	.dn_rd(trsram_rd),
	.dn_addr(trsram_addr),			// CPU = 0000-FFFF; cassette = 10000-1FFFF
	.dn_data(trsram_data),	
	.dn_din(trsram_din),

	.loader_download(loader_download),
	.execute_addr(execute_addr),
	.execute_enable(execute_enable),
	.execute_method(status[22:21]),
	.debug_select_line(debug_select_line),
	.exec_stack(exec_stack),
	.dbg_min_addr(dgb_min_addr),
	.dbg_max_addr(dgb_max_addr),

	.img_mounted(img_mounted[4:1]), // we avoid drive0, because it gets overrided if FS3 is opened ...
	.img_readonly(img_readonly),
	.img_size(img_size),

	.sd_lba(sd_lba_0),
	.sd_rd(sd_rd[4:1]),
	.sd_wr(sd_wr[4:1]),
	.sd_ack(sd_ack[4]|sd_ack[1]|sd_ack[2]|sd_ack[3]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_0),
	.sd_dout_strobe(sd_buff_wr),

	.UART_TXD(uart_tx),
	.UART_RXD(uart_rx),
	.UART_RTS(uart_rts),
	.UART_CTS(uart_cts),
	.UART_DTR(uart_dtr),
	.UART_DSR(uart_dsr),
	
	.uart_mode(uart_mode),   // 0=None, 1=PPP or Modem, 2=Console, 3=MIDI 
	.uart_speed(uart_speed),
	
	// .DDRAM_CLK(clk_sys),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),
	
	.load_state(status[17])	,
	.save_state(status[18]),
	.ss_slot(status[20:19])
	
);

////////////////////////////  UART  ////////////////////////////////////

/// UART1

wire uart_cts, uart_dcd, uart_dsr, uart_rts, uart_dtr;
wire uart_tx, uart_rx;
wire midi_tx, midi_rx;

wire hps_mpu = (uart_mode == 0 || mt32_use);

assign UART_RTS  = uart_rts;
assign UART_DTR  = uart_dtr;
assign uart_cts = UART_CTS;
assign uart_dcd = UART_DSR;
assign uart_dsr = UART_DSR;
assign uart_rx    = hps_mpu ? midi_rx : UART_RXD;
assign UART_TXD  = hps_mpu ? 1'b1 : uart_tx ;
assign midi_tx  = hps_mpu ? uart_tx : 1'b1;



assign sd_buff_din[0]=sd_buff_din_0;
assign sd_buff_din[1]=sd_buff_din_0;
assign sd_buff_din[2]=sd_buff_din_0;
assign sd_buff_din[3]=sd_buff_din_0;
assign sd_buff_din[4]=sd_buff_din_0;
assign sd_lba[0]=sd_lba_0;
assign sd_lba[1]=sd_lba_0;
assign sd_lba[2]=sd_lba_0;
assign sd_lba[3]=sd_lba_0;
assign sd_lba[4]=sd_lba_0;


///////////////////////////////////////////////////
wire        ce_pix;
wire [23:0] RGB;
wire        HSync,VSync,HBlank,VBlank;

wire  [2:0] scale = status[3:1];
wire  [2:0] sl = scale > 1'd1 ? scale - 1'd1 : 3'b000;
wire freeze_sync;

// aspect ratio including all border space is  4:3
// aspect ratio iwith partial border space is 20:17
// aspect ratio of only displayed area is     11:10
assign VIDEO_ARX = ~|status[13:12] ? 13'd4 : (status[12] ? 13'd40 : 13'd40);
assign VIDEO_ARY = ~|status[13:12] ? 13'd3 : (status[12] ? 13'd29 : 13'd28);

assign CLK_VIDEO = clk_sys;
assign VGA_SL = sl[1:0];

video_mixer #(.LINE_LENGTH(672), .GAMMA(1)) video_mixer
(
	.*,

	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale==3'b001),

	.R(mt32_lcd ? {{2{mt32_lcd_pix}},RGB[7:2]} : RGB[7:0]),
	.G(mt32_lcd ? {{2{mt32_lcd_pix}},RGB[15:10]} : RGB[15:8]),
	.B(mt32_lcd ? {{2{mt32_lcd_pix}},RGB[23:18]} : RGB[23:16])
//	.R(RGB[7:0]),
//	.G(RGB[15:8]),
//	.B(RGB[23:16])
);

assign sd_rd[0] = 1'b0 ;
assign sd_wr[0] = 1'b0 ;

reg [15:0] out_l, out_r;
always @(posedge CLK_AUDIO) begin
	reg [16:0] tmp_l, tmp_r;

	tmp_l <= {1'b0, audiomix, 7'b0000000 } + (mt32_mute ? 17'd0 : {mt32_i2s_l[15],mt32_i2s_l});
	tmp_r <= {1'b0, audiomix, 7'b0000000 } + (mt32_mute ? 17'd0 : {mt32_i2s_r[15],mt32_i2s_r});

	// clamp the output
	out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];
	out_r <= (^tmp_r[16:15]) ? {tmp_r[16], {15{tmp_r[15]}}} : tmp_r[15:0];
end

wire  [8:0] audiomix;

assign AUDIO_S=1 ;
assign AUDIO_L=out_l ;
assign AUDIO_R=out_r;

//  MT32 stuff
//	Shamelessly copied from AtariST

////////////////////////////  MT32pi  ////////////////////////////////// 

wire        mt32_reset    = status[32] | reset;
wire        mt32_disable  = ~status[33];
wire        mt32_mode_req = status[34];
wire  [1:0] mt32_rom_req  = status[36:35];
wire  [7:0] mt32_sf_req   = status[39:37];
wire  [1:0] mt32_info     = status[41:40];

wire [15:0] mt32_i2s_r, mt32_i2s_l;
wire  [7:0] mt32_mode, mt32_rom, mt32_sf;
wire        mt32_lcd_en, mt32_lcd_pix, mt32_lcd_update;

wire mt32_newmode;
wire mt32_available;
wire mt32_use  = mt32_available & ~mt32_disable;
wire mt32_mute = mt32_available &  mt32_disable;

wire [6:0] USER_IN_MT32 = mt32_disable ? 1 : USER_IN[6:0];
wire [6:0] USER_OUT_MT32;
mt32pi mt32pi
(
	.*,
	.USER_IN(USER_IN_MT32),
	.USER_OUT(USER_OUT_MT32),
	.reset(mt32_reset),
	.CE_PIXEL(mt32_ce_pix)

);

wire  [4:0] mt32_cfg = (mt32_mode == 'hA2) ? {mt32_sf[2:0],  2'b10} :
                       (mt32_mode == 'hA1) ? {mt32_rom[1:0], 2'b01} : 5'd0;

reg mt32_lcd_on;
always @(posedge CLK_VIDEO) begin
	int to;
	reg old_update;

	old_update <= mt32_lcd_update;
	if(to) to <= to - 1;

	if(mt32_info == 2) mt32_lcd_on <= 1;
	else if(mt32_info != 3) mt32_lcd_on <= 0;
	else begin
		if(!to) mt32_lcd_on <= 0;
		if(old_update ^ mt32_lcd_update) begin
			mt32_lcd_on <= 1;
			to <= 96000000 * 2;
		end
	end
end

wire mt32_lcd = mt32_lcd_on & mt32_lcd_en;

reg mt32_ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [1:0] div;

	div <= div + 1'd1;
	if(div == 2) div <= 0;

	mt32_ce_pix <= 0;
	if(!div) mt32_ce_pix <= ce_pix;
end


/* ------------------------------------------------------------------------------ */

reg [7:0] info;
reg       info_req = 0;
always @(posedge clk_sys) begin
	reg old_mode;
	reg old_mt32mode;

	old_mt32mode <= mt32_newmode;
	info_req <=  ((old_mt32mode ^ mt32_newmode) && (mt32_info == 1));

	info <= (mt32_mode == 'hA2)                  ? (8'd1 + mt32_sf[2:0]) :
           (mt32_mode == 'hA1 && mt32_rom == 0) ?  8'd9 :
           (mt32_mode == 'hA1 && mt32_rom == 1) ?  8'd10 :
           (mt32_mode == 'hA1 && mt32_rom == 2) ?  8'd11 : 8'd12;
end



endmodule
