# Web Server API Reference

The Nightshade Web Server provides a REST API for remote control of the desktop application. This allows mobile devices and other clients to control Nightshade over the network.

## Overview

The web server runs on port 8080 by default and provides both REST API endpoints and WebSocket support for real-time updates.

**Base URL:** `http://localhost:8080`

## Server Information

### GET /api/info

Get server information and capabilities.

**Response:**
```json
{
  "status": "running",
  "version": "2.0.0",
  "apiOnlyMode": true,
  "webUIAvailable": false,
  "timestamp": "2025-11-30T12:00:00Z",
  "endpoints": [
    "GET /api/info",
    "GET /api/status",
    "GET /api/devices",
    "POST /api/devices/connect",
    "POST /api/devices/disconnect",
    "GET /api/devices/connected",
    "POST /api/phd2/connect",
    "POST /api/phd2/disconnect",
    "GET /api/sequences/status",
    "POST /api/sequences/start",
    "POST /api/sequences/stop",
    "GET /api/images/recent"
  ]
}
```

### GET /api/status

Get server status.

**Response:**
```json
{
  "status": "running",
  "version": "2.0.0",
  "timestamp": "2025-11-30T12:00:00Z"
}
```

## Device Management

### GET /api/devices

List all available and connected devices.

**Response:**
```json
{
  "devices": [
    {
      "id": "camera-1",
      "name": "ZWO ASI294MC Pro",
      "deviceType": "camera",
      "driverType": "native",
      "description": "ZWO Camera",
      "driverVersion": "1.0.0"
    }
  ],
  "connected": {
    "camera": "camera-1",
    "mount": null,
    "focuser": null,
    "filterWheel": null,
    "rotator": null
  },
  "available": [...]
}
```

### POST /api/devices/connect

Connect to a device.

**Request Body:**
```json
{
  "deviceType": "camera",
  "deviceId": "camera-1"
}
```

**Response:**
```json
{
  "status": "connected",
  "deviceId": "camera-1"
}
```

### POST /api/devices/disconnect

Disconnect from a device.

**Request Body:**
```json
{
  "deviceType": "camera",
  "deviceId": "camera-1"
}
```

**Response:**
```json
{
  "status": "disconnected",
  "deviceId": "camera-1"
}
```

### GET /api/devices/connected

Get list of currently connected devices.

**Response:**
```json
{
  "devices": [
    {
      "id": "camera-1",
      "name": "ZWO ASI294MC Pro",
      "deviceType": "camera",
      "driverType": "native"
    }
  ]
}
```

## PHD2 Guiding

### POST /api/phd2/connect

Connect to PHD2.

**Request Body (optional):**
```json
{
  "host": "localhost",
  "port": 4400
}
```

**Response:**
```json
{
  "status": "connected"
}
```

### POST /api/phd2/disconnect

Disconnect from PHD2.

**Response:**
```json
{
  "status": "disconnected"
}
```

## Sequence Control

### GET /api/sequences/status

Get sequence status.

**Response:**
```json
{
  "state": "running",
  "currentNodeId": "node-1",
  "currentNodeName": "Exposure",
  "totalExposures": 100,
  "completedExposures": 45,
  "totalIntegrationSecs": 3600.0,
  "elapsedSecs": 1620.0,
  "estimatedRemainingSecs": 1980.0,
  "currentTarget": "M42",
  "currentFilter": "L",
  "message": "Exposing frame 45/100"
}
```

### POST /api/sequences/start

Start a sequence.

**Request Body (optional):**
```json
{
  "sequenceId": "seq-1",
  "targetName": "M42"
}
```

**Response:**
```json
{
  "status": "started",
  "sequenceId": "seq-1"
}
```

### POST /api/sequences/stop

Stop current sequence.

**Response:**
```json
{
  "status": "stopped"
}
```

## Image Management

### GET /api/images/recent

List recent images.

**Query Parameters:**
- `limit` (optional) - Maximum number of images to return

**Response:**
```json
{
  "images": [
    {
      "id": "img-1",
      "filename": "M42_L_001.fits",
      "path": "/path/to/image.fits",
      "timestamp": "2025-11-30T12:00:00Z",
      "exposureTime": 60.0,
      "filter": "L",
      "target": "M42"
    }
  ],
  "count": 10
}
```

## WebSocket Support

### WebSocket Connection

Connect to `/api/ws` for real-time updates.

**Connection:**
```javascript
const ws = new WebSocket('ws://localhost:8080/api/ws');
```

**Message Format:**
```json
{
  "type": "ping"
}
```

**Response:**
```json
{
  "type": "pong"
}
```

The server can broadcast messages to all connected clients for real-time updates (sequence progress, device status, etc.).

## Error Responses

All endpoints may return error responses:

**Error Response:**
```json
{
  "error": "Error type",
  "message": "Detailed error message"
}
```

**HTTP Status Codes:**
- `200 OK` - Success
- `400 Bad Request` - Invalid request
- `404 Not Found` - Endpoint not found
- `500 Internal Server Error` - Server error
- `501 Not Implemented` - Handler not registered

## CORS

The server includes CORS headers to allow cross-origin requests:

- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type`

## Example Usage

### JavaScript/TypeScript

```javascript
// Get device list
const response = await fetch('http://localhost:8080/api/devices');
const data = await response.json();
console.log('Devices:', data.devices);

// Connect to camera
await fetch('http://localhost:8080/api/devices/connect', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    deviceType: 'camera',
    deviceId: 'camera-1'
  })
});

// Get sequence status
const statusResponse = await fetch('http://localhost:8080/api/sequences/status');
const status = await statusResponse.json();
console.log('Sequence state:', status.state);
```

### Python

```python
import requests

# Get device list
response = requests.get('http://localhost:8080/api/devices')
devices = response.json()
print(f"Found {len(devices['devices'])} devices")

# Connect to camera
requests.post('http://localhost:8080/api/devices/connect', json={
    'deviceType': 'camera',
    'deviceId': 'camera-1'
})

# Get sequence status
status = requests.get('http://localhost:8080/api/sequences/status').json()
print(f"Sequence state: {status['state']}")
```

## Server Configuration

The web server can be configured when creating an instance:

```dart
final server = NightshadeWebServer(
  port: 8080,
  webRoot: '/path/to/web/build', // Optional: for serving static files
  devicesHandler: () async => {...},
  deviceConnectHandler: (type, id) async => {...},
  // ... other handlers
);

await server.start();
```

If `webRoot` is not provided or doesn't exist, the server runs in API-only mode.

