# Framing Assistant

The Framing Assistant helps you plan and preview how targets will appear in your camera's field of view before imaging. Use it to optimize composition, plan mosaics, and verify target visibility.

## Overview

The Framing screen provides:
- Target search and selection
- Altitude and visibility planning
- Field of view preview
- Mosaic planning tools
- Equipment configuration display

## Screen Layout

### Resizable Sidebar (Left)

The sidebar contains all configuration controls:
- Initial width: 320px
- Resizable: 250px to 500px
- Drag handle on right edge

### Preview Canvas (Right)

The main preview area shows:
- Sky survey imagery
- Equipment FOV overlay
- Grid and labels
- Mosaic panels

## Target Search

### Search Input

Find targets by name or catalog designation:

**Search Examples**
- Object names: "M42", "Orion Nebula"
- Catalog numbers: "NGC7000", "IC1396"
- Common names: "Heart Nebula", "Crab Nebula"

**Search Features**
- Real-time search with loading indicator
- Clear button when text present
- Results dropdown (max 200px height)

### Search Results

Each result shows:
- Type icon (galaxy, nebula, cluster, star, planet)
- Target name with catalog ID
- Magnitude (when available)
- Click to select

### Manual Coordinates

Enter coordinates directly:
- **RA field**: Hours (e.g., "05h 35m 17s" or "5.588")
- **Dec field**: Degrees (e.g., "-05° 23' 28"" or "-5.391")
- **Go button**: Navigate to coordinates

**Format Support**
- Sexagesimal: 05h 35m 17s, -05° 23' 28"
- Decimal: 5.588, -5.391
- Flexible parsing

### Target Resolution

When selecting a target:
- SIMBAD resolver queries astronomical databases
- Returns: main ID, catalog ID, RA, Dec, magnitude
- Target saved to database for future sessions

## Altitude Chart

### Visibility Graph

The altitude chart shows target visibility over time:

**Chart Data**
- 10-minute interval calculations
- Time range: Sunset-1hr to Sunrise+1hr
- Altitude curve with gradient fill
- Optional airmass overlay

**Current Values**
Two chips display current conditions:
- **Altitude**: Current degrees above horizon
- **Airmass**: Atmospheric path length (lower = better)

**Color Coding**

| Value | Altitude Color | Airmass Color |
|-------|----------------|---------------|
| Good | Green (>30°) | Green (<1.5) |
| Moderate | Yellow (0-30°) | Yellow (1.5-2.0) |
| Poor | Red (<0°) | Red (>2.0) |

### Chart Features

**Reference Lines**
- Horizon (red, 0°)
- Good altitude threshold (yellow dashed, 30°)
- Twilight markers (astronomical dusk/dawn)
- Current time (red dashed, "Now" label)

**Interactive Tooltip**
- Hover/tap for time and value
- Format: "HH:mm, Alt: XX.X°" or "Airmass: X.XX"

### Visibility Summary

Chips showing key times:
- **Rise time**: When target rises above horizon
- **Transit time**: When target reaches peak altitude
- **Set time**: When target sets below horizon
- **Max altitude**: Highest point during night

**Special Cases**
- "Circumpolar" - Target always visible
- "Never rises" - Target below horizon all night

## Field of View Preview

### Equipment Status

The equipment status section shows:

**When Ready**
- Profile name with green checkmark
- Camera name
- Telescope: focal length (mm) and f-ratio
- FOV dimensions and image scale

**When Not Configured**
- Warning triangle indicator
- Message directing to Settings → Equipment
- Still allows sky browsing

### FOV Information

When equipment is configured:
- **Field of View**: Width × Height in degrees
- **Image Scale**: Arcseconds per pixel
- **Sensor**: Pixel dimensions (X × Y)

### Preview Controls

**FOV Slider**
- Adjustable preview FOV (0-180°)
- Independent of equipment FOV
- Allows browsing sky at different scales

**Equipment FOV Overlay**
- Toggle switch to show/hide
- Opacity slider (0-100%)
- Only visible when preview FOV > equipment FOV

**Survey Source**
- Dropdown to select sky survey
- Multiple survey options available
- Works even without equipment

### Display Toggles

| Toggle | Description |
|--------|-------------|
| **Grid** | Coordinate grid overlay |
| **Labels** | Object and constellation labels |
| **Directions** | Cardinal directions (N,E,S,W) |

## Mosaic Planning

### Enable Mosaic Mode

- Toggle switch in sidebar
- Disabled if no equipment configured
- Shows grid configuration when enabled

### Grid Configuration

**Columns** (Horizontal panels)
- Spinner: 1-10 panels
- Default: 2

**Rows** (Vertical panels)
- Spinner: 1-10 panels
- Default: 2

**Overlap**
- Slider: 0-50%
- Typical: 10-20%
- Applied uniformly to all panels

### Capture Pattern

**Serpentine Toggle**
- Enabled: Snake pattern (alternating direction per row)
- Disabled: Row-by-row same direction

**Numbers Toggle**
- Show panel sequence numbers on canvas
- Helps visualize capture order

**Start Corner**
- Dropdown: Top-left, Top-right, Bottom-left, Bottom-right
- Determines first panel position

### Mosaic Summary

Panel information display:
- Total panel count with grid icon
- Scrollable list of panels
- Panel selection capability
- Grid layout visualization

## Coordinate Display

### Target Coordinates

When target selected:
- **RA**: Formatted as HH:MM:SS.s
- **Dec**: Formatted as ±DD° MM' SS.s"
- Copy-to-clipboard button

### Real-Time Position

Updated every 10 seconds:
- Current altitude
- Current azimuth
- "Below Horizon" warning if applicable

## Preview Canvas

### Pan and Rotation

- **Pan**: Click and drag to reposition
- **Rotate**: Use rotation handle or input field
- **Reset**: Button to return to default

### Overlays

**Equipment FOV Rectangle**
- Shows actual camera field
- Includes rotation
- Opacity adjustable

**Mosaic Grid**
- All panels displayed
- Numbers on each panel
- Overlap visualization

**Grid Lines**
- RA/Dec coordinate grid
- Configurable visibility

**Cardinal Directions**
- N, E, S, W markers
- Only with equipment configured

## Workflow

### Basic Framing

1. Search for target or enter coordinates
2. Review altitude chart for visibility
3. Check FOV preview
4. Adjust rotation if needed
5. Save framing or send to sequence

### Mosaic Planning

1. Select center target
2. Enable Mosaic Mode
3. Configure grid (rows × columns)
4. Set overlap percentage
5. Choose start corner and pattern
6. Review panel layout
7. Generate mosaic sequence

### From Planetarium

1. Select target in Planetarium
2. Click "Send to Framing"
3. Target loads automatically
4. Configure framing options
5. Return to sequence builder

## Equipment Configuration

### Required Settings

For full functionality:
1. **Equipment Profile**: Created in Settings → Equipment
2. **Focal Length**: Telescope focal length (mm)
3. **Camera Specs**: Sensor size and pixel dimensions

### Camera Information Sources

Camera specs can come from:
- Connected camera (auto-detected)
- Manual entry in profile
- Default values (less accurate)

### Calculated Values

From equipment settings:
- Field of view (degrees)
- Image scale (arcsec/pixel)
- Sensor coverage (arcminutes)

## Integration

### With Sequencer

1. Plan framing in Framing Assistant
2. Target coordinates saved
3. Add target to sequence
4. Slew uses saved framing

### With Planetarium

1. Preview in Planetarium
2. Send to Framing for detail
3. Return with saved coordinates

### With Imaging

1. Configure framing
2. Plate solve image
3. Compare actual vs planned
4. Adjust if needed

## Best Practices

### Target Planning

1. Check altitude chart first
2. Verify target is accessible
3. Consider moon distance
4. Plan for meridian flip

### Framing Composition

1. Center main object
2. Include interesting context
3. Allow for cropping
4. Consider rotation for aesthetics

### Mosaic Planning

1. Start with fewer panels
2. Use 15-20% overlap minimum
3. Consider serpentine pattern
4. Plan capture order for efficiency

### Before Imaging

1. Verify equipment profile correct
2. Check calculated FOV matches reality
3. Test with short exposure
4. Plate solve to confirm framing

## Troubleshooting

### No Preview Image

- Check internet connection
- Try different survey source
- Verify coordinates valid

### FOV Wrong Size

- Verify focal length in profile
- Check camera pixel size
- Confirm sensor dimensions

### Target Not Found

- Try alternate names
- Use catalog designation (NGC, IC)
- Enter coordinates manually

### Altitude Chart Empty

- Configure location in Settings
- Verify timezone correct
- Check target coordinates valid

## Next Steps

- [Planetarium](planetarium.md) - Visual target selection
- [Sequencing](sequencing.md) - Add framing to sequences
- [Equipment](equipment.md) - Configure profiles
- [Settings](settings.md) - Location and equipment setup
