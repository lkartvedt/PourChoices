//
//  Sex.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/10/26.
//


//
//  BACModel.swift
//  PourChoices
//
//  A physiologically-grounded blood-alcohol-concentration simulator.
//
//  This is an estimate with large individual variation. It is NOT a breathalyzer
//  and must never be used to decide whether someone can legally or safely drive.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  MODEL OVERVIEW
//  ─────────────────────────────────────────────────────────────────────────────
//  Three coupled states integrated with a self-contained fixed-step RK4 stepper
//  (no external ODE dependency — the system is tiny, non-stiff at minute
//  resolution, and discrete user events must interrupt integration anyway):
//
//      G  gut ethanol mass            (g)
//      C  blood ethanol concentration (g/L)   [exposed to UI as g/100mL = C/10]
//      S  gastric motility suppression (dimensionless, >= 0)
//
//  Absorption: a finished drink is consumed at a constant rate over the interval
//  since the previous drink, fed into the gut, then emptied into blood at rate ka.
//
//  Elimination: Michaelis-Menten (saturable ADH), so the descending limb curves
//  realistically. Vmax is derived from predicted LIVER MASS (Vauthey TLV from BSA)
//  divided by the ethanol distribution volume Vd. Because women carry roughly the
//  same absolute liver mass as men in a smaller Vd, their faster per-kg clearance
//  EMERGES from the division — no stipulated sex term, no calibration fudge.
//
//  Hepatic first-pass metabolism is deliberately NOT modeled. It is a measurement
//  artifact of saturable elimination meeting slow delivery, and the slow-input +
//  MM-eliminator structure reproduces it for free. Modeling it separately would
//  double-count.
//
//  Gastric state S: food and nicotine ADD to S; ka = kaFasting * exp(-lambda * S),
//  so suppression slows emptying. S itself decays at a rate proportional to ka,
//  so slow emptying clears suppression slowly. This single coupling produces both
//  (a) the food/nicotine INTERACTION (a cigarette prolongs the food effect) and
//  (b) FASTING DRIFT (no food -> S relaxes -> ka climbs back to the fasting
//  ceiling) without any separate logic.
//
//  Breathalyzer (Level 2): a reading resets blood C to the measured value and
//  continues integrating. The gut G and gastric S are left untouched (the reading
//  only observes blood). Parameters are not re-fit — that would be a future
//  Level 3 (recursive estimation) feature.
//
//  Units: mass in g, concentration in g/L, time in minutes (internally).
//

import Foundation

// MARK: - Public types

public enum Sex {
    case male
    case female
}

public enum BACEventKind {
    /// User finished a drink. `grams` is the ethanol mass of that drink. It is
    /// assumed consumed steadily over the interval since the previous drink (or
    /// session start).
    case finishedDrink(grams: Double)
    /// A glass of water.
    case water
    /// A slice of pizza or comparable quantity of food.
    case food
    /// A cigarette or comparable nicotine dose.
    case nicotine
    /// A breathalyzer reading in g/100mL (e.g. 0.08). Resets the blood state.
    case breathalyzer(bac: Double)
}

public struct BACEvent {
    public let time: TimeInterval   // seconds since session start
    public let duration: TimeInterval
    public let kind: BACEventKind
    public init(time: TimeInterval, kind: BACEventKind, duration: TimeInterval = 0) {
        self.time = time
        self.duration = duration
        self.kind = kind
    }
}

public struct BACSample {
    public let time: TimeInterval   // seconds since session start
    public let bac: Double          // g/100mL
    public let ka: Double           // current absorption rate (per min) — useful for debugging/plots
}

public struct BACResult {
    public let curve: [BACSample]
    public let peakBAC: Double            // g/100mL
    public let peakTime: TimeInterval     // seconds
    public let currentBAC: Double         // g/100mL at the last sample

    /// First time (seconds since session start) after the peak that BAC falls
    /// below `threshold`, or nil if it never rises above it within the window.
    public func timeBelow(_ threshold: Double) -> TimeInterval? {
        var lastAbove: Int? = nil
        for (i, s) in curve.enumerated() where s.bac >= threshold { lastAbove = i }
        guard let idx = lastAbove, idx + 1 < curve.count else { return nil }
        return curve[idx + 1].time
    }
}

// MARK: - Person / physiology

public struct Person {
    public let sex: Sex
    public let ageYears: Double
    public let heightCm: Double
    public let weightKg: Double

    /// Optional multiplier on hepatic clearance. 1.0 = population typical.
    /// Chronic heavy drinkers induce CYP2E1 and run higher (up to ~1.7).
    public let clearanceMultiplier: Double

    public init(sex: Sex,
                ageYears: Double,
                heightCm: Double,
                weightKg: Double,
                clearanceMultiplier: Double = 1.0) {
        self.sex = sex
        self.ageYears = ageYears
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.clearanceMultiplier = clearanceMultiplier
    }

    /// Total body water (liters), Watson equation.
    public var totalBodyWaterL: Double {
        switch sex {
        case .male:
            return 2.447 - 0.09516 * ageYears + 0.1074 * heightCm + 0.3362 * weightKg
        case .female:
            return -2.097 + 0.1069 * heightCm + 0.2466 * weightKg
        }
    }

    /// Widmark distribution factor r (L/kg).
    public var widmarkR: Double { totalBodyWaterL / (0.806 * weightKg) }

    /// Ethanol volume of distribution (liters).
    public var distributionVolumeL: Double { widmarkR * weightKg }

    /// Body surface area (m²), Mosteller.
    public var bsaM2: Double { (heightCm * weightKg / 3600.0).squareRoot() }

    /// Predicted liver mass (kg). Vauthey total liver volume from BSA, converted
    /// to mass at ~1.05 g/mL, with a sane floor.
    public var liverMassKg: Double {
        let tlvML = 1267.28 * bsaM2 - 794.41        // Vauthey (Western adults)
        let massG = max(tlvML, 800.0) * 1.05
        return massG / 1000.0
    }
}

// MARK: - Model constants

public struct BACModelConstants {
    // --- Elimination ---
    /// Michaelis constant (g/L). Intrinsic ADH property; does not scale with size.
    public var km: Double = 0.105

    /// Reference BAC (g/L) at which the observed liver-normalized elimination rate
    /// below was measured. Used once to convert that observed rate into a TRUE
    /// Vmax via (Km + Cref)/Cref. 1.0 g/L ≈ 0.10 g/100mL, mid elimination phase.
    public var referenceBACgL: Double = 1.0

    /// Observed hepatic ethanol clearance per kg of liver (g ethanol / kg-liver / hr).
    /// ~5.0 from liver-weight studies; statistically the same in both sexes (the
    /// finding that makes the liver-mass approach legitimate).
    public var clearancePerKgLiverPerHr: Double = 5.0

    // --- Absorption / gastric state ---
    /// Fasting ceiling for the absorption rate constant (per minute).
    public var kaFasting: Double = 0.08

    /// ka = kaFasting * exp(-lambda * S). Larger lambda = stronger slowing per unit S.
    public var lambda: Double = 1.0

    /// S decays as dS/dt = -gamma * ka * S. Couples suppression clearance to emptying.
    public var gamma: Double = 0.6

    /// Amount added to S by ONE SLICE of pizza (or comparable). A full meal is a
    /// few taps; because S is additive and decays slowly, repeated slices
    /// correctly compound into a longer, deeper suppression — meal behavior
    /// emerges from repeated single-slice events.
    public var foodS: Double = 0.6
    /// Amount added to S by one nicotine event. Calibrated so ka drops ~0.75x,
    /// matching the ~1.5x lengthening of gastric emptying time observed for smoking
    /// after 4 cigarettes.
    public var nicotineS: Double = 0.1
    /// Water has a small, brief motility effect; mostly it dilutes.
    public var waterS: Double = 0.15

    /// Gastric suppression injected as a synthetic food event at session start
    /// when the user reports starting fed. Modeled identically to tapping the
    /// food button (it adds to S and decays on the ka-coupled clock), so "I ate
    /// before going out" and "I ate a slice during" use the same physics. A
    /// pre-session meal is larger than one slice, hence > foodS. Set the session
    /// to start fasting by passing startsFed=false in BACTuning (seed = 0).
    public var startedFedS: Double = 0.6

    /// Physiological bounds on the absorption rate constant ka (per minute),
    /// from realistic gastric-emptying half-lives (~8 min fast to ~2 h slow):
    ///   kaMax 0.087 ≈ t½ 8 min   (fast, dilute, empty stomach)
    ///   kaMin 0.006 ≈ t½ 116 min (large fatty meal / heavy suppression)
    /// The exp() form already keeps ka <= kaFasting, but the floor prevents a
    /// stack of food + cigarettes from driving emptying unphysically near zero.
    public var kaMin: Double = 0.006
    public var kaMax: Double = 0.087

    // --- Drink absorption ---
    /// Gastric (stomach-wall) bioavailability. The only first-pass term; hepatic
    /// FPM is emergent. ~0.92-0.95 realistic; 1.0 fine for v1.
    public var gastricBioavailability: Double = 1.0

    // --- Breathalyzer ---
    /// Readings within this many seconds of finishing a drink are flagged as
    /// likely mouth-alcohol contamination (the solver still applies them, but the
    /// flag lets the UI warn or discard).
    public var mouthAlcoholGuardSeconds: TimeInterval = 15 * 60

    public init() {}
}

// MARK: - Per-user tuning

/// The subset of model parameters intended to be user-adjustable from a settings
/// screen. Everything here is a multiplier or simple shift on a physiological
/// default, so the UI can present sliders in intuitive ranges without the user
/// needing to understand Vmax or ka. Apply with `BACModelConstants.applying(_:)`.
///
/// Suggested slider ranges (clamped on apply):
///   metabolismScale     0.6 ... 1.7   (slow metabolizer ... induced heavy drinker)
///   absorptionScale     0.7 ... 1.4   (slow absorber ... fast absorber)
///   startsFed           Bool          (injects a start-of-session food seed)
public struct BACTuning {
    /// Scales hepatic clearance (Vmax). 1.0 = population typical. This is applied
    /// on top of Person.clearanceMultiplier, so you can use Person for a known
    /// medical reason and BACTuning for user self-calibration independently.
    public var metabolismScale: Double = 1.0

    /// Scales the absorption rate ceiling kaFasting. >1 = empties faster.
    public var absorptionScale: Double = 1.0

    /// Whether the user typically starts a session having eaten.
    public var startsFed: Bool = true

    public init(metabolismScale: Double = 1.0,
                absorptionScale: Double = 1.0,
                startsFed: Bool = true) {
        self.metabolismScale = metabolismScale
        self.absorptionScale = absorptionScale
        self.startsFed = startsFed
    }

    public static let `default` = BACTuning()
}

public extension BACModelConstants {
    /// Returns a copy of these constants with user tuning applied (values clamped
    /// to safe ranges). Use this to build the constants you hand to BACSolver.
    func applying(_ tuning: BACTuning) -> BACModelConstants {
        var c = self
        let metab = min(max(tuning.metabolismScale, 0.6), 1.7)
        let absorp = min(max(tuning.absorptionScale, 0.7), 1.4)
        c.clearancePerKgLiverPerHr = self.clearancePerKgLiverPerHr * metab
        c.kaFasting = min(self.kaFasting * absorp, self.kaMax)
        // Fasting start zeroes the synthetic start-of-session food seed.
        c.startedFedS = tuning.startsFed ? self.startedFedS : 0.0
        return c
    }
}

// MARK: - Solver

public final class BACSolver {

    private let person: Person
    private let k: BACModelConstants
    private static let secondsPerMinute = 60.0

    public init(person: Person, constants: BACModelConstants = BACModelConstants()) {
        self.person = person
        self.k = constants
    }

    /// Convert a pour to grams of ethanol. density of ethanol = 0.789 g/mL.
    public static func grams(volumeML: Double, abvPercent: Double) -> Double {
        volumeML * (abvPercent / 100.0) * 0.789
    }

    /// OPTIONAL absorption modifier from beverage concentration. NOT used by v1.
    ///
    /// Absorption is fastest in the ~15-30% ABV band; below that the large water
    /// volume dilutes and slows emptying (beer), above ~40% the spirit irritates
    /// the mucosa and slows it (straight liquor). So the relationship is a HUMP,
    /// not monotonic — modeling "more water = faster" would be wrong. This returns
    /// a multiplier on ka peaking at 1.0 near 20% ABV and falling off both sides.
    ///
    /// To use it, multiply a drink's effective ka by this factor. Left out of the
    /// default model because it needs per-drink ABV and the effect is second-order;
    /// wire it in if/when drinks carry ABV metadata.
    public static func concentrationKaFactor(abvPercent: Double) -> Double {
        let optimum = 20.0
        let width = 18.0   // Gaussian-ish falloff; ~0.6 at 5% and at 40%
        let z = (abvPercent - optimum) / width
        return max(exp(-z * z), 0.5)   // floor so nothing absorbs absurdly slowly
    }

    /// True Vmax for the MM equation, in g/L per minute.
    /// Chain: observed clearance per kg-liver -> absolute g/hr (× liver mass) ->
    /// true Vmax (× (Km+Cref)/Cref) -> per-minute -> per-distribution-volume.
    private var vmaxGLPerMin: Double {
        let liverKg = person.liverMassKg
        let observedAbsGPerHr = k.clearancePerKgLiverPerHr
            * person.clearanceMultiplier
            * liverKg
        let trueVmaxAbsGPerHr = observedAbsGPerHr
            * (k.km + k.referenceBACgL) / k.referenceBACgL
        let trueVmaxAbsGPerMin = trueVmaxAbsGPerHr / 60.0
        return trueVmaxAbsGPerMin / person.distributionVolumeL
    }

    /// Simulate the BAC curve.
    public func simulate(events: [BACEvent],
                         until tail: TimeInterval = 6 * 3600,
                         stepSeconds: TimeInterval = 30) -> BACResult {

        let sorted = events.sorted { $0.time < $1.time }
        let dtMin = stepSeconds / Self.secondsPerMinute
        let Vd = person.distributionVolumeL
        let vmax = vmaxGLPerMin
        let km = k.km

        // --- Drink input windows (constant-rate consumption) ---
        struct DrinkWindow { let start: Double; let end: Double; let rate: Double } // min, min, g/min
        var drinkWindows: [DrinkWindow] = []
        var prevDrinkEndMin = 0.0
        for e in sorted {
            if case let .finishedDrink(grams) = e.kind {
                let endMin = e.time / Self.secondsPerMinute
                let startMin = e.duration > 0.0 ? endMin - e.duration : prevDrinkEndMin
                let windowMin = max(endMin - startMin, 0.000001)
                let rate = (grams * k.gastricBioavailability) / windowMin
                drinkWindows.append(DrinkWindow(start: startMin, end: endMin, rate: rate))
                prevDrinkEndMin = endMin
            }
        }
        func intake(at tMin: Double) -> Double {
            var s = 0.0
            for w in drinkWindows where tMin >= w.start && tMin < w.end { s += w.rate }
            return s
        }

        // --- Discrete S-additions (food / water / nicotine) ---
        struct SBump { let timeMin: Double; let amount: Double }
        var sBumps: [SBump] = []
        // "Started fed" is modeled as a synthetic food event at t=0, identical in
        // mechanism to a food-button tap, so it persists and decays correctly
        // rather than being a weak initial condition that drains immediately.
        if k.startedFedS > 0 {
            sBumps.append(SBump(timeMin: 0.0, amount: k.startedFedS))
        }
        for e in sorted {
            let tMin = e.time / Self.secondsPerMinute
            switch e.kind {
            case .food:     sBumps.append(SBump(timeMin: tMin, amount: k.foodS))
            case .nicotine: sBumps.append(SBump(timeMin: tMin, amount: k.nicotineS))
            case .water:    sBumps.append(SBump(timeMin: tMin, amount: k.waterS))
            default: break
            }
        }
        sBumps.sort { $0.timeMin < $1.timeMin }

        // --- Breathalyzer resets ---
        struct BreathReset { let timeMin: Double; let cgL: Double }
        var breaths: [BreathReset] = []
        for e in sorted {
            if case let .breathalyzer(bac) = e.kind {
                breaths.append(BreathReset(timeMin: e.time / Self.secondsPerMinute, cgL: bac * 10.0))
            }
        }
        breaths.sort { $0.timeMin < $1.timeMin }

        // ka from gastric state, clamped to physiological bounds.
        func ka(forS S: Double) -> Double {
            let raw = k.kaFasting * exp(-k.lambda * S)
            return min(max(raw, k.kaMin), k.kaMax)
        }

        // Derivatives. State vector (G, C, S).
        func deriv(_ tMin: Double, _ G: Double, _ C: Double, _ S: Double)
            -> (dG: Double, dC: Double, dS: Double) {
            let kaNow = ka(forS: S)
            let absorption = kaNow * G
            let dG = intake(at: tMin) - absorption
            var dC = absorption / Vd - (vmax * C) / (km + C)
            if C <= 0 && dC < 0 { dC = 0 }
            let dS = -k.gamma * kaNow * S
            return (dG, dC, dS)
        }

        // --- Integrate ---
        let endMin = (sorted.last?.time ?? 0) / Self.secondsPerMinute + tail / Self.secondsPerMinute
        var t = 0.0
        var G = 0.0
        var C = 0.0
        var S = 0.0   // all gastric suppression comes from events (incl. fed seed)

        var curve: [BACSample] = []
        var peakBAC = 0.0
        var peakTimeMin = 0.0

        let sampleEverySteps = max(1, Int(300 / stepSeconds))
        var stepIndex = 0
        var nextBumpIdx = 0
        var nextBreathIdx = 0

        print(endMin)
        print(drinkWindows)
        while t <= endMin {
            // Apply any S bumps whose time we've reached.
            while nextBumpIdx < sBumps.count && t >= sBumps[nextBumpIdx].timeMin {
                S += sBumps[nextBumpIdx].amount
                nextBumpIdx += 1
            }
            // Apply any breathalyzer resets (blood only).
            while nextBreathIdx < breaths.count && t >= breaths[nextBreathIdx].timeMin {
                C = breaths[nextBreathIdx].cgL
                nextBreathIdx += 1
            }

            if stepIndex % sampleEverySteps == 0 {
                let bac = C / 10.0
                curve.append(BACSample(time: t * Self.secondsPerMinute, bac: bac, ka: ka(forS: S)))
                if bac > peakBAC { peakBAC = bac; peakTimeMin = t }
            }
            stepIndex += 1

            let (k1G, k1C, k1S) = deriv(t, G, C, S)
            let (k2G, k2C, k2S) = deriv(t + dtMin/2, G + dtMin/2*k1G, C + dtMin/2*k1C, S + dtMin/2*k1S)
            let (k3G, k3C, k3S) = deriv(t + dtMin/2, G + dtMin/2*k2G, C + dtMin/2*k2C, S + dtMin/2*k2S)
            let (k4G, k4C, k4S) = deriv(t + dtMin,   G + dtMin*k3G,   C + dtMin*k3C,   S + dtMin*k3S)

            G += dtMin/6 * (k1G + 2*k2G + 2*k3G + k4G)
            C += dtMin/6 * (k1C + 2*k2C + 2*k3C + k4C)
            S += dtMin/6 * (k1S + 2*k2S + 2*k3S + k4S)
            if G < 0 { G = 0 }
            if C < 0 { C = 0 }
            if S < 0 { S = 0 }
            t += dtMin
        }
        
        let almostPeakTime = (curve.first(where: { $0.bac >= 0.9*peakBAC })?.time ?? peakTimeMin) / Self.secondsPerMinute

        return BACResult(curve: curve,
                         peakBAC: peakBAC,
                         peakTime: almostPeakTime,
                         currentBAC: curve.last?.bac ?? 0.0)
    }

    /// Returns true if a breathalyzer reading at `time` is likely contaminated by
    /// mouth alcohol (a drink was finished within the guard window before it).
    public func isLikelyMouthAlcohol(readingTime: TimeInterval, events: [BACEvent]) -> Bool {
        for e in events {
            if case .finishedDrink = e.kind {
                let dt = readingTime - e.time
                if dt >= 0 && dt < k.mouthAlcoholGuardSeconds { return true }
            }
        }
        return false
    }
}

// MARK: - Usage
//
//  let person = Person(sex: .female, ageYears: 30, heightCm: 165, weightKg: 60)
//  let solver = BACSolver(person: person)
//
//  let events: [BACEvent] = [
//      BACEvent(time: 10*60,  kind: .food),
//      BACEvent(time: 20*60,  kind: .finishedDrink(grams: 14)),
//      BACEvent(time: 50*60,  kind: .nicotine),
//      BACEvent(time: 60*60,  kind: .finishedDrink(grams: 14)),
//      BACEvent(time: 65*60,  kind: .water),
//      BACEvent(time: 100*60, kind: .finishedDrink(grams: 14)),
//      BACEvent(time: 130*60, kind: .breathalyzer(bac: 0.09)),  // anchors the curve
//  ]
//
//  let result = solver.simulate(events: events)
//  // result.curve -> SwiftUI Chart; result.peakBAC, result.timeBelow(0.05), etc.
