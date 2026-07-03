# Electron POC

The original Electron proof-of-concept for this project's desktop overlay agent. It
validated the concept (transparent full-screen click-through window, floats over other
windows, roams the screen, emotions, drag) but costs ~150 MB RAM for a tiny animated
sprite.

Kept here, working, for side-by-side comparison against the native Swift/AppKit port in
`../native/` and as the RAM baseline to beat. Slated for removal once the native port
reaches parity — see `../native/README.md` and the plan history.

## Run

```
make install
make start
```
