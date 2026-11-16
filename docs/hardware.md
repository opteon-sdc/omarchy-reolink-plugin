# Tested hardware

Each row records a real device that someone used with the plugin. Features can
differ by model and firmware: the plugin asks the camera through
`reolink-cli --camera NAME capabilities` and hides controls the camera does not
support.

| Model | Firmware | reolink-cli | Plugin | Connection | Live view | Pan/tilt | Presets | Snapshot | Notes |
|---|---|---|---|---|---|---|---|---|---|
| E1 Pro (E Series E330) | v3.1.0.4417_2412122130 | 0.21.0 | 1.0.0 | Wi-Fi, direct | ✅ H.264 sub and main | ✅ | ✅ | ✅ | No zoom (`ptzMode: pt`) |

✅ works · ⚠️ partly works · ❌ does not work · — not supported by the device

## Add your camera

Open a [hardware report](https://github.com/opteon-sdc/omarchy-reolink-plugin/issues/new?template=hardware_report.yml)
or send a pull request that adds a row. Copy the model and firmware from:

```bash
reolink-cli --camera NAME info | jq '.data | {model, item_no, firmware}'
reolink-cli --camera NAME capabilities | jq '.data.ptzMode'
```

Leave out IP addresses, UIDs, serial numbers and passwords.
