# DIY foot pressure kit (~$40)

Six cheap pressure sensors, one Arduino, one USB cable. Tape the sensors to an insole (or a foot), plug in, click Connect in the sim, and watch live pressure.

## Shopping list

| Part | Qty | ~Price |
|---|---|---|
| Arduino Nano or Uno clone (or ESP32 dev board) | 1 | $8-12 |
| FSR sensors: Interlink FSR 402 ($7 each) or generic 0.5" round FSR (~$1.50 each, pack of 10) | 6 | $10-42 |
| 10k ohm resistors (1/4 W) | 6 | $1 |
| Breadboard + jumper wires (or 26 AWG hookup wire) | 1 | $6 |
| USB cable (mini/micro/C to match the board) | 1 | $4 |
| Cheap foam insole (or Dr. Scholl's style cutout) | 1 | $5 |
| Medical or kinesiology tape, masking tape | 1 | $5 |

Total: about $35-45 with generic FSRs, about $75 with genuine FSR 402s.

## Where the sensors go

Sole view, toes at top. Same spots on both feet (mirrored).

```
            .--.
           ( 6  )          1 Heel
        .-'`--'`-.         2 Outer midfoot
       /          \        3 Inner arch  <- the flat-foot sensor
      | 5      4   |       4 Big toe joint (1st metatarsal head)
       \          ./       5 Little toe joint (5th metatarsal head)
        |          |       6 Big toe
        |  2   3   |
        |          |       outer edge on the left,
         \        /        inner edge (arch side) on the right
          \  1   /
           '-..-'
```

Sensor 3 is the key one: a flat foot loads the inner arch, a normal arch barely does, a high arch not at all.

Positions in the sim's foot frame (mm, x toward the inner side, y heel to toe, foot about 240 mm long): Heel (2, 24), Outer midfoot (-24, 90), Inner arch (20, 96), Big toe joint (36, 161), Little toe joint (-32, 151), Big toe (40, 211). Defined in `sim/src/hardware/layout.ts`. Your foot differs a bit; close is fine.

## Wiring

Each sensor is a voltage divider: supply -> FSR -> analog pin -> 10k -> GND. Six copies.

```
 5V (Uno/Nano) or 3.3V (ESP32)
   |
  FSR  (either leg, polarity does not matter)
   |
   +------- analog pin (A0..A5)
   |
  10k
   |
  GND
```

| Sensor | Uno / Nano | ESP32 |
|---|---|---|
| 1 Heel | A0 | GPIO 32 |
| 2 Outer midfoot | A1 | GPIO 33 |
| 3 Inner arch | A2 | GPIO 34 |
| 4 Big toe joint | A3 | GPIO 35 |
| 5 Little toe joint | A4 | GPIO 36 |
| 6 Big toe | A5 | GPIO 39 |

Uno ADC is 10-bit (0-1023) at 5 V. ESP32 ADC is 12-bit (0-4095) at 3.3 V, and its readings are a bit nonlinear; fine for this. The firmware reports its ADC range so the browser adapts. Use thin wire long enough to reach the board from the foot (about 1 m).

## Steps

1. Solder or twist-and-tape a 10k resistor and the wires on each FSR as above. Test on the breadboard first.
2. Tape each sensor face-up on the insole at the numbered spots, with a small piece of tape over the whole sensor (not bunched up, the active disc should lie flat). Run the wires toward the heel and tape them down.
3. Install the Arduino IDE (or `arduino-cli`). Open `hardware/firmware/foot_sensor/foot_sensor.ino`, pick your board and port, upload. For ESP32, install the "esp32 by Espressif" board package first.
4. Open the Serial Monitor at 115200 baud. You should see `I,foot_sensor,6,1023` and then a stream of `P,...` lines. Press a sensor and watch its number rise. Close the Serial Monitor (only one program can use the port).
5. `cd sim && bun install && bun run dev`, open http://localhost:5173 in **Chrome or Edge** (Safari and Firefox have no Web Serial).
6. Click Connect, choose the Arduino port. Try the built-in demo device first if you want to see the UI with no hardware.

## Wear it

- Foam insole: tape sensors to the insole, put a thin sock over it (or the insole in a shoe, sensors up under the foot). Keep the tape flat and the wires out from under the foot.
- Bare foot: tape sensors directly to the sole of a standing person's foot, wires going up the ankle.

Quick calibration:

1. Foot off the ground: tare (zero the baseline).
2. Stand on both feet for 5 seconds, weight even.
3. Stand on one foot for 5 seconds, then the other. Sensors should read clearly higher than on two feet.
4. Optional max-normalize: after step 3, each sensor is scaled to its own peak, so sensors with different sensitivity look comparable. Re-do it if tape shifts.

In code: `sensor.calibrator.tare()`, `sensor.calibrator.normalize = true`, `sensor.calibrator.resetMax()` (serial devices only).

## Honest limits

Cheap FSRs are approximate. They drift, vary 20-30% between units, saturate around 10 N, and react to bending. Readings are good for relative patterns (is the arch loaded compared with the heel?), not for medical measurement. This is screening, not diagnosis.

## Serial protocol

115200 baud, newline-terminated text.

```
I,foot_sensor,6,<adcMax>        sent at boot, and again whenever the host sends any byte
P,<s1>,<s2>,<s3>,<s4>,<s5>,<s6>  raw ADC counts, about 50 per second, sensor order as numbered above
```

Anything else is ignored. Raw counts are converted to approximate kPa in `sim/src/hardware/calibrate.ts` (divider math, then a rough FSR 402 curve of about 100 uS per newton over the 127 mm^2 disc).

## Upgrade: full heatmap

For a real pressure image, build a Velostat matrix: two layers of parallel conductive strips (copper tape or conductive thread) crossing at right angles with a sheet of Velostat between them, 16x16 crossings. Scan it with analog multiplexers (two 16-channel CD74HC4067, about $4 each). It costs about $30 more and gives 256 points instead of 6. The sim's `LiveSensor` interface already takes any number of sensors with positions, so only a new firmware and layout are needed.

## Check without hardware

`bun hardware/tools/demo_check.ts` runs the demo device for 2 s per foot type and prints frame count and per-sensor max.
