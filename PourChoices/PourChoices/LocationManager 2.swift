//
//  LocationManager.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import Foundation
import CoreLocation
import SwiftUI

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentLocation: CLLocation?
    var lastLoggedLocation: CLLocation?
    var currentPlaceName: String?
    var isTracking = false
    
    // Minimum distance in meters to consider it a new location (helps with bar hopping sensitivity)
    private let minimumDistanceThreshold: Double = 50.0 // ~164 feet
    
    // Callback for when a new location should be added
    var onLocationChange: ((CLLocation, String?) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 30 // Update when moved 30 meters
        authorizationStatus = manager.authorizationStatus
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        
        isTracking = true
        manager.startUpdatingLocation()
    }
    
    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
        lastLoggedLocation = nil
        currentPlaceName = nil
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            if isTracking {
                manager.startUpdatingLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        // Check if we've moved far enough to log a new location
        if shouldLogNewLocation(location) {
            reverseGeocodeLocation(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    // MARK: - Private Helpers
    
    private func shouldLogNewLocation(_ newLocation: CLLocation) -> Bool {
        guard let lastLocation = lastLoggedLocation else {
            // First location, always log it
            return true
        }
        
        let distance = newLocation.distance(from: lastLocation)
        
        // Only log if we've moved more than the threshold
        // This prevents logging when you're just walking around the same bar
        return distance > minimumDistanceThreshold
    }
    
    private func reverseGeocodeLocation(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Geocoding error: \(error.localizedDescription)")
                // Still log the location, just without a name
                self.lastLoggedLocation = location
                self.onLocationChange?(location, nil)
                return
            }
            
            guard let placemark = placemarks?.first else {
                self.lastLoggedLocation = location
                self.onLocationChange?(location, nil)
                return
            }
            
            // Try to get the best name for the location
            let placeName = self.extractPlaceName(from: placemark)
            self.currentPlaceName = placeName
            self.lastLoggedLocation = location
            
            // Notify the callback
            self.onLocationChange?(location, placeName)
        }
    }
    
    private func extractPlaceName(from placemark: CLPlacemark) -> String? {
        // Priority order for place names:
        // 1. Name (usually the business/POI name like "The Shellback Tavern")
        // 2. Thoroughfare (street name) + subThoroughfare (number)
        // 3. Locality (city name)
        
        if let name = placemark.name,
           let areasOfInterest = placemark.areasOfInterest,
           !areasOfInterest.isEmpty {
            // If we have a POI that matches the name, use it
            if areasOfInterest.contains(name) {
                return name
            }
            // Otherwise use the first area of interest (likely a landmark/business)
            return areasOfInterest.first
        }
        
        if let name = placemark.name {
            // Check if it's not just a street address
            if !name.contains(where: { $0.isNumber }) || name.count < 10 {
                return name
            }
        }
        
        // Fallback to street address
        var components: [String] = []
        if let number = placemark.subThoroughfare {
            components.append(number)
        }
        if let street = placemark.thoroughfare {
            components.append(street)
        }
        
        if !components.isEmpty {
            return components.joined(separator: " ")
        }
        
        // Last resort: city name
        return placemark.locality
    }
    
    // Manual location logging (for the button)
    func logCurrentLocation(completion: @escaping (CLLocation?, String?) -> Void) {
        guard let location = currentLocation else {
            completion(nil, nil)
            return
        }
        
        reverseGeocodeLocation(location)
        
        // Give geocoding a moment to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            completion(self?.currentLocation, self?.currentPlaceName)
        }
    }
}
