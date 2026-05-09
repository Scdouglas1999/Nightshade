# Headless Route Policy Audit

- Passed: `true`
- Issues: `0`
- High-risk policies: `19`
- Default limited policies: `9`
- Body-limited API write routes: `161`
- `/api/files/browse` audit action: `file_browse`
- `/api/info` rate limited: `false`
- Server middleware tests: `4/4`

This audit verifies request body limits, per-endpoint rate-limit metadata, and high-risk audit action metadata for release-gated headless control routes.

## Body Limits

| Route | Max bytes |
| --- | ---: |
| `/api/mount/slew` | 1048576 |
| `/api/imaging/stats` | 67108864 |
| `/api/imaging/stretch` | 67108864 |
| `/api/imaging/debayer` | 67108864 |
| `/api/imaging/save-fits` | 67108864 |
| `/api/backup/upload-restore` | 268435456 |

## Body-Limited API Write Routes

| Method | Route | Max bytes |
| --- | --- | ---: |
| `POST` | `/api/backup/auto-save` | 1048576 |
| `POST` | `/api/backup/create` | 1048576 |
| `POST` | `/api/backup/restore` | 1048576 |
| `POST` | `/api/backup/upload-restore` | 268435456 |
| `POST` | `/api/builtin-guider/config` | 1048576 |
| `POST` | `/api/camera/abort` | 1048576 |
| `POST` | `/api/camera/cooling` | 1048576 |
| `POST` | `/api/camera/expose` | 1048576 |
| `POST` | `/api/camera/gain` | 1048576 |
| `POST` | `/api/camera/offset` | 1048576 |
| `POST` | `/api/camera/readoutMode` | 1048576 |
| `POST` | `/api/collaboration/annotations` | 1048576 |
| `POST` | `/api/collaboration/chat` | 1048576 |
| `POST` | `/api/collaboration/preview` | 1048576 |
| `POST` | `/api/collaboration/viewers/join` | 1048576 |
| `POST` | `/api/collaboration/viewers/leave` | 1048576 |
| `POST` | `/api/cover/brightness` | 1048576 |
| `POST` | `/api/cover/calibrator-off` | 1048576 |
| `POST` | `/api/cover/calibrator-on` | 1048576 |
| `POST` | `/api/cover/close` | 1048576 |
| `POST` | `/api/cover/open` | 1048576 |
| `POST` | `/api/device/heartbeat/start` | 1048576 |
| `POST` | `/api/device/heartbeat/stop` | 1048576 |
| `POST` | `/api/devices/connect` | 1048576 |
| `POST` | `/api/devices/disconnect` | 1048576 |
| `POST` | `/api/dome/close` | 1048576 |
| `POST` | `/api/dome/halt` | 1048576 |
| `POST` | `/api/dome/home` | 1048576 |
| `POST` | `/api/dome/open` | 1048576 |
| `POST` | `/api/dome/park` | 1048576 |
| `POST` | `/api/dome/slew` | 1048576 |
| `POST` | `/api/dome/sync` | 1048576 |
| `POST` | `/api/files/validate` | 1048576 |
| `POST` | `/api/filter-wheel/position` | 1048576 |
| `POST` | `/api/filter-wheel/set-by-name` | 1048576 |
| `POST` | `/api/flat-wizard/calibrate` | 1048576 |
| `POST` | `/api/flat-wizard/calibrate-multi` | 1048576 |
| `POST` | `/api/flat-wizard/generate-sequence` | 1048576 |
| `POST` | `/api/flat-wizard/quick-calibrate` | 1048576 |
| `POST` | `/api/focus-model/add-point` | 1048576 |
| `POST` | `/api/focus-model/filter-offsets` | 1048576 |
| `POST` | `/api/focus-model/import` | 1048576 |
| `POST` | `/api/focuser/autofocus/cancel` | 1048576 |
| `POST` | `/api/focuser/autofocus/start` | 1048576 |
| `POST` | `/api/focuser/halt` | 1048576 |
| `POST` | `/api/focuser/move-relative` | 1048576 |
| `POST` | `/api/focuser/move-to` | 1048576 |
| `POST` | `/api/framing/abort-slew` | 1048576 |
| `POST` | `/api/framing/center-on-target` | 1048576 |
| `POST` | `/api/framing/park` | 1048576 |
| `POST` | `/api/framing/rotate-to` | 1048576 |
| `POST` | `/api/framing/slew-to-target` | 1048576 |
| `POST` | `/api/framing/sync` | 1048576 |
| `POST` | `/api/framing/unpark` | 1048576 |
| `POST` | `/api/guider/deselect-star` | 1048576 |
| `POST` | `/api/guider/dither` | 1048576 |
| `POST` | `/api/guider/find-star` | 1048576 |
| `POST` | `/api/guider/loop` | 1048576 |
| `POST` | `/api/guider/set-lock-position` | 1048576 |
| `POST` | `/api/guider/start-guiding` | 1048576 |
| `POST` | `/api/guider/stop-guiding` | 1048576 |
| `POST` | `/api/imaging/debayer` | 67108864 |
| `POST` | `/api/imaging/save-fits` | 67108864 |
| `POST` | `/api/imaging/save-fits-from-capture` | 1048576 |
| `POST` | `/api/imaging/stats` | 67108864 |
| `POST` | `/api/imaging/stretch` | 67108864 |
| `POST` | `/api/mosaic/calculate-area` | 1048576 |
| `POST` | `/api/mosaic/estimate-time` | 1048576 |
| `POST` | `/api/mosaic/generate-panels` | 1048576 |
| `POST` | `/api/mosaic/generate-sequence` | 1048576 |
| `POST` | `/api/mosaic/validate` | 1048576 |
| `POST` | `/api/mount/abort` | 1048576 |
| `POST` | `/api/mount/find-home` | 1048576 |
| `POST` | `/api/mount/move-axis` | 1048576 |
| `POST` | `/api/mount/park` | 1048576 |
| `POST` | `/api/mount/pulse-guide` | 1048576 |
| `POST` | `/api/mount/set-tracking-rate` | 1048576 |
| `POST` | `/api/mount/slew` | 1048576 |
| `POST` | `/api/mount/slew-alt-az` | 1048576 |
| `POST` | `/api/mount/sync` | 1048576 |
| `POST` | `/api/mount/tracking` | 1048576 |
| `POST` | `/api/mount/unpark` | 1048576 |
| `POST` | `/api/phd2/algo-param` | 1048576 |
| `POST` | `/api/phd2/clear-calibration` | 1048576 |
| `POST` | `/api/phd2/connect` | 1048576 |
| `POST` | `/api/phd2/deselect-star` | 1048576 |
| `POST` | `/api/phd2/disconnect` | 1048576 |
| `POST` | `/api/phd2/dither` | 1048576 |
| `POST` | `/api/phd2/find-star` | 1048576 |
| `POST` | `/api/phd2/flip-calibration` | 1048576 |
| `POST` | `/api/phd2/get-calibration-data` | 1048576 |
| `POST` | `/api/phd2/loop` | 1048576 |
| `POST` | `/api/phd2/pause` | 1048576 |
| `POST` | `/api/phd2/set-lock-position` | 1048576 |
| `POST` | `/api/phd2/start-guiding` | 1048576 |
| `POST` | `/api/phd2/stop-guiding` | 1048576 |
| `POST` | `/api/planetarium/center-on` | 1048576 |
| `POST` | `/api/planetarium/slew-to` | 1048576 |
| `POST` | `/api/planetarium/sync-to` | 1048576 |
| `POST` | `/api/plate-solve` | 1048576 |
| `POST` | `/api/polar-alignment/start` | 1048576 |
| `POST` | `/api/polar-alignment/stop` | 1048576 |
| `POST` | `/api/profiles` | 1048576 |
| `POST` | `/api/profiles/<profileId>/load` | 1048576 |
| `POST` | `/api/rotator/halt` | 1048576 |
| `POST` | `/api/rotator/move-relative` | 1048576 |
| `POST` | `/api/rotator/move-to` | 1048576 |
| `POST` | `/api/safety/acknowledge` | 1048576 |
| `POST` | `/api/safety/settings` | 1048576 |
| `POST` | `/api/scheduler/optimize-targets` | 1048576 |
| `POST` | `/api/science/calibration/compute-transform` | 1048576 |
| `POST` | `/api/science/calibration/image/<imageId>/match-stars` | 1048576 |
| `POST` | `/api/science/calibration/save-transform` | 1048576 |
| `POST` | `/api/science/session/<sessionId>/config` | 1048576 |
| `POST` | `/api/science/session/<sessionId>/export/aavso` | 1048576 |
| `POST` | `/api/science/session/<sessionId>/generate-line-ratios` | 1048576 |
| `POST` | `/api/science/settings` | 1048576 |
| `POST` | `/api/sequence-management` | 1048576 |
| `PUT` | `/api/sequence-management/<id>` | 1048576 |
| `POST` | `/api/sequence-management/<id>/duplicate` | 1048576 |
| `POST` | `/api/sequence-management/<id>/nodes` | 1048576 |
| `POST` | `/api/sequence-management/<id>/reorder` | 1048576 |
| `PUT` | `/api/sequence-management/nodes/<nodeId>` | 1048576 |
| `POST` | `/api/sequence-management/nodes/<nodeId>/enabled` | 1048576 |
| `POST` | `/api/sequencer/checkpoint/dir` | 1048576 |
| `POST` | `/api/sequencer/checkpoint/discard` | 1048576 |
| `POST` | `/api/sequencer/checkpoint/resume` | 1048576 |
| `POST` | `/api/sequencer/checkpoint/save` | 1048576 |
| `POST` | `/api/sequencer/devices` | 1048576 |
| `POST` | `/api/sequencer/load` | 1048576 |
| `POST` | `/api/sequencer/pause` | 1048576 |
| `POST` | `/api/sequencer/reset` | 1048576 |
| `POST` | `/api/sequencer/resume` | 1048576 |
| `POST` | `/api/sequencer/safety-fail-mode` | 1048576 |
| `POST` | `/api/sequencer/save-path` | 1048576 |
| `POST` | `/api/sequencer/simulation` | 1048576 |
| `POST` | `/api/sequencer/skip` | 1048576 |
| `POST` | `/api/sequencer/start` | 1048576 |
| `POST` | `/api/sequencer/stop` | 1048576 |
| `POST` | `/api/sequencer/update-dither-config` | 1048576 |
| `POST` | `/api/sequencer/update-filter-offsets` | 1048576 |
| `POST` | `/api/sequencer/update-location` | 1048576 |
| `POST` | `/api/sequences/start` | 1048576 |
| `POST` | `/api/sequences/stop` | 1048576 |
| `POST` | `/api/session-handoff` | 1048576 |
| `POST` | `/api/sessions` | 1048576 |
| `PUT` | `/api/sessions/<id>` | 1048576 |
| `POST` | `/api/sessions/<id>/end` | 1048576 |
| `POST` | `/api/settings` | 1048576 |
| `POST` | `/api/settings/location` | 1048576 |
| `POST` | `/api/switch/set` | 1048576 |
| `POST` | `/api/targets` | 1048576 |
| `PUT` | `/api/targets/<id>` | 1048576 |
| `POST` | `/api/targets/<id>/favorite` | 1048576 |
| `PUT` | `/api/targets/<id>/progress` | 1048576 |
| `POST` | `/api/transients/<id>/dismiss` | 1048576 |
| `POST` | `/api/transients/<id>/queue` | 1048576 |
| `POST` | `/api/transients/refresh` | 1048576 |
| `POST` | `/api/transients/settings` | 1048576 |
| `POST` | `/api/weather/clear-cache` | 1048576 |
| `POST` | `/api/weather/settings` | 1048576 |

## Server Middleware Tests

| Coverage | Present |
| --- | --- |
| `oversized_control_request_before_auth` | `true` |
| `chunked_oversized_control_request_before_auth` | `true` |
| `high_risk_control_rate_limit` | `true` |
| `websocket_api_version_before_auth` | `true` |

## High-Risk Policies

| Route | Audit action | Max requests |
| --- | --- | ---: |
| `/api/devices/connect` | `device_connect` | 12 |
| `/api/devices/disconnect` | `device_disconnect` | 12 |
| `/api/mount/slew` | `mount_slew` | 12 |
| `/api/mount/slew-alt-az` | `mount_slew_alt_az` | 12 |
| `/api/mount/park` | `mount_park` | 12 |
| `/api/mount/unpark` | `mount_unpark` | 12 |
| `/api/framing/slew-to-target` | `framing_slew_to_target` | 12 |
| `/api/framing/center-on-target` | `framing_center_on_target` | 12 |
| `/api/framing/park` | `framing_park` | 12 |
| `/api/framing/unpark` | `framing_unpark` | 12 |
| `/api/dome/open` | `dome_open` | 12 |
| `/api/dome/close` | `dome_close` | 12 |
| `/api/dome/slew` | `dome_slew` | 12 |
| `/api/dome/park` | `dome_park` | 12 |
| `/api/backup/restore` | `backup_restore` | 12 |
| `/api/backup/upload-restore` | `backup_upload_restore` | 12 |
| `/api/sequencer/start` | `sequence_start` | 12 |
| `/api/sequencer/stop` | `sequence_stop` | 12 |
| `/api/sequencer/resume` | `sequence_resume` | 12 |
