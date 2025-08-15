# Live Audio Sampler

A cross-platform audio sampler application designed for live sound production, perfect for events, conferences, and performances. Built with Flutter for seamless deployment across Windows, macOS, iOS, and Android.

## Features

### 🎵 Core Functionality
- **Grid-based Sample Layout**: Classic drum machine style interface with expandable grid
- **Real-time Audio Playback**: Instant sample triggering with visual feedback
- **Waveform Visualization**: Visual representation of audio with trimming handles
- **Multi-page Support**: Organize samples across multiple pages for better workflow

### ✂️ Audio Editing
- **Trim Controls**: Drag handles to set start and end points for samples
- **Volume Control**: Adjust sample volume from 0% to 200%
- **Pitch Shifting**: Modify playback speed from 0.5x to 2.0x
- **Effects Processing**: Real-time reverb and echo effects
- **Sample Metadata**: Add notes, categories, and favorite markers

### 🎛️ Live Performance Features
- **Transport Controls**: Play, pause, stop, and seek functionality
- **Fade Effects**: Smooth fade-in and fade-out transitions
- **Loop Mode**: Continuous playback for background music
- **Quick Access**: Swipe gestures for edit, copy, and delete actions

### 📱 Cross-Platform Support
- **Windows**: Desktop application with full keyboard/mouse support
- **macOS**: Native macOS app with system integration
- **iOS**: Touch-optimized interface for iPad and iPhone
- **Android**: Tablet-friendly design with gesture support

## Installation

### Prerequisites
- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Android Studio / Xcode (for mobile development)
- Visual Studio Code (recommended for development)

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd audio-sampler
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the application**
   ```bash
   # For Windows
   flutter run -d windows
   
   # For macOS
   flutter run -d macos
   
   # For iOS
   flutter run -d ios
   
   # For Android
   flutter run -d android
   ```

### Building for Production

```bash
# Windows
flutter build windows

# macOS
flutter build macos

# iOS
flutter build ios

# Android
flutter build apk
```

## Usage Guide

### Adding Samples
1. Tap the "+" button in any empty grid slot
2. Select an audio file from your device
3. Enter sample name, category, and optional notes
4. The sample will appear in the grid ready for playback

### Playing Samples
- **Single Tap**: Play the sample once
- **Long Press**: Access additional options (edit, copy, delete)
- **Swipe**: Quick actions for sample management

### Editing Samples
1. Select a sample from the grid
2. Switch to "Edit" mode using the toggle button
3. Adjust trim points, effects, and metadata
4. Save changes or discard modifications

### Waveform Editing
- **Blue Handle**: Drag to set start point
- **Red Handle**: Drag to set end point
- **Playback Indicator**: Shows current position during playback
- **Time Display**: Shows start, current, and end times

### Effects Panel
- **Volume**: 0% to 200% with fine control
- **Pitch**: 0.5x to 2.0x speed adjustment
- **Reverb**: Add spatial depth (0% to 100%)
- **Echo**: Create delay effects (0% to 100%)

### Transport Controls
- **Play/Pause**: Control playback
- **Stop**: Reset to beginning
- **Seek**: Drag progress bar to jump to position
- **Loop**: Enable continuous playback
- **Fade**: Smooth volume transitions

## File Structure

```
lib/
├── main.dart                 # Application entry point
├── models/
│   └── audio_sample.dart     # Audio sample data model
├── providers/
│   ├── audio_provider.dart   # Audio playback management
│   └── sample_provider.dart  # Sample data management
├── screens/
│   └── main_sampler_screen.dart  # Main application screen
└── widgets/
    ├── add_sample_button.dart    # Add sample button
    ├── effects_panel.dart        # Effects controls
    ├── sample_button.dart        # Individual sample button
    ├── sample_editor.dart        # Sample editing interface
    ├── sample_grid.dart          # Grid layout
    ├── transport_controls.dart   # Playback controls
    └── waveform_viewer.dart      # Waveform display
```

## Dependencies

### Core Dependencies
- **just_audio**: Audio playback engine
- **audio_session**: Audio session management
- **flutter_audio_waveforms**: Waveform visualization
- **file_picker**: File selection
- **path_provider**: File system access
- **provider**: State management
- **shared_preferences**: Data persistence

### UI Dependencies
- **flutter_staggered_grid_view**: Grid layout
- **flutter_slidable**: Swipe actions
- **permission_handler**: Device permissions

## Development

### Architecture
The application follows the Provider pattern for state management:
- **AudioProvider**: Manages audio playback and effects
- **SampleProvider**: Handles sample data and persistence

### Key Components
- **AudioSample Model**: Represents individual audio samples with metadata
- **Waveform Viewer**: Custom painter for audio visualization
- **Sample Grid**: Masonry layout with dynamic sizing
- **Effects Panel**: Real-time audio processing controls

### Customization
- **Themes**: Dark theme optimized for live performance
- **Layout**: Responsive design for different screen sizes
- **Effects**: Extensible effects system for audio processing

## Performance Considerations

### Audio Processing
- Samples are loaded on-demand to conserve memory
- Waveform data is cached for smooth visualization
- Effects are applied in real-time with minimal latency

### UI Performance
- Grid uses lazy loading for large sample collections
- Animations are hardware accelerated
- Gesture detection is optimized for touch interfaces

## Troubleshooting

### Common Issues

**Audio not playing:**
- Check device permissions for microphone and storage
- Ensure audio files are in supported formats (MP3, WAV, M4A)
- Verify audio session configuration

**Performance issues:**
- Reduce number of samples in grid
- Close other audio applications
- Check available system memory

**Build errors:**
- Update Flutter SDK to latest version
- Clear build cache: `flutter clean`
- Reinstall dependencies: `flutter pub get`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Create an issue on GitHub
- Check the documentation
- Review the troubleshooting guide

## Roadmap

### Planned Features
- **MIDI Support**: External controller integration
- **Sample Packs**: Import/export sample collections
- **Advanced Effects**: EQ, compression, and filters
- **Cloud Sync**: Sample backup and sharing
- **Recording**: Built-in audio recording
- **Automation**: Scheduled sample playback
- **Multi-track**: Layer multiple samples
- **VST Support**: Plugin integration (desktop)

### Performance Improvements
- **Audio Engine**: Lower latency playback
- **Waveform Rendering**: Hardware acceleration
- **Memory Management**: Better sample caching
- **Touch Response**: Improved gesture handling 