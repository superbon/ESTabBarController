//
//  ESTabBarController.swift
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
    
    /// Observer tabBarController's selectedViewController. change its selection when it will-set.
    open override var selectedViewController: UIViewController? {
        willSet {
            guard let newValue = newValue else {
                // if newValue == nil ...
                return
            }
            guard !ignoreNextSelection else {
                ignoreNextSelection = false
                return
            }
            guard let tabBar = self.tabBar as? ESTabBar, let items = tabBar.items, let index = viewControllers?.firstIndex(of: newValue) else {
                return
            }
            let value = (ESTabBarController.isShowingMore(self) && index > items.count - 1) ? items.count - 1 : index
            print("ESTabBarController.selectedViewController: skipping select call to prevent crash")
            // Skip calling tabBar.select to prevent "Directly modifying a tab bar managed by a tab bar controller is not allowed" crash
            // The system UITabBar will handle the selection through normal mechanisms
        }
    }
    
    /// Observer tabBarController's selectedIndex. change its selection when it will-set.
    open override var selectedIndex: Int {
        willSet {
            print("ESTabBarController.selectedIndex willSet: newValue=\(newValue)")
            guard !ignoreNextSelection else {
                ignoreNextSelection = false
                print("ESTabBarController.selectedIndex: ignoring due to ignoreNextSelection flag")
                return
            }
            
            // Check if the new index corresponds to a hijacked tab
            if newValue >= 0 && newValue < viewControllers?.count ?? 0,
               let vc = viewControllers?[newValue],
               shouldHijackHandler?(self, vc, newValue) ?? false {
                print("ESTabBarController.selectedIndex: BLOCKED hijacked index \(newValue)")
                // This is a hijacked tab - don't change selectedIndex
                return
            }
            
            print("ESTabBarController.selectedIndex: allowing change to \(newValue)")
            guard let tabBar = self.tabBar as? ESTabBar, let items = tabBar.items else {
                return
            }
            let value = (ESTabBarController.isShowingMore(self) && newValue > items.count - 1) ? items.count - 1 : newValue
            print("ESTabBarController.selectedIndex: skipping select call to prevent crash")
            // Skip calling tabBar.select to prevent "Directly modifying a tab bar managed by a tab bar controller is not allowed" crash
            // The system UITabBar will handle the selection through normal mechanisms
        }
    }
    
    /// Customize set tabBar use KVC.
    open override func viewDidLoad() {
        super.viewDidLoad()
        let tabBar = { () -> ESTabBar in 
            let tabBar = ESTabBar()
            tabBar.delegate = self
            tabBar.customDelegate = self
            tabBar.tabBarController = self
            
            // GLOBAL glass effect elimination for ALL tabs
            tabBar.layer.allowsGroupOpacity = false
            tabBar.layer.shouldRasterize = false
            
            // Completely disable system selection animations but preserve icon colors
            if #available(iOS 13.0, *) {
                tabBar.standardAppearance.selectionIndicatorTintColor = UIColor.clear
                tabBar.standardAppearance.selectionIndicatorImage = nil
                // Don't clear icon colors - let ESTabBar handle them
                // tabBar.standardAppearance.stackedLayoutAppearance.selected.iconColor = UIColor.clear
                // tabBar.standardAppearance.inlineLayoutAppearance.selected.iconColor = UIColor.clear
                // tabBar.standardAppearance.compactInlineLayoutAppearance.selected.iconColor = UIColor.clear
                
                if #available(iOS 15.0, *) {
                    tabBar.scrollEdgeAppearance = tabBar.standardAppearance
                }
            }
            
            // Legacy iOS support
            tabBar.selectionIndicatorImage = nil
            tabBar.backgroundImage = UIImage()
            tabBar.shadowImage = UIImage()
            
            return tabBar
        }()
        self.setValue(tabBar, forKey: "tabBar")
        
        // Global animation blocking at controller level
        self.view.layer.allowsGroupOpacity = false
        self.view.layer.shouldRasterize = false
    }

    // MARK: - UITabBar delegate
    public func tabBar(_ tabBar: UITabBar, shouldSelect item: UITabBarItem) -> Bool {
        guard let idx = tabBar.items?.firstIndex(of: item) else {
            return true
        }
        
        print("ESTabBarController.shouldSelect (system): index=\(idx)")
        
        // Check if this tab is hijacked - if so, block system selection entirely
        if let vc = viewControllers?[idx],
           shouldHijackHandler?(self, vc, idx) ?? false {
            print("ESTabBarController.shouldSelect (system): BLOCKING hijacked tab \(idx) and calling hijack handler")
            // Call the hijack handler directly here since we're blocking the selection
            didHijackHandler?(self, vc, idx)
            return false
        }
        
        print("ESTabBarController.shouldSelect (system): allowing non-hijacked tab \(idx)")
        return true
    }
    
    open override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let idx = tabBar.items?.firstIndex(of: item) else {
            return;
        }
        
        print("ESTabBarController.didSelect: index=\(idx)")
        
        // Check if this tab is hijacked - if so, don't change selectedIndex
        if let vc = viewControllers?[idx],
           shouldHijackHandler?(self, vc, idx) ?? false {
            print("ESTabBarController.didSelect: BLOCKED hijacked tab from changing selectedIndex")
            // This is a hijacked tab - don't change selection
            return
        }
        
        print("ESTabBarController.didSelect: proceeding with non-hijacked tab")
        // Note: Non-hijacked tab selection proceeds normally
        
        if idx == tabBar.items!.count - 1, ESTabBarController.isShowingMore(self) {
            ignoreNextSelection = true
            selectedViewController = moreNavigationController
            return;
        }
        if let vc = viewControllers?[idx] {
            ignoreNextSelection = true
            selectedIndex = idx
            delegate?.tabBarController?(self, didSelect: vc)
        }
    }
    
    open override func tabBar(_ tabBar: UITabBar, willBeginCustomizing items: [UITabBarItem]) {
        if let tabBar = tabBar as? ESTabBar {
            tabBar.updateLayout()
        }
    }
    
    open override func tabBar(_ tabBar: UITabBar, didEndCustomizing items: [UITabBarItem], changed: Bool) {
        if let tabBar = tabBar as? ESTabBar {
            tabBar.updateLayout()
        }
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
    
}
