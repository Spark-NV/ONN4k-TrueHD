# onn 4K Pro TrueHD / Atmos passthrough

A Magisk module that gets the onn 4K Pro (2026) to send real Dolby TrueHD and
TrueHD Atmos to your receiver or soundbar over HDMI.

Out of the box the onn won't do it. Play a movie with a TrueHD Atmos track and
it gets converted to Dolby Digital Plus (or plain PCM) before it leaves the
box, so you lose the lossless audio. The hardware can handle it fine, it's
just turned off in the firmware. This module turns it back on.

It also brings back a few sound settings onn hid:

- a proper **Passthrough** mode you can switch on and off in Settings
- **Dolby DRC** (Line / RF) and **DTS DRC** (on / off)
- **Dolby preferred output** (MAT or DD+)

## Tested on

| | |
|---|---|
| Device | onn 4K Pro Streaming Device (2026), codename `jarvis2` |
| Chip | Amlogic S905X5M |
| Android | Android TV 14 (API 34) |
| Firmware | `URO3.260203.035.A1.15640252` |
| Security patch | 2026-06-01 |
| Kernel | `5.15.196-android14-11-g3d26c188ef7e-ab14657224` |
| Magisk | 30.7 |
| Audio setup | Samsung HW-Q910 soundbar through a Samsung Q90A TV (eARC) |
| Player | Just Player with audio passthrough on |

The module only installs on that exact firmware. On anything else (another box,
or the same box after an update) it tells you it's not supported and doesn't
change anything. If you get it working on another firmware, open an issue.

## Install

1. You need a rooted box with Magisk.
2. Flash `onn-truehd-passthrough-v1.0.zip` in Magisk and reboot.
3. About a minute after it boots, the sound will cut out for a second. That's
   the module kicking in.
4. Go to **Settings > Display & Sound > Audio output mode**. This opens onn's
   sound menu.
5. Open **Advanced sound settings > Select formats** and pick **Passthrough**.

That's it. Play something with a TrueHD Atmos track in Kodi or Just Player
(with passthrough turned on in the player) and your receiver should show
Dolby Atmos. Your choice is remembered across reboots. Pick **Automatic** to go
back to how onn does it.

To build the zip yourself, run `python3 build-zip.py`.

## Other settings it unlocks

In the same **Audio output mode** menu:

- **Dolby DRC Mode**: squashes the loud and quiet parts closer together. RF
  squashes more than Line, which is handy at night.
- **DTS DRC Mode**: the same thing for DTS.
- **Dialog Enhancer** and **Downmix Mode** were already there, there just
  wasn't any way to get to the menu.

Under **Settings > Display & Sound > Audio options**:

- **Dolby preferred output**: whether the box sends Dolby MAT or Dolby Digital
  Plus when it's re-encoding audio itself in Automatic mode.

These only matter when the box is decoding or re-encoding the audio. In
Passthrough the audio goes out exactly as it is in the file.

## How it works

Nothing on the system is permanently modified. Everything happens after the
box boots and is gone on the next reboot if the module is off.

- The HDMI multichannel audio link was capped at 96 kHz. TrueHD needs
  192 kHz. A small kernel module raises that limit in memory.
- The firmware already has a TrueHD switch, it's just turned off. The module
  turns it on, and turns off the setting that forces everything to DD+.
- TrueHD gets added to the surround format list in Settings.
- onn's Passthrough and DRC options are hidden behind flags in an audio config
  file. The module mounts a copy with those flags turned on.
- A new **Audio output mode** row in Display & Sound takes you to onn's sound
  menu, which normally has no way in.

The Magisk **Action** button opens the same sound menu and shows what the
module is doing. The log is at `/data/adb/onn_truehd/apply.log`.

## What doesn't work

- **96 kHz TrueHD** (rare, mostly music and some test files) plays as stereo
  PCM. That's Dolby's own code on the box failing. 48 kHz TrueHD, which is what
  movies use, works fine.
- **DTS-HD MA and DTS:X** aren't covered. My Samsung TV doesn't take DTS at
  all, so I couldn't test it.
- While TrueHD is playing in Passthrough you won't hear menu click sounds.
  That's normal for any box doing lossless passthrough.

## Removing it

Disable or remove it in Magisk and reboot. If you can't get into Magisk,
`adb shell su -c magisk --remove-modules` and reboot.

Your audio output mode setting stays saved after removal. If it was on
Passthrough, the stock firmware just goes back to sending DD+, so nothing
breaks. Set it to Automatic first if you want it fully stock.

## Source

- `module/` is the Magisk module itself.
- `src/kernel/` is the kernel helper (`t9015rate.ko`) and how to build it.
- `src/overlay/` is the Settings row overlay and its build script.

The kernel helper is GPL-2.0.
