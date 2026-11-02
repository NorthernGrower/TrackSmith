# AI Music Studio — Web

A zero-build web version of the studio. It shares the app's dark, amber-accented
look and the same session model: tracks, clips, mixer, volume automation, piano
roll, looping, metronome and count-in, sessions, bounce and track freeze.

Everything runs locally in the browser with the Web Audio API. Sessions are kept
in `localStorage`, audio files live in IndexedDB, and nothing is uploaded.

## Running it

Open `index.html` from this folder in a browser (it needs to be served over
`http://` or `https://`, for example with any static file server, because the app
uses ES modules and IndexedDB).

## What it does

- Import audio stems or add a blank track, with waveform clips on a shared ruler.
- Track controls: mute, solo, fader, meter, freeze, equalizer, piano roll, volume
  automation.
- Transport: play/pause/stop, timecode, tempo, loop range and loop playback,
  metronome click with level, and a one-bar count-in.
- Named song sections marked on the ruler: add, drag, rename, delete, and tap
  one to jump the playhead there.
- Channel mixer with pan, faders, dB readouts, meters and a master strip.
- Master effects: tempo-synced delay and reverb on the master output, with a
  bypass switch, applied to playback and the bounce.
- Piano roll sequencer for the built-in synthesizer, snapped to the beat grid.
- Bounce the arrangement to a WAV file.

## Still iOS-only

Live microphone recording, the sampler sound library and on-device stem
separation are not part of the web version yet.
