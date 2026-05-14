# Hardware Trace Replay

Place captured real-device traces here as JSON files. The compatibility suite validates every trace in this directory and writes replay readiness results to `reports/compat/trace-replay`.

Minimum schema:

```json
{
  "vendor": "ZWO",
  "driver_type": "Native SDK",
  "device_type": "Camera",
  "model": "ASI2600MM Pro",
  "events": [
    { "direction": "call", "name": "ASIStartExposure", "args": { "dark": false } },
    { "direction": "return", "name": "ASIStartExposure", "result": 0 }
  ]
}
```

The important rule is that traces should contain real SDK/API calls and returns, not hand-written expectations. Once a community tester captures a device once, the trace can stay in CI permanently.
