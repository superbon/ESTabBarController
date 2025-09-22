//
//  Created by Vincent Li on 2017/2/8.
//  Copyright (c) 2013-2020 ESTabBarController (https://github.com/eggswift/ESTabBarController)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit

/// 是否需要自定义点击事件回调类型
public typealias ESTabBarControllerShouldHijackHandler = ((_ tabBarController: UITabBarController, _ viewController: UIViewController, _ index: Int) -> (Bool))
/// 自定义点击事件回调类型
public typealias ESTabBarControllerDidHijackHandler = ((_ tabBarController: UITabBarController, _ viewController: UIViewController, _ index: Int) -> (Void))

open class ESTabBarController: UITabBarController, ESTabBarDelegate {
    
    /// 打印异常
    public static func printError(_ description: String) {
        #if DEBUG
        print("ERROR: ESTabBarController catch an error '\(description)' \n")
        #endif
    }
    
    /// 当前tabBarController是否存在"More"tab
    public static func isShowingMore(_ tabBarController: UITabBarController?) -> Bool {
        return tabBarController?.moreNavigationController.parent != nil
    }

    /// Ignore next selection or not.
    fileprivate var ignoreNextSelection = false

    /// Should hijack select action or not.
    open var shouldHijackHandler: ESTabBarControllerShouldHijackHandler?
    /// Hijack select action.
    open var didHijackHandler: ESTabBarControllerDidHijackHandler?
    
    // MARK: - Selection bridging
    open override var selectedViewController: UIViewController? {
        willSet {
            guard let newValue = newValue else { return }
            guard !ignoreNextSelection else {
                ignoreNextSelection = false
                return
            }
            guard let tabBar = self.tabBar as? ESTabBar, let items = tabBar.items, let index = viewControllers?.firstIndex(of: newValue) else {
                return
            }
            let _ = (ESTabBarController.isShowingMore(self) && index > items.count - 1) ? items.count - 1 : index
            // Prevent direct select to avoid UIKit crash
            print("ESTabBarController.selectedViewController: skipping select call to prevent crash")
        }
    }
    
    open override var selectedIndex: Int {
        willSet {
            guard newValue != NSNotFound else { return }
            guard !ignoreNextSelection else {
                ignoreNextSelection = false
                return
            }
            if newValue >= 0 && newValue < viewControllers?.count ?? 0,
               let vc = viewControllers?[newValue],
               shouldHijackHandler?(self, vc, newValue) ?? false {
                print("ESTabBarController.selectedIndex: BLOCKED hijacked index \(newValue)")
                return
            }
            guard let tabBar = self.tabBar as? ESTabBar, let items = tabBar.items else {
                return
            }
            let _ = (ESTabBarController.isShowingMore(self) && newValue > items.count - 1) ? items.count - 1 : newValue
            print("ESTabBarController.selectedIndex: skipping select call to prevent crash")
        }
    }
    
    // MARK: - Lifecycle
    open override func viewDidLoad() {
        super.viewDidLoad()
        forceReplaceSystemTabBar(reason: "viewDidLoad")
        hideNativeTabBarSubviews()
        bringCustomTabBarToFront()
        view.layer.allowsGroupOpacity = false
        view.layer.shouldRasterize = false
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        forceReplaceSystemTabBar(reason: "viewWillAppear")
        hideNativeTabBarSubviews()
        bringCustomTabBarToFront()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        forceReplaceSystemTabBar(reason: "viewDidAppear")
        hideNativeTabBarSubviews()
        bringCustomTabBarToFront()
        if let es = tabBar as? ESTabBar {
            es.isHidden = false
            es.alpha = 1.0
        }
    }
    
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // UIKit may add a UITabBar back during layout on some transitions
        forceReplaceSystemTabBar(reason: "viewWillLayoutSubviews")
        hideNativeTabBarSubviews()
        bringCustomTabBarToFront()
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hideNativeTabBarSubviews()
        bringCustomTabBarToFront()
    }
    
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Appearance may be reset across trait changes
        forceReplaceSystemTabBar(reason: "traitCollectionDidChange")
        hideNativeTabBarSubviews()
        bringCustomTabBarToFront()
    }
    
    // MARK: - Ensure replacement on API usage
    open override func setViewControllers(_ viewControllers: [UIViewController]?, animated: Bool) {
        super.setViewControllers(viewControllers, animated: animated)
        DispatchQueue.main.async {
            self.forceReplaceSystemTabBar(reason: "setViewControllers")
            self.hideNativeTabBarSubviews()
            self.bringCustomTabBarToFront()
        }
    }
    
    /// Convenience method to change selectedIndex while preserving our custom tab bar setup.
    open func setSelectedIndex(_ selectedIndex: Int) {
        // Avoid triggering our selectedIndex override logic
        ignoreNextSelection = true
        self.selectedIndex = selectedIndex
        // Ensure we still have our custom bar after selection changes
        DispatchQueue.main.async {
            self.forceReplaceSystemTabBar(reason: "setSelectedIndex")
            self.hideNativeTabBarSubviews()
            self.bringCustomTabBarToFront()
        }
    }
    
    open override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        DispatchQueue.main.async {
            self.forceReplaceSystemTabBar(reason: "willMoveToParent")
            self.hideNativeTabBarSubviews()
        }
    }
    
    open override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        DispatchQueue.main.async {
            self.forceReplaceSystemTabBar(reason: "didMoveToParent")
            self.hideNativeTabBarSubviews()
            self.bringCustomTabBarToFront()
        }
    }
    
    // MARK: - UITabBar delegate
    public func tabBar(_ tabBar: UITabBar, shouldSelect item: UITabBarItem) -> Bool {
        guard let idx = tabBar.items?.firstIndex(of: item) else { return true }
        if let vc = viewControllers?[idx],
           shouldHijackHandler?(self, vc, idx) ?? false {
            didHijackHandler?(self, vc, idx)
            return false
        }
        return true
    }
    
    open override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let idx = tabBar.items?.firstIndex(of: item) else { return }
        if let vc = viewControllers?[idx],
           shouldHijackHandler?(self, vc, idx) ?? false {
            // blocked
            return
        }
        if idx == tabBar.items!.count - 1, ESTabBarController.isShowingMore(self) {
            ignoreNextSelection = true
            selectedViewController = moreNavigationController
            return
        }
        if let vc = viewControllers?[idx] {
            ignoreNextSelection = true
            selectedIndex = idx
            delegate?.tabBarController?(self, didSelect: vc)
        }
    }
    
    open override func tabBar(_ tabBar: UITabBar, willBeginCustomizing items: [UITabBarItem]) {
        (tabBar as? ESTabBar)?.updateLayout()
    }
    
    open override func tabBar(_ tabBar: UITabBar, didEndCustomizing items: [UITabBarItem], changed: Bool) {
        (tabBar as? ESTabBar)?.updateLayout()
    }
    
    // MARK: - ESTabBar delegate
    internal func tabBar(_ tabBar: UITabBar, shouldHijack item: UITabBarItem) -> Bool {
        if let idx = tabBar.items?.firstIndex(of: item), let vc = viewControllers?[idx] {
            return shouldHijackHandler?(self, vc, idx) ?? false
        }
        return false
    }
    
    internal func tabBar(_ tabBar: UITabBar, didHijack item: UITabBarItem) {
        if let idx = tabBar.items?.firstIndex(of: item), let vc = viewControllers?[idx] {
            didHijackHandler?(self, vc, idx)
        }
    }

    // MARK: - Replacement & Hiding
    private func forceReplaceSystemTabBar(reason: String) {
        if let current = self.tabBar as? ESTabBar {
            // Ensure wiring and appearance are intact
            current.delegate = self
            current.customDelegate = self
            current.tabBarController = self
            current.isHidden = false
            current.alpha = 1.0
            configureAppearance(for: current)
            return
        }
        // Replace any system UITabBar with ESTabBar
        let newTabBar = ESTabBar()
        newTabBar.delegate = self
        newTabBar.customDelegate = self
        newTabBar.tabBarController = self
        configureAppearance(for: newTabBar)
        self.setValue(newTabBar, forKey: "tabBar")
    }
    
    private func configureAppearance(for tabBar: ESTabBar) {
        tabBar.backgroundImage = UIImage()
        tabBar.shadowImage = UIImage()
        tabBar.isTranslucent = true
        tabBar.backgroundColor = .clear
        tabBar.layer.shadowOpacity = 0
        tabBar.layer.shadowColor = UIColor.clear.cgColor
        tabBar.layer.backgroundColor = UIColor.clear.cgColor

        if #available(iOS 13.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
            appearance.shadowImage = nil
            appearance.backgroundImage = nil
            tabBar.standardAppearance = appearance
            if #available(iOS 15.0, *) {
                tabBar.scrollEdgeAppearance = appearance
            }
        }
    }
    
    private func bringCustomTabBarToFront() {
        guard let esTabBar = self.tabBar as? ESTabBar else { return }
        // Ensure it's in the view hierarchy and on top
        if esTabBar.superview !== self.view {
            esTabBar.removeFromSuperview()
            self.view.addSubview(esTabBar)
        }
        self.view.bringSubviewToFront(esTabBar)
    }
    
    private func hideNativeTabBarSubviews() {
        // Remove any UITabBar instances that are not our ESTabBar
        for subview in self.view.subviews {
            if subview is UITabBar && !(subview is ESTabBar) {
                subview.removeFromSuperview()
            }
        }
        // Also hide any system tab bar buttons within our ESTabBar
        if let esTabBar = self.tabBar as? ESTabBar {
            let systemButtons = esTabBar.subviews.filter { subview -> Bool in
                if let cls = NSClassFromString("UITabBarButton") {
                    return subview.isKind(of: cls)
                }
                return false
            }
            for btn in systemButtons {
                btn.isHidden = true
                btn.isUserInteractionEnabled = false
                btn.alpha = 0.0
                // If UIKit re-added them, remove to be safe
                btn.removeFromSuperview()
            }
        }
    }
}
