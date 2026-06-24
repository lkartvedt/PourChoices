//
//  AgeVerificationView.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/15/26.
//

import SwiftUI

// MARK: - Age Verification View
struct AgeVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: UserProfile
    @Binding var showingOnboarding: Bool
    
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -21, to: Date()) ?? Date()
    @State private var showUnder21Alert = false
    
    var calculatedAge: Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthdate, to: Date())
        return ageComponents.year ?? 0
    }
    
    var isOver21: Bool {
        calculatedAge >= 21
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                
                // Header
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.accent)
                    
                    Text("Age Verification")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("You must be 21 or older to use this app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Birthdate picker
                VStack(spacing: 16) {
                    Text("Enter your birthdate")
                        .font(.headline)
                    
                    DatePicker("Birthdate", 
                              selection: $birthdate,
                              in: ...Date(),
                              displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.horizontal)
                }
                .padding(.vertical, 30)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Continue button
                Button(action: verifyAge) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isOver21 ? Color.accent : Color.gray, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .disabled(!isOver21)
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Age Requirement Not Met", isPresented: $showUnder21Alert) {
                Button("OK") { }
            } message: {
                Text("You must be 21 years or older to use Pour Choices. This app is intended for legal drinking age users only.")
            }
        }
    }
    
    private func verifyAge() {
        guard isOver21 else {
            showUnder21Alert = true
            return
        }
        
        // Save birthdate and mark verification as complete
        profile.birthdate = birthdate
        profile.hasCompletedAgeVerification = true
        
        // Dismiss this sheet first, then show onboarding
        dismiss()
        
        // Delay to allow sheet dismissal to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showingOnboarding = true
        }
    }
}
