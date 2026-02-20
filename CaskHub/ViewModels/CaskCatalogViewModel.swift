//
//  CaskCatalogViewModel.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class CaskCatalogViewModel {
    private(set) var casks: [Cask] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let apiClient: BrewAPIClientProtocol

    init(apiClient: BrewAPIClientProtocol = BrewAPIClient()) {
        self.apiClient = apiClient
    }

    func fetchCasks() async {
        isLoading = true
        errorMessage = nil

        do {
            casks = try await apiClient.fetchAllCasks()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
