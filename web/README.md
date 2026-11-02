# AI Music Studio — Web

A zero-build web version of the studio. It shares the app's dark, amber-accented
look and the same session model: tracks, clips, mixer, volume and pan
automation, piano roll, looping, metronome and count-in, sessions, bounce and
track freeze.

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

- Import audio stems or add a blank track, with waveform clips on a shared ruler.
- Track controls: mute, solo, fader, meter, freeze, equalizer, piano roll, and
  volume or pan automation lanes.
- Transport: play/pause/stop, timecode, tempo, loop range and loop playback,
  metronome click with level, and a one-bar count-in.
- Named song sections marked on the ruler: add, drag, rename, delete, and tap
  one to jump the playhead there.
- Channel presets: save a track's EQ, compressor, pan and level on device and
  apply it to any other track.
- Channel mixer with pan, faders, dB readouts, meters and a master strip.
- Master effects: tempo-synced delay and reverb on the master output, with a
  bypass switch, applied to playback and the bounce.
- Piano roll sequencer for the built-in synthesizer, snapped to the beat grid.
- Instruments rack: a playable synth, the 808-style drum pads, a TB-303 acid bass
  and a sampler that loads the bundled starter sounds, a session's own audio or a
  file from the device, all played through the selected track's mixer.
- Bounce the arrangement to a WAV file, or export every track as its own stem
  through its mixer settings and the master.

## Bundled sounds

The `sounds` folder holds the free, CC0 starter sounds that also ship with the
iOS app (see the app's `Starter Sounds/CREDITS.md`); the sampler can load them
straight from the page.

## Still iOS-only

Live microphone recording and on-device stem separation are not part of the web
version yet.
