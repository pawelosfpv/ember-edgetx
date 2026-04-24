# Ember for EdgeTX

FPV muscle-memory drills that run on your transmitter.

Inspired by the [Ember iOS app](https://github.com/pawelosfpv/ember), this is a native EdgeTX Tool that uses your real sticks, not a phone screen.

## Requirements

- RadioMaster TX16S Mk II (other color-LCD 480×272 radios may work but are untested)
- EdgeTX 2.7.1 or newer

## Install

1. Connect your radio's SD card to your computer.
2. Copy the `SCRIPTS/` folder from this repo onto the SD card, merging with what's already there.
3. Eject, reboot the radio.
4. `SYS` (hold) → `Tools` → `Ember`.

## Drills (v1)

- **Gimbal Snap** — both sticks, X-axis. Snap left, right, left, right. Release-outside-target breaks combo.
- **Offset Chase** — channel-based flight pattern (throttle heavy, pitch/yaw subtle). Tracks % on-target + longest both-on streak.
- **Corner Storm** — cycle four corners with both sticks together.

## Scoring

Discrete drills (Gimbal Snap, Corner Storm): hit-chain combo. Each hit adds `currentCombo + 1` points, then combo increments. Miss breaks combo.

Tracking drills (Offset Chase): 10 pts/sec while one stick is on, 25 pts/sec while both are on, plus 20 pts per second of longest both-on streak.

## Controls

- **EXIT** during a drill → abort (no score saved).
- **EXIT** on completion screen → back to drill picker.
- **EXIT** on drill picker → back to system.

## Bests

Stored in plain text at `/SCRIPTS/TOOLS/ember/bests.txt`. One line per drill. Delete the file to reset.

## License

MIT. Fork, remix, ship.
