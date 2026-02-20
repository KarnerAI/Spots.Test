//
//  ProfileView.swift
//  Spots.Test
//
//  Created by Hussain Alam on 12/29/25.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack {
                Text("Profile")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.gray900)

                Text("Coming soon")
                    .font(.system(size: 16))
                    .foregroundColor(.gray500)
                    .padding(.top, 8)

                Button("Log out") {
                    viewModel.signOut()
                }
                .padding(.top, 24)
            }
        }
    }
}

#Preview {
    ProfileView().environmentObject(AuthenticationViewModel())
}

