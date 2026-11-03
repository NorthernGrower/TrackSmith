# AI Music Studio — Web

A zero-build web version of the studio. It shares the app's dark, amber-accented
look and its core session workflows: tracks, clips, mixer, automation, piano roll,
looping, metronome, buses, templates, bounce options, instruments and track freeze.

Everything runs locally in the browser with the Web Audio API. Sessions are kept
in `localStorage`, audio files live in IndexedDB, and nothing is uploaded. There
is no Flash, Java or plugin involved — sound uses the browser's built-in audio
engine, which works in Safari on iPhone.

## Running it

Open `index.html` from this folder in a browser (it needs to be served over
`http://` or `https://`, for example with any static file server, because the app
uses ES modules and IndexedDB).

It is also published with GitHub Pages by the `Deploy web studio` workflow, so
the repository's Pages address serves this folder directly once Pages is set to
build from GitHub Actions.

## What it does

- Import MP3 or WAV audio (plus other browser-supported formats) or add a blank/instrument layer, with waveform clips on a shared ruler.
- On an empty install, start with the eight-bar “Night Drive” house demo split into Kick, Snare & Clap, Hi-Hats, Bass, Chords and Lead tracks.
- Track controls: mute, solo, fader, meter, freeze, equalizer, piano roll, and
  volume or pan automation lanes.
- Transport: play/pause/stop, timecode, tempo, loop range and loop playback,
  metronome click with level, and a one-bar count-in.
- Named song sections marked on the ruler: add, drag, rename, delete, and tap
  one to jump the playhead there.
- Channel presets: save a track's EQ, compressor, pan and level on device and
  apply it to any other track.
- Channel mixer with pan, faders, dB readouts, meters, a master strip and named buses with group level, mute and solo.
- Save custom session templates with track order, colours, level, pan, EQ and compression; reuse or delete them from Templates.
- Master effects: tempo-synced delay and reverb on the master output, with a
  bypass switch, applied to playback and the bounce.
- Piano roll sequencer for the built-in synthesizer, with chord mode, per-note velocity and multi-note quantize with adjustable strength.
- Instruments rack: a playable synth, the 808-style drum pads and hardware-style
  rotary controls, a TB-303 acid bass with tuned rotary controls, and a sampler for
  bundled starter sounds, session audio or device files. Record performances as
  clips on the selected track.
- Bounce the mix or stems as 16/24-bit WAV or supported-browser M4A, choose sample rate and file name, and optionally normalize. Settings are remembered locally.

## Bundled sounds

The `sounds` folder holds the free, CC0 starter sounds that also ship with the
iOS app (see the app's `Starter Sounds/CREDITS.md`); the sampler can load them
straight from the page.

## Still iOS-only

Live microphone recording and on-device stem separation are not part of the web
version yet.
