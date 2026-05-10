// DReg
module DReg #(parameter N = 4) (input clk, reset, input [N-1:0] D, output logic [N-1:0] Q);
	always_ff @(posedge clk) begin
		if (reset)
			Q <= {N{1'b0}};
		else	
			Q <= D;
	end
endmodule

// BAUD rate
module BAUD_rate_gen #(parameter CLOCK_FREQ = 100, parameter BAUD_RATE = 10)(input clk, reset, output logic baud_tick);
localparam int BAUD_Div = (CLOCK_FREQ / BAUD_RATE); // 100 /10 = 10 (4 bits)
localparam int Count_Width = 4; // goes up to 15 but need 10
localparam [Count_Width-1:0] BAUD_MAX = BAUD_Div - 1; // setting MAX to 10-1 = 9
logic [Count_Width-1:0] Count, N_Count;
	always_comb begin
		N_Count = Count;
		if (Count == BAUD_MAX)  // count up to "9" (BAUD Div = 1-10)
			N_Count = {Count_Width{1'b0}}; // if 9 reset to "0"
		else
			N_Count = Count + 1'b1; // if not, increment by 1
		end
DReg #(Count_Width) R (clk, reset, N_Count, Count);
assign baud_tick = (Count == BAUD_MAX) ? 1'b1 : 1'b0; // 1 when count = 9
endmodule

// UART: RS, LD, TX
module UART_tx (input clk, reset, baud_tick, tx_start, input [7:0] tx_data, output logic tx, tx_busy);
localparam [1:0] RS = 2'b00; // Reset / Idle
localparam [1:0] LD = 2'b01; // Load Buffer
localparam [1:0] TX = 2'b10; // Transmit serial bits
logic [1:0] State, N_State; // FSM state
logic [9:0] Buffer, N_Buffer; // stop(1), data[7:0], start(0)
logic [3:0] Bit_Counter, N_Bit_Counter; // counter to 10 (0-9)
	always_comb begin
		N_State = State; //default to hold state
		N_Buffer = Buffer; // default to hold buffer
		N_Bit_Counter = Bit_Counter; // default hold index
		tx = (State == TX) ? Buffer[Bit_Counter] : 1'b1; // idle 1 
		tx_busy = (State != RS)? 1'b1: 1'b0; // 1 in LD and TX but 0 in RS
	case (State)
		RS : begin
			N_Bit_Counter = 4'd0; // index starts at 0 
			if (tx_start && !tx_busy)  // if start and not busy then move to LD
				N_State = LD; // move to LD load the buffer
			end
		LD : begin
			N_Bit_Counter = 4'd0; // begin at bit 0
			N_Buffer = {1'b1, tx_data, 1'b0}; // stop = 1, data [7:0], start = 0
			if (baud_tick && tx_busy)  // if tick and is busy then move to TX
				N_State = TX; //BAUD tick and put 1 to busy, then move to TX
			end
		TX : begin
			if (baud_tick) begin
				if (Bit_Counter == 4'd9) begin // last bit = stop bit 
					N_Bit_Counter = 4'd0; // prepare for next load
					tx_busy = 1'b0; // set busy to 0 here
					N_State = LD; // move back to LD to load again
				end else begin
					N_Bit_Counter = Bit_Counter + 4'd1; // go next bit
				end
			end
		end
		default: begin 
			N_State = RS;
			N_Bit_Counter = 4'd0;
		end
	endcase
	end
DReg#(2) S (clk, reset, N_State, State);
DReg#(10) B (clk, reset, N_Buffer, Buffer);
DReg#(4) C (clk, reset, N_Bit_Counter, Bit_Counter);
endmodule

//UART_rx
module UART_rx (input clk, reset, rx, baud_tick, output logic [7:0] rx_data, output logic rx_ready);
localparam [1:0] RST = 2'b00; //reset
localparam [1:0] DET = 2'b01; // Detect start bit
localparam [1:0] REC = 2'b10; 
logic [1:0] State, N_State;
logic [9:0] Buffer, N_Buffer;
logic [3:0] Bit_Counter, N_Bit_Counter;
logic receiving, N_receiving, N_rx_ready;
logic [7:0] N_rx_data;
	always_comb begin
		//default
		N_State = State; // Next state is state unless changed
		N_Buffer = Buffer; // hold shift
		N_Bit_Counter = Bit_Counter; // hold current index 0-9
		N_receiving = receiving; 
		N_rx_data = rx_data; // hold previous rx_data
		N_rx_ready = 1'b0;
	case (State)
		RST : begin
			N_Bit_Counter = 4'd0; // start bit index at 0
				if ((rx == 1'b0) && (receiving == 1'b0)) begin
					N_receiving = 1'b1;
					N_rx_ready = 1'b0;
					N_State = DET;
				end
		end
		DET : begin
			N_Bit_Counter = 4'd0;
			if (rx == 1'b0) begin
				N_receiving   = 1'b1;
				N_State = REC;
			end else begin
				N_receiving = 1'b1;
				N_State = DET;
			end
		end
		REC :  begin
			if (baud_tick == 1'b1) begin
				N_Buffer[Bit_Counter] = rx; // if BAUD = 1 then sample bit is current bit
				if (Bit_Counter == 4'd9) begin //10 bit frame 
					N_rx_data = N_Buffer[8:1]; //  1 - 8 is for data, bit 0 is start and MSB bit 9 is for stop bit
					N_rx_ready = 1'b1; // rx_ready = 1 for 1 cycle to show done and data is good
					N_Bit_Counter = 4'd0; // reset for new frame
					N_receiving = 1'b0; // show done (no longer inside a frame)
					N_State = DET; //go back to detect next start bit
				end else begin
					N_Bit_Counter = Bit_Counter + 4'd1; // go to capture next bit on the next BAUD tick
				end
			end
		end
		default: begin
			N_State        = RST;
			N_Bit_Counter  = 4'd0;
			N_receiving    = 1'b0;
		end
	endcase
	end 
DReg #(2) S (clk, reset, N_State, State);
DReg #(10) B (clk, reset, N_Buffer, Buffer);
DReg #(4) C (clk, reset, N_Bit_Counter, Bit_Counter);
DReg #(1) R (clk, reset, N_receiving, receiving); // but be true until it is done collecting all 10 bits
DReg #(8) Rd (clk, reset, N_rx_data, rx_data); // needed to hold the bits until next frame
DReg #(1) NR (clk, reset, N_rx_ready, rx_ready); // for storing rx_ready to show full byte is ready
endmodule

// Hex 7 Seg
module Hex7Seg (input [3:0] hex, output logic [6:0] HexSeg);
	always_comb begin
		HexSeg = 7'b0000000;
		case (hex)
//			0
			4'h0 : begin
				HexSeg[6] = 1'b1;
			end
//			1
			4'h1 : begin
				HexSeg [0] = 1'b1; HexSeg [3] = 1'b1; HexSeg [4] = 1'b1; HexSeg [5] = 1'b1; HexSeg [6] = 1'b1;
			end
//			2
			4'h2 : begin
				HexSeg [2] = 1'b1; HexSeg [5] = 1'b1;
			end
//			3
			4'h3 : begin
				HexSeg [4] = 1'b1; HexSeg [5] = 1'b1;
			end
//			4
			4'h4 : begin
				HexSeg [0] = 1'b1; HexSeg [3] = 1'b1; HexSeg [4] = 1'b1;
			end
//			5
			4'h5 : begin
				HexSeg [1] = 1'b1; HexSeg [4] = 1'b1;
			end
//			6
			4'h6 : begin
				HexSeg [1] = 1'b1;
			end
//			7
			4'h7 : begin
				HexSeg [3] = 1'b1; HexSeg [4] = 1'b1; HexSeg [5] = 1'b1; HexSeg [6] = 1'b1;
			end
//			8
			4'h8 : begin
			end
//			9
			4'h9 : begin
				HexSeg [4] = 1'b1;
			end
		default : begin
		HexSeg = 7'b0000000;
		end
		endcase
	end
endmodule
	
// UART Test Bench
module UART_TB;
logic clk, reset;
	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk; 
	end
logic baud_tick, tx, tx_start, tx_busy, rx_ready;
logic [7:0] tx_data, rx_data;
localparam [7:0] Bits1 = 8'h20; // ASU ID: 1229362045
localparam [7:0] Bits2 = 8'h45;
	initial begin
		reset = 1'b1;
		tx_start = 1'b0;
		tx_data = 8'h00;
		repeat (2) @(posedge clk);
		reset = 1'b0;
// 1
		@(posedge clk);
		tx_data = Bits1;
		tx_start = 1'b1;
		@(posedge clk);
		tx_start = 1'b0;
		@(posedge rx_ready);
		$display("RX Bits 1 = 0x%h", rx_data);
// 2
		@(posedge clk);
		tx_data = Bits2;
		tx_start = 1'b1;
		@(posedge clk);
		tx_start = 1'b0;
		@(posedge rx_ready);
		$display("RX Bits 2 = 0x%h", rx_data);
//done
		repeat (10) @(posedge clk);
		$stop;
	end
BAUD_rate_gen #(100, 10) B (clk, reset, baud_tick);
UART_tx TX (clk, reset, baud_tick, tx_start, tx_data, tx, tx_busy);
logic rx; assign rx = tx;
UART_rx RX (clk, reset, rx, baud_tick, rx_data, rx_ready);
endmodule

// UART pv
module UART_pv (input clk, reset, sel, output logic tx_busy, rx_ready, rx, output [6:0] HEX0, HEX1); 

logic baud_tick, tx_start, tx; 
BAUD_rate_gen #(100,10) B (clk, reset, baud_tick); 

logic [7:0] tx_data, rx_data; 
assign tx_data = (sel) ? 8'h45 : 8'h20; 
assign rx = tx; 
assign tx_start = 1'b1; 
UART_tx TX (clk, reset, baud_tick, tx_start, tx_data, tx, tx_busy); 
UART_rx RX (clk, reset, rx, baud_tick, rx_data, rx_ready); 

Hex7Seg D0 (rx_data[7:4], HEX1); 
Hex7Seg D1 (rx_data[3:0], HEX0); 
endmodule