# Easy Effects Profile Switcher

A Dank Material Shell plugin for quickly switching between Easy Effects profiles.

![Screenshot](screenshot.png)

## Features

- Shows currently active output and input profiles
- Click to open a menu with separate output and input profile sections
- Automatically detects and displays the currently active profiles
- Reload the profile list when you add new profiles
- Reset all presets to default state

## Requirements

- Easy Effects installed on your system
- Audio profiles configured in Easy Effects (output and/or input presets)

## Installation

1. Copy this plugin folder to your DMS plugins directory:

   ```bash
   mkdir -p ~/.config/DankMaterialShell/plugins/EasyEffects
   ```

2. The plugin will be automatically detected and can be enabled in DMS settings.

3. Configure your audio profiles in Easy Effects

## Usage

- Click the bar widget to open the profile menu
- Select profiles from output or input sections
- Click "Clear" (top right) to reset all presets
- Click refresh icon (top right) to reload profiles
- Click "Open Easy Effects" to launch the full application

## Configuration

Not much to it. The plugin should automatically detect both output and input presets.

## Permissions

- `settings_read`: Read saved profile selection
- `settings_write`: Save current profile selection

## Version

1.0.0
