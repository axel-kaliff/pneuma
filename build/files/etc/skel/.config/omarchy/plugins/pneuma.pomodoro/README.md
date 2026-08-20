# Pomodoro (`pneuma.pomodoro`)

A focus timer in the Omarchy bar. Idle is a lone hourglass; a running phase
puts a live `mm:ss` countdown on the bar, tinted with the theme's active color
during focus and swapped for a coffee glyph during breaks. Clicking opens a
panel with the phase, cycle progress, a big countdown, and transport controls.

## Architecture

The timer lives in `Service.qml`, declared as a `service` kind so the shell
loads exactly one per session. That matters on a multi-monitor setup: a bar
surface exists per monitor, so an engine living in the bar widget would run one
timer per screen and fire a completion notification from each. `BarWidget.qml`
is a stateless view over the service.

A running phase is stored as a wall-clock deadline (`endsAt`), never as a
decremented counter, so suspend/resume, a slow tick, and a shell restart all
resolve to the same remaining time. State persists to
`~/.local/state/omarchy/pomodoro.json`.

## Interactions

| Where | Action | Effect |
| --- | --- | --- |
| Bar pill | Left click | Open/close the panel |
| Bar pill | Middle click | Start / pause |
| Bar pill | Right click | Skip to the next phase |
| Panel | `Space` | Start / pause |
| Panel | `R` | Reset to idle |
| Panel | `S` | Skip phase |
| Panel | `Esc` | Close |

Breaks start on their own when a focus phase ends; focus always waits for a
deliberate start, so walking away never silently burns a session.

## Settings

Inline on the bar layout entry in `~/.config/omarchy/shell.json`. Numbers need
`--json` or they land as strings:

```sh
omarchy bar set pneuma.pomodoro workMinutes 50 --json
```

| Key | Default | Meaning |
| --- | --- | --- |
| `workMinutes` | `25` | Focus phase length |
| `breakMinutes` | `5` | Short break length |
| `longBreakMinutes` | `15` | Long break length |
| `cyclesPerLong` | `4` | Focus phases before a long break |

## From scripts and keybindings

```sh
omarchy-shell pomodoro toggle | start | pause | skip | reset | status
omarchy-shell pneuma.pomodoro toggle          # the panel
```

`status` returns JSON. Note that the panel IPC routes to one monitor's bar
instance only — clicking the pill is per-monitor, as with the first-party
widgets.

## Known gap

The phase-change notification calls `omarchy-notification-send`. On Omarchy
4.0.0.alpha the shell's own notification service fails to load
(`plugins/notifications/Service.qml` uses `var transient`, and `transient` is a
reserved word in Qt 6.10's QML parser), so no notification daemon is on the
bus and the alert is silently dropped. The bar pill still changes phase.
