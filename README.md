# YGTECH FPV TOOLS

Collection of my open source tools for FPV pilots.

## Author

A Chinese developer and FPV pilot (开发者 / FPV 飞手).

- Instagram: [yuan.fpv](https://instagram.com/yuan.fpv)
- WeChat: helloyuanyuan
- Douyin: helloyuanyuan

---

## AcroLED

Quickly switch VTX frequency channels and LED colors directly from your radio.

If your race needs more frequency / LED color combinations, please contact me.

### Install

1. Update your radio to EdgeTX **>= 2.12.0**.
2. Set **Mixer CH12 = GV1**.
3. Copy `AcroLED/AcroLED.lua` to the `SCRIPTS/TOOLS` folder on the radio's SD card.
4. Import `AcroLED/AcroLED-cli.txt` into your flight controller settings.

You're ready to go.

---

## AcroStick

Shows a real-time stick heatmap on your radio, plus statistics for full-throttle
count and average throttle.

### Install

1. Copy `AcroStick/AcroStick.lua` to the `SCRIPTS/TOOLS` folder on the radio's SD card.

That's it. After launching the tool, select your arm switch. Flip it to arm and
recording starts; disarm and recording stops.
