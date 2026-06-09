# Location Tracking Setup

## Required Info.plist Keys

You need to add these keys to your `Info.plist` file:

### Privacy - Location When In Use Usage Description
**Key:** `NSLocationWhenInUseUsageDescription`

**Value:** 
```
Pour Choices tracks your location to automatically log bar hops and show your route on the map. Your location data stays private on your device.
```

## How to Add to Info.plist

### Option 1: In Xcode Project Settings
1. Select your project in the Project Navigator
2. Select the "PourChoices" target
3. Go to the "Info" tab
4. Click the "+" button to add a new key
5. Start typing "Location When In Use" and select it from the dropdown
6. Paste the description above

### Option 2: Directly in Info.plist
Add this to your Info.plist file:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Pour Choices tracks your location to automatically log bar hops and show your route on the map. Your location data stays private on your device.</string>
```

## How Location Tracking Works

### Automatic Tracking
- When you start a session, location tracking begins automatically
- The app monitors your location in the background (while in use)
- When you move **50+ meters** (~164 feet), it logs a new location
- Uses reverse geocoding to find the name of the place (e.g., "The Shellback Tavern")
- Falls back to street address or "Unknown Location" if no POI is found

### Manual Logging
- Tap "Log Location" to manually add your current spot
- Useful if you want to mark a specific location without waiting for auto-detection

### Sensitivity Features
- **50m threshold** prevents logging every time you step outside
- Perfect for bar hopping (going next door = ~30-50m usually)
- Won't spam your timeline with duplicate locations

### Privacy
- Location only tracked during active sessions
- Stops tracking when you end a session
- All data stays on device (using SwiftData)
- No server, no cloud sync (unless you add it later)

## Testing Tips

When testing in the simulator:
1. Use **Debug > Location > Custom Location** to set a test location
2. Or use **Debug > Location > City Run** to simulate movement
3. Check the console for geocoding results

On a real device:
1. Grant location permission when prompted
2. Walk around (or drive... wait, NO DRIVING! 🚗❌)
3. Watch locations auto-populate in the timeline
4. The "📍 Current Location" will show at the top when detected
