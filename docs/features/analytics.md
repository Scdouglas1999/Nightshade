# Analytics

The Analytics screen provides comprehensive session analysis, historical data visualization, and equipment statistics to help you understand your imaging performance and improve over time.

## Overview

The Analytics screen has three tabs:
- **Session**: Current session statistics and charts
- **History**: Past session records and analysis
- **Equipment Stats**: Long-term equipment performance metrics

## Session Tab

### Current Session Summary

Overview of the active imaging session:

**Session Information**
- Session name
- Current status (Active, Paused, Complete)
- Start time
- Duration (real-time update)

**Progress Metrics**
- Exposures: Completed / Total
- Total integration time (accumulated exposure)
- Average HFR (Half-Flux Radius)

### Session Charts

Four charts displayed in a 2×2 grid:

#### HFR Chart

Tracks star sharpness over time:
- Blue line showing HFR values
- Lower values = sharper stars
- Useful for detecting focus drift

**Interpreting HFR**
- < 2.0 px: Excellent focus
- 2.0-2.5 px: Good focus
- 2.5-3.5 px: Acceptable
- > 3.5 px: May need refocus

#### Guiding RMS Chart

Shows guiding accuracy:
- Green line for total RMS
- Values in arcseconds
- Goal: < 1.0 arcsec

#### Focuser Position Chart

Tracks focuser movement:
- Purple line showing position
- Reveals temperature-related drift
- Shows autofocus events

#### Temperature Chart

Monitors environmental temperature:
- Orange line for temperature
- Values in °C
- Correlates with focus changes

### Captured Images Strip

Horizontal scrollable list of captured images:

**Image Cards (120px height)**
- Thumbnail preview
- Color-coded border:
  - Green: Accepted
  - Red: Rejected
- HFR badge with color coding
- Filter name
- Exposure duration

**HFR Badge Colors**
| HFR | Color |
|-----|-------|
| < 2.0 | Green |
| < 2.5 | Light green |
| < 3.5 | Orange |
| > 3.5 | Red |

### Chart Features

All session charts include:
- Line chart with bezier curves
- Auto-scaling with 10% padding
- Interactive tooltip on hover
- Time-based X-axis (minutes/hours)
- Data-driven Y-axis

## History Tab

### Session Filters

Filter historical sessions:

**Search**
- Search by session name
- Real-time filtering

**Time Filter**
- All Time
- This Month
- This Year

**Target Filter**
- All Targets
- Specific targets (M31, M42, NGC 7000, etc.)

### Session List

Cards for each past session:

**Card Information**
- Session name
- Status badge
- Date/time stamp

**Statistics Chips**
- Duration
- Image count
- Total integration time
- Average HFR

### Session Detail Dialog

Click a session card for details:

**Statistics Grid**
- Up to 6 columns of detailed metrics
- All session statistics

**Image Gallery**
- All captured images
- Filter by accepted/rejected
- Preview thumbnails

**Export Options**
- Export as JSON
- Export as CSV
- Share functionality

## Equipment Stats Tab

Long-term performance metrics for each equipment type:

### Camera Statistics

- **Total Exposures**: All-time exposure count
- **Integration Time**: Total hours of integration
- **Average Temperature**: Mean operating temperature

### Mount Statistics

- **Total Slews**: Number of GoTo operations
- **Tracking Time**: Hours of tracking
- **Meridian Flips**: Count of flip operations

### Focuser Statistics

- **Autofocus Runs**: Total AF attempts
- **Average HFR**: Mean achieved HFR
- **Total Movements**: Focuser step count

### Guider Statistics

- **Total Guide Time**: Hours of guiding
- **Average RMS**: Mean guiding accuracy
- **Star Lost Events**: Guide star loss count

## Chart Components

### Generic Session Chart

All charts share common features:
- FL_Chart library rendering
- Smooth bezier curve interpolation
- Auto-scaling Y-axis
- Time-based X-axis

### Chart Variants

**HFR Chart**
- Blue line color
- Y-axis in pixels
- Lower is better

**Temperature Chart**
- Orange line color
- Y-axis in °C
- Reference for focus correlation

**Guiding RMS Chart**
- Green line color
- Y-axis in arcseconds
- Lower is better

**Focuser Position Chart**
- Purple line color
- Y-axis in focuser steps
- Shows drift and corrections

## Data Analysis

### Session Comparison

Compare sessions to track improvement:
- View sessions for same target
- Compare HFR, RMS, integration
- Identify trends over time

### Equipment Trends

Long-term equipment performance:
- Degradation indicators
- Maintenance reminders
- Performance optimization

### Weather Correlation

Relate session quality to conditions:
- Temperature vs. focus stability
- Cloud cover vs. image quality
- Seeing vs. HFR values

## Export and Sharing

### Export Formats

**JSON Export**
- Complete session data
- Machine-readable format
- Preserves all metadata

**CSV Export**
- Tabular format
- Spreadsheet compatible
- Key metrics only

### What's Exported

- Session metadata
- Image list with statistics
- Equipment settings
- Environmental data
- Timing information

## Best Practices

### Session Review

After each imaging session:
1. Review captured images
2. Check HFR trend for focus issues
3. Review guiding performance
4. Note any rejected frames
5. Export session data

### Performance Tracking

Over time:
1. Compare sessions on same targets
2. Track equipment performance trends
3. Identify optimization opportunities
4. Document setup changes

### Quality Improvement

Use analytics to improve:
1. Optimal exposure times
2. Refocus intervals
3. Dither settings
4. Equipment configurations

## Integration

### With Sequencer

Session analytics include:
- Sequence execution data
- Node timing information
- Checkpoint information

### With Imaging

Real-time updates during capture:
- Live HFR tracking
- Continuous guiding stats
- Temperature monitoring

### With Equipment

Equipment stats track:
- Usage patterns
- Performance over time
- Maintenance indicators

## Troubleshooting

### No Data Showing

- Verify session started properly
- Check database connectivity
- Ensure images being saved

### Charts Empty

- Confirm exposure completion
- Check data logging enabled
- Review session status

### Missing Sessions

- Check date filter settings
- Verify session was saved
- Check database backup

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+E | Export session |
| Ctrl+F | Filter sessions |
| Tab | Switch between tabs |

## Next Steps

- [Imaging Features](imaging.md) - Capture images
- [Sequencing](sequencing.md) - Automated sessions
- [Settings](settings.md) - Configure logging
