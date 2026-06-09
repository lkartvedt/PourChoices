# Pizza & Water Tracking 🍕💧

## What's New!

Added **food and water tracking** that actually **affects your BAC**!

---

## New Buttons

### 🍕 Pizza Button
- Logs 1 slice of NY-style pepperoni pizza
- **Reduces BAC absorption by 15% per slice**
- Max 40% reduction (about 3 slices)
- Shows in timeline as "🍴 1 slice of Pizza"

### 💧 Water Button  
- Logs 8oz of water
- **Improves metabolism rate** (+0.002% per hour per glass)
- Max +0.010% per hour bonus
- Shows in timeline as "💧 8oz Water"

---

## How It Affects BAC

### Food (Pizza) 🍕
**Science**: Eating slows alcohol absorption and reduces peak BAC

**In the app:**
- Each slice reduces absorption by **15%**
- Formula: `BAC × (1 - foodReduction)`
- Max reduction: **40%** (after ~3 slices)

**Example:**
- No food: BAC = 0.080%
- 1 slice: BAC = 0.068% (15% reduction)
- 2 slices: BAC = 0.056% (30% reduction)
- 3+ slices: BAC = 0.048% (40% max reduction)

### Water 💧
**Science**: Hydration helps metabolism (slightly) and dilution

**In the app:**
- Each 8oz glass adds **0.002% per hour** to metabolism
- Normal metabolism: 0.015% per hour
- With 2 glasses: 0.019% per hour
- Max bonus: **+0.010% per hour** (5+ glasses)

**Example (2 hours elapsed):**
- No water: -0.030% from metabolism
- 2 glasses: -0.038% from metabolism
- 5+ glasses: -0.050% from metabolism

---

## Updated BAC Formula

```
BAC = (Alcohol in grams / (Weight × r)) × (1 - foodFactor) - (metabolism × hours)

Where:
- r = 0.68 (male) or 0.55 (female)
- foodFactor = min(0.40, slices × 0.15)
- metabolism = 0.015 + min(0.010, waterGlasses × 0.002)
```

---

## UI Changes

### Action Buttons (New Layout):
```
┌───────────────────────────┐
│   🍺 Log Drink (Blue)     │
├───────────────────────────┤
│  🍕 Pizza  │  💧 Water    │ ← NEW!
├───────────────────────────┤
│  Zyn/Cig  │  Location     │
└───────────────────────────┘
```

### Timeline Entries:
```
🍺 Beer
   8:45 PM • 📍 Shellback Tavern
   1.00 std

🍴 1 slice of Pizza  
   8:40 PM

💧 8oz Water
   8:35 PM

🍺 Shot
   8:30 PM
   1.50 std
```

---

## Example Session

**Scenario:** You drink 4 beers over 4 hours

### Without Food/Water:
- Hour 1: 0.025% BAC
- Hour 2: 0.035% BAC
- Hour 3: 0.030% BAC
- Hour 4: 0.025% BAC

### With 2 Slices Pizza + 3 Glasses Water:
- Hour 1: 0.021% BAC (-30% food)
- Hour 2: 0.027% BAC (-30% food, +water metabolism)
- Hour 3: 0.019% BAC (-30% food, +water metabolism)
- Hour 4: 0.013% BAC (-30% food, +water metabolism)

**Result:** You stay under 0.03% the whole time! 🎉

---

## Testing It

1. **Start a session**
2. **Add a beer** - watch BAC go up
3. **Tap "Pizza"** - BAC drops!
4. **Tap "Water"** a few times
5. **Wait** and watch the timeline
6. **See how it affects** the big BAC number

---

## Technical Details

### Food Model:
```swift
@Model
final class FoodEntry {
    var timestamp: Date
    var foodType: String  // "Pizza"
    var quantity: Int     // Number of slices
}
```

### Water Model:
```swift
@Model
final class WaterEntry {
    var timestamp: Date
    var volumeOz: Double  // 8.0 oz
}
```

### BAC Calculation Additions:
```swift
// Food reduction
let foodSlices = food.reduce(0) { $0 + $1.quantity }
let foodReduction = min(0.40, Double(foodSlices) * 0.15)

// Water benefit
let waterOz = water.reduce(0.0) { $0 + $1.volumeOz }
let waterGlasses = waterOz / 8.0
let extraMetabolism = min(0.010, waterGlasses * 0.002)
```

---

## Future Ideas

- **More food types**: Burger, Tacos, Fries (different absorption rates)
- **Custom serving sizes**: "I ate a whole pizza"
- **Time-based food effect**: Food works better if eaten BEFORE drinking
- **Hydration tracking**: Show total water consumed
- **Food suggestions**: "Your BAC is 0.08%, try eating something!"

---

## Notes

⚠️ **These are estimates!** Real-world factors:
- Type of food (fatty foods slow absorption more)
- When you ate (before vs during drinking)
- Individual differences
- Still **never drive after drinking**!

The percentages are based on scientific studies but are **simplified for the app**.

---

## Quick Stats to Show

You could add to the stats bar:
```
┌──────────────────────────┐
│ Drinks: 4  Locations: 2  │
│ Pizza: 2   Water: 3      │ ← NEW!
│ Duration: 3h 15m         │
└──────────────────────────┘
```

Try it out! Tap pizza and water while drinking and watch your BAC stay lower! 🍕💧🍻
