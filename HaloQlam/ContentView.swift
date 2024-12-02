//
//  ContentView.swift
//  HaloQlam
//
//  Created by naim sassine on 02/12/2024.
//

import SwiftUI
import AccessorySetupKit

struct ContentView: View {
    @State var ringSessionManager = RingSessionManager()
    
    var body: some View {
        List {
            Section("MY DEVICE", content: {
                if ringSessionManager.pickerDismissed, let currentRing = ringSessionManager.currentRing {
                    makeRingView(ring: currentRing)
                } else {
                    Button {
                        ringSessionManager.presentPicker()
                    } label: {
                        Text("Add Ring")
                            .frame(maxWidth: .infinity)
                            .font(Font.headline.weight(.semibold))
                    }
                }
            })
        }.listStyle(.insetGrouped)
        
    }
    
    @ViewBuilder
    private func makeRingView(ring: ASAccessory) -> some View {
        HStack {
            Image("colmi")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 70)
            
            VStack(alignment: .leading) {
                Text(ring.displayName)
                    .font(Font.headline.weight(.semibold))
            }
        }
    }
}

#Preview {
    ContentView()
}
