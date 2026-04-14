//
//  NewsFeedView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct NewsFeedView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            VStack {
                Text("News Feed")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.gray900)
                
                Text("Coming soon")
                    .font(.system(size: 16))
                    .foregroundColor(.gray500)
                    .padding(.top, 8)
            }
        }
    }
}

#Preview {
    NewsFeedView()
}

