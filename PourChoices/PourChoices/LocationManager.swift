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
                
                // Try to get a business name or point of interest
                let name = placemark.name ?? placemark.thoroughfare ?? "Unknown Location"
                continuation.resume(returning: name)
            }
        }
    }
    
    // Alternative: Search for nearby bars/restaurants using MapKit
    func searchNearbyVenues(at location: CLLocation, radius: CLLocationDistance = 100) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "bar restaurant pub"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            // Sort by distance from current location
            let sorted = response.mapItems.sorted { item1, item2 in
                let distance1 = item1.placemark.location?.distance(from: location) ?? .infinity
                let distance2 = item2.placemark.location?.distance(from: location) ?? .infinity
                return distance1 < distance2
            }
            return sorted
        } catch {
            print("Search error: \(error.localizedDescription)")
            return []
        }
    }
    
    // Get best venue name (tries nearby search first, falls back to geocoding)
    func getBestVenueName(for location: CLLocation) async -> String {
        // First try to find nearby bars/restaurants
        let venues = await searchNearbyVenues(at: location, radius: 75)
        
        // If we found a venue within ~75 meters, use it
        if let closestVenue = venues.first,
           let venueLocation = closestVenue.placemark.location,
           venueLocation.distance(from: location) < 75 {
            return closestVenue.name ?? "Unknown Bar"
        }
        
        // Fall back to reverse geocoding
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
