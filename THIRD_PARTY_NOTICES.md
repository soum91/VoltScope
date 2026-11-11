# Power sensor research acknowledgments

VoltScope's read-only private HID power sensor probe is adapted from the
`IOHIDEventSystemClient` research and implementation in:

- Greg Wilson, **ios-charging-monitor (ChargeSpeed)**, 2026. MIT License.
  https://github.com/gregsramblings/ios-charging-monitor
- ZhaoHe Studio, **MiniWatts**, 2026. Apache License 2.0.
  https://github.com/ResistanceTo/MiniWatts

The probe resolves private HID symbols at runtime, enumerates Apple vendor
power and temperature usage pages, and decodes the SMC key from `LocationID`.
Sensor-specific limitations and the distinction between measured USB input and
battery-side charge current were learned from these projects.

## Upstream MIT notice

Copyright (c) 2026 Greg Wilson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## MiniWatts licensing

MiniWatts code and documentation are provided under the Apache License, Version
2.0. The relevant license and its NOTICE are available at:

https://github.com/ResistanceTo/MiniWatts/blob/master/LICENSE

https://github.com/ResistanceTo/MiniWatts/blob/master/NOTICE

This work does not include MiniWatts' UI, widgets, history, or bundled assets.

## PowerLog access research acknowledgment

VoltScope's experimental PowerLog reader follows the publicly described
`worse_query` sandbox-extension technique and compatibility observations from:

- forcequitOS, **worse_query**: https://github.com/forcequitOS/worse_query
- kolbicz, **WQFiles**: https://github.com/kolbicz/WQFiles (GPL-3.0)

`PowerLogProbe.m` is an independent implementation limited to a read-only
PowerLog access attempt, its own temporary App Group Caches swap, and SQLite
schema introspection. No WQFiles source code or assets are copied or linked.
The upstream projects' licenses still govern their own repositories.
