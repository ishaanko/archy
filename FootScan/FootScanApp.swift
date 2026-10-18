//
//  FootScanApp.swift
//  FootScan
//
//  Created by Pranav Narsipur on 10/17/26.
//

import SwiftUI
import CoreData

@main
struct FootScanApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
