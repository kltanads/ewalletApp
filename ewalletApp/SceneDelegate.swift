//
//  SceneDelegate.swift
//  ewalletApp
//
//  Created by Koon Lai Tan on 2026/11/3.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let viewModel = LockViewModel(
            authenticator: BiometricAuthenticator(),
            tokenStore: KeychainTokenStore(service: Constants.keychainService),
            backgroundTimeout: Constants.backgroundLockTimeout
        )
        let coordinator = AppCoordinator(lockViewModel: viewModel)
        self.window = window
        self.coordinator = coordinator
        coordinator.start(in: window)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        coordinator?.willResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        coordinator?.didEnterBackground()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        coordinator?.willEnterForeground()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        coordinator?.didBecomeActive()
    }
}
