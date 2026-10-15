# NeoGeoTREX v10 TEST - v9 TEST + DB15 joysticks on the user port

Everything in v9 TEST (68K overclock, no sprite limit, faster VRAM writes)
plus a new OSD option:

**User Port: Off / DB15 Joystick** (status bit 49, default Off)

For the DB15 splitter that plugs into the MiSTer user port (Antonio Villena's
design, the one Jotego's "User port: DB15 Joystick" option uses). Two pads or
sticks, players 1 and 2:

| DB15 button | NeoGeo |
|-------------|--------|
| Directions, A, B, C, D | the same |
| Start | Start |
| Select | Select |
| E | Coin |
| F | (not used) |

USB controllers keep working at the same time (inputs are combined).
With the option Off the user port is left exactly as before.

## Changes vs v9 TEST (`v10_test_db15.patch`)
- `rtl/io/neo_db15.v` (new, in files.qip): DB15 serial reader, same bit order
  and 3 MHz timing as joydb15.v (NeuroRulez), clocked from clk_sys with a clock
  enable.
- `neogeo.sv`: OSD line, reader instance, DB15 pads OR-ed into joystick_0/1.
- `sys/emu_ports.vh`, `sys/sys_top.v`: new `USER_PP` so user port pins 0/1
  (splitter clock/load) are driven push-pull while the option is on, as jtframe
  does; open-drain as before when off.

Not yet tested with a real adapter.

## Build
Compile `NeoGeo.qpf` and rename the rbf to `NeoGeoTREX_v10_TEST.rbf`.
