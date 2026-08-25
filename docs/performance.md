# Performance

Background work only runs when it has something to do. CPU sits near zero when nothing is
happening and rises with what is on screen: a playing track costs about four times idle,
and the media visualizer costs more than everything else combined. Once the session goes
idle, or the bar steps aside for the compositor overview, every animation stops on its own
until you come back.

## Reference numbers

Idle use on a reference session measured **under 1% of one CPU core** and **95-110 MB PSS**,
holding in that band across a day of uptime. An empty Quickshell panel doing nothing
measured about **57 MB PSS** on the same machine, so much of that is the Qt and GPU driver
floor rather than Silere.

Results vary with hardware, drivers, and which widgets you enable. Measure your own
checkout:

```bash
bash scripts/bench.sh 30
```

The number is how many seconds to sample. The report tracks open file descriptors too, so a
leak shows up as a climbing number while everything else stays flat.

## Animation driver

Silere defaults to Qt's elapsed-time animation driver. Qt otherwise moves regular QML
animations to a roughly 16 ms timer when the bar and a popup are visible as separate
windows, making a high-refresh display look like 60 Hz. Launch with
`QSG_USE_SIMPLE_ANIMATION_DRIVER=0` to compare or work around a driver-specific issue.

## Cava

Cava is the main optional CPU cost, and only while the visualizer is on screen. Silere
creates its own temporary Cava profile at runtime, so it does not alter or depend on your
personal Cava configuration.
