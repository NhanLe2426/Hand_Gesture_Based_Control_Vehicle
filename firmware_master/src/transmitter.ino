#include <SPI.h>
#include <RF24.h>

// --- Hardware Pins Configuration ---
#define PIN_X A0  // ADXL335 X-axis output
#define PIN_Y A1  // ADXL335 Y-axis output

// --- NRF24L01 Configuration ---
#define CE_PIN  8
#define CSN_PIN 10
RF24 radio(CE_PIN, CSN_PIN);
const byte address[6] = "1Node";

// --- State Variables ---
int speed_bits = 0;   // Bits [3:2]: 00=Stop, 01=Normal, 10=Fast, 11=Reverse
int steer_bits = 0;   // Bits [1:0]: 00=Forward, 10=Left, 01=Right
bool y_armed = true;  // Flag for Y-axis state management

void setup() {
  Serial.begin(115200);
  while (!Serial) {}

  // Initialize NRF24L01 module
  if (!radio.begin()) {
    Serial.println("radio.begin() FAILED");
    while (1) {}
  }

  // --- NRF24 Settings (Must match FPGA Receiver) ---
  radio.setChannel(76);
  radio.setDataRate(RF24_1MBPS);
  radio.setCRCLength(RF24_CRC_16);
  radio.setPayloadSize(32);
  radio.setPALevel(RF24_PA_LOW);
  
  // Test mode: Disable ACK to avoid depending on receiver's ACK
  radio.setAutoAck(false);

  radio.openWritingPipe(address);
  radio.stopListening();

  Serial.println("TX ready");
}

void loop() {
  // ---------------------------------------------
  // 1. Get data from hand gestures (ADXL335)
  // ---------------------------------------------
  int xVal = analogRead(PIN_X);
  int yVal = analogRead(PIN_Y);

  // Arm the Y-axis when the hand is in neutral position
  if (yVal >= 300 && yVal <= 420) {
    y_armed = true;
  }

  // ---------------------------------------------
  // 2. SPEED PROCESSING (Based on Y-axis - Forward/Backward Tilt)
  // Logic: 00=Stop, 01=Normal, 10=Turbo (Fast), 11=Reverse
  // ---------------------------------------------
  if (yVal > 420) { 
    // Tilt Forward -> GO FORWARD (Increase speed up to Turbo mode)
    if (speed_bits < 2) {
      speed_bits++;
    } else if (speed_bits == 3) {
      speed_bits = 0;
    }
    y_armed = false;
  } 
  else if (yVal < 300) {
    // Tilt Backward -> GO BACKWARD (Or decrease speed)
    if (speed_bits == 0) {
      speed_bits = 3;
    } else if (speed_bits != 3) {
      speed_bits--;
    }
    y_armed = false;
  } 

  // ---------------------------------------------
  // 3. STEERING PROCESSING (Based on X-axis - Left/Right Tilt)
  // Logic: 00=Straight, 10=Left, 01=Right
  // ---------------------------------------------
  if (xVal < 300) {
    // Tilt to the left
    steer_bits = 2; // 10: Left
  } 
  else if (xVal > 400) {
    // Tilt to the right
    steer_bits = 1; // 01: Right
  } 
  else {
    // Neutral position -> GO STRAIGHT
    steer_bits = 0; // 00: Straight
  }

  // ---------------------------------------------
  // 4. PACK & SEND DATA (Payload[0])
  // ---------------------------------------------
  uint8_t payload[32] = {0};
  
  // Bitwise packing: Speed [Bits 3:2] | Steer [Bits 1:0]
  uint8_t command = (speed_bits << 2) | steer_bits;
  payload[0] = command;

  radio.write(payload, 32);

  // ---------------------------------------------
  // 5. DEBUG SECTION
  // ---------------------------------------------
  Serial.print("Tilt X: ");
  Serial.print(xVal);
  Serial.print(" | Tilt Y: ");
  Serial.print(yVal);
  Serial.print(" -> CMD: "); 
  
  // Print with leading zeros to ensure a 4-bit binary format (0000..1111)
  if (command < 8) Serial.print('0');
  if (command < 4) Serial.print('0');
  if (command < 2) Serial.print('0');
  Serial.println(command, BIN);
  
  delay(100);
}