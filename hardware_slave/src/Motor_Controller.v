`timescale 1ns / 1ps

// ============================================================
// PWM_Generator (9-bit) with prescaler DIV
// - reset active-high (match with Motor_Controller)
// - PWM freq = CLK_HZ / (DIV * 512)
//   Example: CLK_HZ=125MHz, DIV=25 => ~9.77 kHz
// ============================================================
module PWM_Generator #(
    parameter integer DIV = 25
)(
    input  wire       clk,
    input  wire       reset,        // active high
    input  wire [8:0] duty,         // 9-bit duty cycle
    output reg        pwm_out
);
    reg [15:0] div_cnt;
    reg [8:0]  counter;             // 9-bit counter

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            div_cnt <= 16'd0;
            counter <= 9'd0;
            pwm_out <= 1'b0;
        end else begin
            if (div_cnt == DIV-1) begin
                div_cnt <= 16'd0;
                counter <= counter + 9'd1;
            end else begin
                div_cnt <= div_cnt + 16'd1;
            end
            pwm_out <= (counter < duty);
        end
    end
endmodule


// ============================================================
// Motor_Controller: decode cmd_nibble -> duty + direction + PWM
// cmd_nibble: [3:2]=speed, [1:0]=steer
// steer mapping:
//   00=forward, 10=left, 01=right
// ============================================================
module Motor_Controller(
    input  wire       clk,
    input  wire       reset,            // active high
    input  wire [3:0] cmd_nibble,       // [3:2]=speed, [1:0]=steer

    output reg        motor_in1,
    output reg        motor_in2,
    output reg        motor_in3,
    output reg        motor_in4,
    output wire       motor_pwm_a,      // -> L298N ENA
    output wire       motor_pwm_b       // -> L298N ENB
);
    wire [1:0] speed = cmd_nibble[3:2];
    wire [1:0] steer = cmd_nibble[1:0];

    // -------- Reverse Mode (Moving Backward) --------
    wire reverse = (speed == 2'b11);    // turn on Reverse Mode when speed == 2'b11 

    // speed -> duty (9-bit)
    reg [8:0] base_duty;
    always @(*) begin
        case (speed)
            2'b00: base_duty = 9'd0;    // Stop
            2'b01: base_duty = 9'd400;  // Normal
            2'b10: base_duty = 9'd510;  // Fast
            2'b11: base_duty = 9'd400;  // Reverse Mode with normal speed
            default: base_duty = 9'd0;
        endcase
    end

    // steer -> duty mix (A=Left, B=Right)
    reg [8:0] duty_a, duty_b;
    always @(*) begin
        duty_a = 9'd0;
        duty_b = 9'd0;

        if (base_duty == 0) begin
            duty_a = 9'd0;
            duty_b = 9'd0;
        end else begin
            case (steer)
                2'b00: begin // Forward
                    duty_a = base_duty;
                    duty_b = base_duty;
                end
                2'b10: begin // Left: Run the right motor only
                    duty_a = 9'd0;
                    duty_b = base_duty;
                end
                2'b01: begin // Right: Run the left motor only
                    duty_a = base_duty;
                    duty_b = 9'd0;
                end
                default: begin
                    duty_a = base_duty;
                    duty_b = base_duty;
                end
            endcase
        end
    end

    // Direction Pins: Forward or Backward. Stop => All 0.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            motor_in1 <= 1'b0; motor_in2 <= 1'b0;
            motor_in3 <= 1'b0; motor_in4 <= 1'b0;
        end else begin
            if (base_duty == 0) begin
                // Stop
                motor_in1 <= 1'b0; motor_in2 <= 1'b0;
                motor_in3 <= 1'b0; motor_in4 <= 1'b0;
            end else if (!reverse) begin
                // Moving Forward   (IN1 = IN3 = 1 and IN2 = IN4 = 0)
                motor_in1 <= 1'b1; motor_in2 <= 1'b0;
                motor_in3 <= 1'b1; motor_in4 <= 1'b0;
            end else begin
                // Moving Backward  (reverse IN1/IN3 and IN2/IN4 => IN1 = IN3 = 0 and IN2 = IN4 = 1)
                motor_in1 <= 1'b0; motor_in2 <= 1'b1;
                motor_in3 <= 1'b0; motor_in4 <= 1'b1;
            end
        end
    end

    PWM_Generator #(.DIV(25)) u_pwm_a (
        .clk(clk), .reset(reset), .duty(duty_a), .pwm_out(motor_pwm_a)
    );

    PWM_Generator #(.DIV(25)) u_pwm_b (
        .clk(clk), .reset(reset), .duty(duty_b), .pwm_out(motor_pwm_b)
    );

endmodule