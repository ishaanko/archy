// Foot pressure sensor: 6 FSRs, each in a divider with a 10k resistor to GND.
// Wiring per sensor: 3.3V/5V -> FSR -> analog pin -> 10k -> GND.
// Output at 115200 baud, ~50 Hz:
//   I,foot_sensor,6,<adcMax>   once at startup (and when you send any byte)
//   P,<a0>,<a1>,<a2>,<a3>,<a4>,<a5>   raw ADC, one line per sample
// Sensor order: 0 Heel, 1 Outer midfoot, 2 Inner arch, 3 Big toe joint, 4 Little toe joint, 5 Big toe.

#if defined(ESP32)
const uint8_t PINS[6] = {32, 33, 34, 35, 36, 39};  // ADC1 pins, 12-bit, 3.3 V
const int ADC_MAX = 4095;
#else
const uint8_t PINS[6] = {A0, A1, A2, A3, A4, A5};  // Uno/Nano, 10-bit, 5 V
const int ADC_MAX = 1023;
#endif

const unsigned long PERIOD_MS = 20;  // 50 Hz
unsigned long next = 0;

void sendInfo() {
  Serial.print("I,foot_sensor,6,");
  Serial.println(ADC_MAX);
}

void setup() {
  Serial.begin(115200);
#if defined(ESP32)
  analogReadResolution(12);
#endif
  delay(100);
  sendInfo();
}

void loop() {
  if (Serial.available()) {  // any byte from the browser re-sends the header
    while (Serial.available()) Serial.read();
    sendInfo();
  }
  unsigned long now = millis();
  if ((long)(now - next) < 0) return;
  next = now + PERIOD_MS;

  Serial.print('P');
  for (uint8_t i = 0; i < 6; i++) {
    Serial.print(',');
    Serial.print(analogRead(PINS[i]));
  }
  Serial.println();
}
