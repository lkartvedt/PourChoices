# Testing Location Tracking in Pour Choices 📍

## Quick Test Guide

### ✅ What to Check First

1. **Start a session** - Tap "Start Session"
2. **Grant permission** - When prompted, tap "Allow While Using App"
3. **Look for the indicator** - You should see green text saying "Auto-tracking locations" under the BAC display

---

## Testing on iOS Simulator

### Method 1: Set a Specific Location (Easiest)

1. **In Xcode menu**: Debug → Location → Custom Location...
2. Try these coordinates for a known bar:
   
   **The Shellback Tavern (Manhattan Beach)**
   - Latitude: `33.8847`
   - Longitude: `-118.4109`
   
   **Or any bar you know:**
   - Find it on Google Maps
   - Right-click → "What's here?"
   - Copy the coordinates

3. **Set another location** 100+ meters away after a few seconds
4. **Watch the Timeline section** - new location should appear!

### Method 2: Simulate Movement

1. **In Xcode menu**: Debug → Location → City Run
   - This simulates you running around San Francisco
   - Great for testing the 50m threshold
   
2. **Or try**: Debug → Location → City Bicycle Ride
   - Simulates biking around (faster movement)

### Method 3: Freeway Drive (Fast testing)

1. **In Xcode menu**: Debug → Location → Freeway Drive
   - Simulates driving (moves quickly between locations)
   - You'll see multiple locations populate

---

## Testing on Real Device (Best Results)

### Option 1: Walk Around
1. **Start a session**
2. **Walk outside** to a nearby bar/restaurant
3. **Check the app** - should auto-log when you move 50+ meters
4. **Manually log** - Tap "Log Location" button to force a check-in

### Option 2: Drive Around (Passenger only! 🚗)
1. Have someone else drive
2. Pass by different bars/restaurants
3. Watch locations auto-populate

---

## Debugging: See What's Happening

### Add Console Logging

The app already prints to the console! **Open the debug console** in Xcode (bottom panel) and look for:

```
Geocoding error: [any errors]
Search error: [any errors]
Location manager error: [any errors]
```

### Check the Timeline

After moving locations, scroll down to the **Timeline** section:
- 📍 Green location pins = new locations logged
- Should show the venue name or street address

---

## Expected Behavior

### Automatic Logging:
- ✅ Triggers when you move **50+ meters** (~164 feet)
- ✅ Tries to find nearby bars/restaurants first
- ✅ Falls back to street address if no venue found
- ✅ Shows "Unknown Location" if geocoding fails

### Manual Logging:
- Tap **"Log Location"** button
- Instantly adds current location to timeline
- Searches for venue name in background
- May take 1-2 seconds to get the name

---

## Quick Simulator Test Script

**Copy/paste these steps:**

1. ▶️ **Run app** in simulator
2. 🚀 **Start session**
3. ✅ **Allow location** when prompted
4. 🎯 **Debug → Location → Custom Location**
   - Lat: `33.8847`, Long: `-118.4109` (Shellback Tavern)
5. ⏱️ **Wait 2-3 seconds**
6. 📍 **Check Timeline** - should show "The Shellback Tavern" or nearby address
7. 🔄 **Change location**: Debug → Location → Custom Location
   - Lat: `33.8900`, Long: `-118.4150` (different spot ~500m away)
8. ⏱️ **Wait 2-3 seconds**
9. 📍 **Check Timeline again** - new location should appear!

---

## Troubleshooting

### "Unknown Location" showing?
- The geocoder might not find a venue name
- Check the coordinates are valid
- Try a well-known landmark/bar

### No locations appearing?
- Make sure you moved **50+ meters**
- Check the green "Auto-tracking locations" indicator is showing
- Try tapping "Log Location" manually

### Permission issues?
- Check Settings → Privacy → Location Services
- Make sure "PourChoices" is set to "While Using"

---

## Advanced: Test with Real Bar Data

### Find a Real Bar to Test:

1. Open **Apple Maps** or **Google Maps**
2. Search for a bar (e.g., "bars near me")
3. Right-click → Get coordinates
4. Use those in Custom Location

### Example Real Bars:

**McSorley's Old Ale House (NYC)**
- Lat: `40.7290`, Long: `-73.9867`

**The Abbey (West Hollywood)**  
- Lat: `34.0900`, Long: `-118.3617`

**Bukowski Tavern (Boston)**
- Lat: `42.3467`, Long: `-71.0897`

---

## What Success Looks Like

✅ **Timeline shows**:
```
📍 The Shellback Tavern
   8:45 PM

🍷 Beer
   8:30 PM
   1.00 std

📍 Starting Location  
   8:15 PM
```

🎉 **You're done! The location tracking works!**
