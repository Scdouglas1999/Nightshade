# INDI Troubleshooting

INDI support requires a reachable INDI server. Nightshade connects to the server
and uses the properties exposed by the loaded device drivers.

## Quick Checks

1. Confirm the INDI server is running on the expected host.
2. Confirm Nightshade is using the same host and port. The common default is
   `localhost:7624`.
3. Start the INDI server with the exact drivers needed for the device.
4. Confirm no other process has exclusive access to the USB or serial device.

## Useful Commands

```bash
ps aux | grep indiserver
indi_getprop
indi_getprop "*CONNECTION*"
lsusb
dmesg | tail -100
```

If `indi_getprop` cannot see the device properties, Nightshade will not be able
to control that device either.

## Server Not Reachable

- Check that the INDI server is bound to the expected interface.
- Open TCP port `7624` only on trusted networks.
- Use `localhost` when Nightshade and INDI run on the same machine.
- Use the server IP address when INDI runs on another computer.
- Check firewall rules on both machines.

## Device Appears But Commands Fail

- Verify the INDI driver exposes the required capability for the Nightshade
  control being used.
- Check INDI logs for permission, timeout, or device-busy errors.
- Confirm the device is not parked, disconnected, or in a driver-specific safe
  mode.
- Restart the INDI driver after changing cabling or USB permissions.

## Linux Permissions

- Add the user to `dialout` for serial devices.
- Add the user to `video` or `plugdev` when required by camera drivers.
- Install vendor udev rules for cameras and USB accessories.
- Log out and back in after changing group membership.

## Release-Gate Evidence

For public-release sign-off, record the OS, INDI server version, driver names,
host/port, device models, tested operations, and any unsupported properties that
must be disabled or documented.
