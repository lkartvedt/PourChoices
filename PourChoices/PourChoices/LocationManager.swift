//
//  LocationManager.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import Foundation
import CoreLocation
import MapKit

@Observable
class LocationTracker: NSObject {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isTracking = false
    
    // Callback for when a significant location change happens
    var onSignificantLocationChange: ((CLLocation, String?) -> Void)?
    
    // Track last recorded location to avoid duplicates
    private var lastRecordedLocation: CLLocation?
    private let minimumDistanceThreshold: CLLocationDistance = 50.0 // meters (about 164 feet)
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 50 // Update every 50 meters
        locationManager.activityType = .other
        authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        
        locationManager.startUpdatingLocation()
        isTracking = true
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        isTracking = false
        lastRecordedLocation = nil
    }
    
    // Get place name from coordinates
    func getPlaceName(for location: CLLocation) async -> String? {
        return await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // PRIORITY 1: Areas of Interest (likely business/venue names)
                if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
                    // Return the first area of interest (usually the business name)
                    continuation.resume(returning: areasOfInterest.first!)
                    return
                }
                
                // PRIORITY 2: Name field (if it looks like a business, not an address)
                if let name = placemark.name {
                    // If name has very few numbers or is long, it's probably a venue
                    let numberCount = name.filter({ $0.isNumber }).count
                    if numberCount <= 1 || name.count > 30 {
                        continuation.resume(returning: name)
                        return
                    }
                }
                
                // PRIORITY 3: Street address as last resort
                var components: [String] = []
                if let number = placemark.subThoroughfare {
                    components.append(number)
                }
                if let street = placemark.thoroughfare {
                    components.append(street)
                }
                
                if !components.isEmpty {
                    continuation.resume(returning: components.joined(separator: " "))
                    return
                }
                
                // LAST RESORT: City name
                continuation.resume(returning: placemark.locality)
            }
        }
    }
    
    // Alternative: Search for nearby bars/restaurants using MapKit
    func searchNearbyVenues(at location: CLLocation, radius: CLLocationDistance = 100) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        // Cast a wider net - search for all food and drink places
        request.naturalLanguageQuery = "bar restaurant food drink"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        // Search for points of interest
        request.resultTypes = .pointOfInterest
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            
            // DEBUG: Print all results
            print("🔍 MapKit Search found \(response.mapItems.count) venues:")
            for (index, item) in response.mapItems.prefix(10).enumerated() {
                let dist = item.placemark.location?.distance(from: location) ?? 0
                print("  \(index + 1). \(item.name ?? "Unknown") - \(Int(dist))m away")
            }
            
            // Sort by distance from current location
            let sorted = response.mapItems.sorted { item1, item2 in
                let distance1 = item1.placemark.location?.distance(from: location) ?? .infinity
                let distance2 = item2.placemark.location?.distance(from: location) ?? .infinity
                return distance1 < distance2
            }
            
            return sorted
        } catch {
            print("❌ Search error: \(error.localizedDescription)")
            return []
        }
    }
    
    // Get best venue name (tries nearby search first, falls back to geocoding)
    func getBestVenueName(for location: CLLocation) async -> String {
        print("📍 Getting venue name for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // First try to find nearby venues with a generous radius
        print("🔎 Searching for venues within 200m...")
        let venues = await searchNearbyVenues(at: location, radius: 200)
        
        // Take the absolute closest venue if we found any
        if let closestVenue = venues.first,
           let venueLocation = closestVenue.placemark.location {
            let distance = venueLocation.distance(from: location)
            let distanceInMeters = Int(distance)
            
            print("✅ Found closest venue: \(closestVenue.name ?? "Unknown") at \(distanceInMeters)m")
            
            // ONLY use venues that are actually nearby (within 200m)
            if distance < 200 {
                return closestVenue.name ?? "Unknown Venue"
            } else {
                print("❌ Closest venue is TOO FAR (\(distanceInMeters)m / \(Int(distance * 3.28084))ft) - ignoring it")
            }
        } else {
            print("❌ No venues found in MapKit search")
        }
        
        print("🔍 No nearby venues found, trying reverse geocoding...")
        
        // Try reverse geocoding for POI/areas of interest
        if let placeName = await getPlaceName(for: location) {
            print("✅ Geocoding returned: \(placeName)")
            
            // Check if it's likely a venue name (not just an address)
            let hasLotsOfNumbers = placeName.filter({ $0.isNumber }).count > 2
            if !hasLotsOfNumbers {
                return placeName
            } else {
                print("⚠️ Geocoding result looks like an address: \(placeName)")
            }
        }
        
        // Absolute fallback
        print("❌ No venue name found, using fallback")
        if let placeName = await getPlaceName(for: location) {
            return placeName
        }
        
        return "Unknown Location"
    }
    
    private func shouldRecordLocation(_ location: CLLocation) -> Bool {
        guard let lastLocation = lastRecordedLocation else {
            return true // First location, always record
        }
        
        // Check if we've moved enough distance
        let distance = location.distance(from: lastLocation)
        return distance >= minimumDistanceThreshold
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationTracker: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            if isTracking {
                locationManager.startUpdatingLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        
        // Check if this is a significant enough location change
        if shouldRecordLocation(location) {
            lastRecordedLocation = location
            
            // Get the venue name asynchronously
            Task {
                let venueName = await getBestVenueName(for: location)
                await MainActor.run {
                    onSignificantLocationChange?(location, venueName)
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}
