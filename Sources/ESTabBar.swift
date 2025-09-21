//
//  ESTabBar.swift
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


/// 对原生的UITabBarItemPositioning进行扩展，通过UITabBarItemPositioning设置时，系统会自动添加insets，这使得添加背景样式的需求变得不可能实现。ESTabBarItemPositioning完全支持原有的item Position 类型，除此之外还支持完全fill模式。
///
/// - automatic: UITabBarItemPositioning.automatic
/// - fill: UITabBarItemPositioning.fill
/// - centered: UITabBarItemPositioning.centered
/// - fillExcludeSeparator: 完全fill模式，布局不覆盖tabBar顶部分割线
/// - fillIncludeSeparator: 完全fill模式，布局覆盖tabBar顶部分割线
public enum ESTabBarItemPositioning : Int {
    
    case automatic
    
    case fill
    
    case centered
    
    case fillExcludeSeparator
    
    case fillIncludeSeparator
}



/// 对UITabBarDelegate进行扩展，以支持UITabBarControllerDelegate的相关方法桥接
internal protocol ESTabBarDelegate: NSObjectProtocol {

    /// 当前item是否支持选中
    ///
    /// - Parameters:
    ///   - tabBar: tabBar
    ///   - item: 当前item
    /// - Returns: Bool
    func tabBar(_ tabBar: UITabBar, shouldSelect item: UITabBarItem) -> Bool
    
    /// 当前item是否需要被劫持
    ///
    /// - Parameters:
    ///   - tabBar: tabBar
    ///   - item: 当前item
    /// - Returns: Bool
    func tabBar(_ tabBar: UITabBar, shouldHijack item: UITabBarItem) -> Bool
    
    /// 当前item的点击被劫持
    ///
    /// - Parameters:
    ///   - tabBar: tabBar
    ///   - item: 当前item
    /// - Returns: Void
    func tabBar(_ tabBar: UITabBar, didHijack item: UITabBarItem)
}



/// ESTabBar是高度自定义的UITabBar子类，通过添加UIControl的方式实现自定义tabBarItem的效果。目前支持tabBar的大部分属性的设置，例如delegate,items,selectedImge,itemPositioning,itemWidth,itemSpacing等，以后会更加细致的优化tabBar原有属性的设置效果。
open class ESTabBar: UITabBar {

    internal weak var customDelegate: ESTabBarDelegate? {
        didSet {
            // Update system button states when delegate changes
            DispatchQueue.main.async {
                self.updateSystemButtonStates()
            }
        }
    }
    
    /// Prevent multiple hijack calls during a single touch event
    private var lastHijackTime: TimeInterval = 0
    private var lastHijackedIndex: Int = -1
    
    /// Prevent multiple selection calls during a single touch event
    private var lastSelectionTime: TimeInterval = 0
    private var lastSelectedIndex: Int = -1
    
    /// set value > 0 to change tabbar height
    /// 设置 > 0 的值了来修改TabBar的高度
    public var tabBarHeight: CGFloat?{
        didSet{
            guard tabBarHeight ?? 0 > 0 else{
                return
            }
            setNeedsLayout()
        }
    }
    
    /// tabBar中items布局偏移量
    public var itemEdgeInsets = UIEdgeInsets.zero
    
    /// Custom item width. If 0, items will be distributed equally across available width
    public override var itemWidth: CGFloat {
        get { return _itemWidth }
        set {
            _itemWidth = newValue
            self.setNeedsLayout()
        }
    }
    private var _itemWidth: CGFloat = 0.0
    
    /// Spacing between items when using custom positioning
    public override var itemSpacing: CGFloat {
        get { return _itemSpacing }
        set {
            _itemSpacing = newValue
            self.setNeedsLayout()
        }
    }
    private var _itemSpacing: CGFloat = 0.0
    
    /// 是否设置为自定义布局方式，默认为空。如果为空，则通过itemPositioning属性来设置。如果不为空则忽略itemPositioning,所以当tabBar的itemCustomPositioning属性不为空时，如果想改变布局规则，请设置此属性而非itemPositioning。
    public var itemCustomPositioning: ESTabBarItemPositioning? {
        didSet {
            if let itemCustomPositioning = itemCustomPositioning {
                switch itemCustomPositioning {
                case .fill:
                    itemPositioning = .fill
                case .automatic:
                    itemPositioning = .automatic
                case .centered:
                    itemPositioning = .centered
                default:
                    break
                }
            }
            self.reload()
        }
    }
    /// tabBar自定义item的容器view
    internal var containers = [ESTabBarItemContainer]()
    /// 缓存当前tabBarController用来判断是否存在"More"Tab
    internal weak var tabBarController: UITabBarController?
    /// 自定义'More'按钮样式，继承自ESTabBarItemContentView
    open var moreContentView: ESTabBarItemContentView? = ESTabBarItemMoreContentView.init() {
        didSet { self.reload() }
    }
    
    open override var items: [UITabBarItem]? {
        didSet {
            self.reload()
        }
    }
    
    // Override touchesEnded to prevent system glass effect on ALL tabs
    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // GLOBAL glass effect prevention for ALL tabs - don't call super at all
        print("ESTabBar.touchesEnded: blocking all system processing to prevent glass effects")
        // Completely block system processing - no super call
    }
    
    // Override touchesCancelled to prevent system glass effect on ALL tabs
    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // GLOBAL glass effect prevention for ALL tabs - don't call super at all
        print("ESTabBar.touchesCancelled: blocking all system processing to prevent glass effects")
        // Completely block system processing - no super call
    }
    
    // Override hitTest to prevent system from detecting touches on ALL tabs
    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Check if touch is on ANY tab container
        for (index, container) in containers.enumerated() {
            if container.frame.contains(point) {
                if let item = items?[index],
                   let customDelegate = customDelegate {
                    
                    // Check if it's a hijacked tab
                    if customDelegate.tabBar(self, shouldHijack: item) {
                        let currentTime = Date.timeIntervalSinceReferenceDate
                        
                        // Prevent multiple calls within 0.5 seconds for the same tab
                        if currentTime - lastHijackTime < 0.5 && lastHijackedIndex == index {
                            print("ESTabBar.hitTest: HIJACKED tab \(index) hit - debouncing multiple calls")
                            return nil
                        }
                        
                        print("ESTabBar.hitTest: HIJACKED tab \(index) hit - returning nil and triggering hijack")
                        
                        lastHijackTime = currentTime
                        lastHijackedIndex = index
                        
                        // Trigger the hijack handler
                        DispatchQueue.main.async {
                            print("ESTabBar.hitTest: calling didHijack for tab \(index) from hitTest")
                            customDelegate.tabBar(self, didHijack: item)
                        }
                        
                        return nil
                    } else {
                        // For non-hijacked tabs, also return nil but trigger selection manually
                        let currentTime = Date.timeIntervalSinceReferenceDate
                        
                        // Prevent multiple calls within 0.5 seconds for the same tab
                        if currentTime - lastSelectionTime < 0.5 && lastSelectedIndex == index {
                            print("ESTabBar.hitTest: NON-HIJACKED tab \(index) hit - debouncing multiple calls")
                            return nil
                        }
                        
                        print("ESTabBar.hitTest: NON-HIJACKED tab \(index) hit - returning nil and triggering manual selection")
                        
                        lastSelectionTime = currentTime
                        lastSelectedIndex = index
                        
                        DispatchQueue.main.async {
                            print("ESTabBar.hitTest: manually selecting tab \(index)")
                            // Use the proper select method to handle visual updates
                            self.select(itemAtIndex: index, animated: false)
                            
                            // Also trigger the delegate call for view controller switching
                            if let customDelegate = self.customDelegate,
                               customDelegate.tabBar(self, shouldSelect: item) {
                                print("ESTabBar.hitTest: triggering delegate for view controller switch")
                                self.delegate?.tabBar?(self, didSelect: item)
                            }
                        }
                        
                        return nil
                    }
                }
                break
            }
        }
        
        // For areas outside containers, allow minimal system processing
        return super.hitTest(point, with: event)
    }
    
    // Override selection indicator methods to prevent glass effect
    open override var selectionIndicatorImage: UIImage? {
        get { return nil }
        set { /* ignore */ }
    }
    
    // Disable system animations completely but allow content view updates
    open override func setNeedsDisplay() {
        // Allow display updates for content views but disable system glass effects
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setNeedsDisplay()
        CATransaction.commit()
    }
    
    // Override layout methods to prevent glass effect animations
    open override func setNeedsLayout() {
        // Only allow layout for non-animation scenarios
        super.setNeedsLayout()
    }
    
    open override func layoutIfNeeded() {
        // Disable animations during layout
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        super.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsEnabled)
    }
    
    // Override CALayer actions to prevent glass effect animations for ALL tabs
    public override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        // Block ALL layer animations that could create glass effects on any tab
        if event == "position" || event == "opacity" || event == "transform" || 
           event == "bounds" || event == "frame" || event == "backgroundColor" ||
           event == "shadowOpacity" || event == "shadowOffset" || event == "shadowRadius" {
            return NSNull()
        }
        return super.action(for: layer, forKey: event)
    }
    
    // Override ALL touch methods to disable glass effects globally
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Since hitTest returns nil for all tab touches, this should rarely be called
        // Block any remaining system processing
        print("ESTabBar.touchesBegan: blocking any remaining system touch processing")
        // Don't call super to prevent any glass effects
    }
    
    // Store the original delegate
    private weak var originalDelegate: UITabBarDelegate?
    
    open override var delegate: UITabBarDelegate? {
        get {
            return originalDelegate
        }
        set {
            originalDelegate = newValue
            // Don't intercept delegate calls - let the system handle them normally
            // We prevent hijacked tabs at the hitTest level instead
            super.delegate = newValue
        }
    }
    
    open var isEditing: Bool = false {
        didSet {
            if oldValue != isEditing {
                self.updateLayout()
            }
        }
    }
    
    open override func setItems(_ items: [UITabBarItem]?, animated: Bool) {
        super.setItems(items, animated: animated)
        self.reload()
    }
    
    open override func beginCustomizingItems(_ items: [UITabBarItem]) {
        ESTabBarController.printError("beginCustomizingItems(_:) is unsupported in ESTabBar.")
        super.beginCustomizingItems(items)
    }
    
    open override func endCustomizing(animated: Bool) -> Bool {
        ESTabBarController.printError("endCustomizing(_:) is unsupported in ESTabBar.")
        return super.endCustomizing(animated: animated)
    }
    
    open override func layoutSubviews() {
        print("ESTabBar.layoutSubviews: Starting with bounds: \(bounds)")
        
        // Completely disable animations during layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        super.layoutSubviews()
        
        print("ESTabBar.layoutSubviews: After super.layoutSubviews(), bounds: \(bounds)")
        
        self.updateLayout()
        
        CATransaction.commit()
        
        // Ensure system buttons remain hidden after layout
        DispatchQueue.main.async {
            self.ensureSystemButtonsHidden()
        }
    }
    
    // Call this method whenever items change to ensure hijacked tabs are properly handled
    private func updateSystemButtonStates() {
        print("ESTabBar.updateSystemButtonStates: called")
        ensureSystemButtonsHidden()
        
        // Also update container interactions for hijacked tabs
        for (index, container) in containers.enumerated() {
            if index < items?.count ?? 0,
               let item = items?[index],
               let customDelegate = customDelegate,
               customDelegate.tabBar(self, shouldHijack: item) {
                container.isUserInteractionEnabled = false
                
                // Disable animations on content views for hijacked tabs
                if let esItem = item as? ESTabBarItem {
                    esItem.contentView.layer.allowsGroupOpacity = false
                    esItem.contentView.layer.shouldRasterize = false
                    UIView.setAnimationsEnabled(false)
                    esItem.contentView.isUserInteractionEnabled = false
                    UIView.setAnimationsEnabled(true)
                }
                
                print("ESTabBar.updateSystemButtonStates: disabled container interaction for hijacked tab \(index)")
            } else if index < items?.count ?? 0,
                      let item = items?[index] {
                container.isUserInteractionEnabled = true
                
                // Re-enable for non-hijacked tabs
                if let esItem = item as? ESTabBarItem {
                    esItem.contentView.isUserInteractionEnabled = true
                }
            }
        }
    }
    
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let defaultSize = super.sizeThatFits(size)
        if let tabBarHeight, tabBarHeight > 0{
            return CGSize(width: defaultSize.width, height: tabBarHeight)
        }
        return defaultSize
    }
    
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var b = super.point(inside: point, with: event)
        if !b {
            for container in containers {
                if container.point(inside: CGPoint.init(x: point.x - container.frame.origin.x, y: point.y - container.frame.origin.y), with: event) {
                    b = true
                }
            }
        }
        return b
    }
    
    private func ensureSystemButtonsHidden() {
        guard let tabBarItems = self.items else { return }
        
        let tabBarButtons = subviews.filter { subview -> Bool in
            if let cls = NSClassFromString("UITabBarButton") {
                return subview.isKind(of: cls)
            }
            return false
        }
        
        // Completely hide and disable system buttons for hijacked tabs
        for (index, button) in tabBarButtons.enumerated() {
            if index < tabBarItems.count {
                let item = tabBarItems[index]
                if let customDelegate = customDelegate,
                   customDelegate.tabBar(self, shouldHijack: item) {
                    // For hijacked tabs, completely remove the button from the view hierarchy
                    button.isHidden = true
                    button.isUserInteractionEnabled = false
                    button.alpha = 0.0
                    button.removeFromSuperview() // Completely remove it
                    print("ESTabBar.ensureSystemButtonsHidden: REMOVED system button for hijacked tab \(index)")
                } else {
                    // For non-hijacked tabs, ensure button is hidden but present (ESTabBar uses custom containers)
                    button.isHidden = true
                    button.isUserInteractionEnabled = false
                    button.alpha = 0.0
                }
            } else {
                button.isHidden = true
                button.removeFromSuperview()
            }
        }
    }

}

internal extension ESTabBar /* Layout */ {    func updateLayout() {
        guard let tabBarItems = self.items else {
            ESTabBarController.printError("empty items")
            return
        }
        
        print("ESTabBar.updateLayout: Starting layout with bounds: \(bounds), itemCount: \(tabBarItems.count)")
        
        let tabBarButtons = subviews.filter { subview -> Bool in
            if let cls = NSClassFromString("UITabBarButton") {
                return subview.isKind(of: cls)
            }
            return false
            } .sorted { (subview1, subview2) -> Bool in
                return subview1.frame.origin.x < subview2.frame.origin.x
        }
        
        print("ESTabBar.updateLayout: Found \(tabBarButtons.count) tabBarButtons")
        for (idx, button) in tabBarButtons.enumerated() {
            print("ESTabBar.updateLayout: TabBarButton \(idx) frame: \(button.frame)")
        }
        
        if isCustomizing {
            for (idx, _) in tabBarItems.enumerated() {
                if idx < tabBarButtons.count {
                    tabBarButtons[idx].isHidden = false
                }
                moreContentView?.isHidden = true
            }
            for (_, container) in containers.enumerated(){
                container.isHidden = true
            }
        } else {
            // Always hide all system tab bar buttons when using custom containers
            for button in tabBarButtons {
                button.isHidden = true
            }
            
            // Show our custom containers
            for (_, container) in containers.enumerated(){
                container.isHidden = false
            }
        }
        
        var layoutBaseSystem = true
        if let itemCustomPositioning = itemCustomPositioning {
            switch itemCustomPositioning {
            case .fill, .automatic, .centered:
                break
            case .fillIncludeSeparator, .fillExcludeSeparator:
                layoutBaseSystem = false
            }
        }
        
        if layoutBaseSystem {
            // System itemPositioning
            print("ESTabBar.updateLayout: Using system layout base")
            for (idx, container) in containers.enumerated(){
                if idx < tabBarButtons.count && !tabBarButtons[idx].frame.isEmpty {
                    container.frame = tabBarButtons[idx].frame
                    print("ESTabBar.updateLayout: Set container \(idx) frame from tabBarButton: \(container.frame)")
                } else {
                    // Fallback: if no valid tabBarButton frame, distribute equally
                    guard containers.count > 0 else { continue }
                    let containerWidth = bounds.width / CGFloat(containers.count)
                    let containerHeight = bounds.height
                    container.frame = CGRect(x: CGFloat(idx) * containerWidth, y: 0, width: containerWidth, height: containerHeight)
                    print("ESTabBar.updateLayout: Set container \(idx) frame with fallback: \(container.frame)")
                }
            }
        } else {
            // Custom itemPositioning
            print("ESTabBar.updateLayout: Using custom layout")
            guard bounds.size.width > 0 && bounds.size.height > 0 && containers.count > 0 else {
                print("ESTabBar.updateLayout: Invalid bounds or no containers - bounds: \(bounds), containers: \(containers.count)")
                return
            }
            
            var x: CGFloat = itemEdgeInsets.left
            var y: CGFloat = itemEdgeInsets.top
            switch itemCustomPositioning! {
            case .fillExcludeSeparator:
                if y <= 0.0 {
                    y += 1.0
                }
            default:
                break
            }
            let width = bounds.size.width - itemEdgeInsets.left - itemEdgeInsets.right
            let height = bounds.size.height - y - itemEdgeInsets.bottom
            let eachWidth = _itemWidth == 0.0 ? width / CGFloat(containers.count) : _itemWidth
            let eachSpacing = _itemSpacing == 0.0 ? 0.0 : _itemSpacing
            
            print("ESTabBar.updateLayout: Custom layout - eachWidth: \(eachWidth), height: \(height)")
            
            for (idx, container) in containers.enumerated() {
                container.frame = CGRect.init(x: x, y: y, width: eachWidth, height: height)
                print("ESTabBar.updateLayout: Set container \(idx) frame with custom: \(container.frame)")
                x += eachWidth
                x += eachSpacing
            }
        }
    }
}

internal extension ESTabBar /* Actions */ {
    
    func isMoreItem(_ index: Int) -> Bool {
        return ESTabBarController.isShowingMore(tabBarController) && (index == (items?.count ?? 0) - 1)
    }
    
    func restoreSelectionAfterHijack(currentIndex: Int, animated: Bool) {
        // Restore the visual selection to the previously selected tab
        if currentIndex != -1 && currentIndex < items?.count ?? 0 {
            if let currentItem = items?[currentIndex] as? ESTabBarItem {
                currentItem.contentView.select(animated: animated, completion: nil)
            } else if self.isMoreItem(currentIndex) {
                moreContentView?.select(animated: animated, completion: nil)
            }
        }
    }
    
    func removeAll() {
        for container in containers {
            container.removeFromSuperview()
        }
        containers.removeAll()
    }
    
    func reload() {
        removeAll()
        guard let tabBarItems = self.items else {
            ESTabBarController.printError("empty items")
            return
        }
        
        print("ESTabBar.reload: Loading \(tabBarItems.count) items")
        
        for (idx, item) in tabBarItems.enumerated() {
            let container = ESTabBarItemContainer.init(self, tag: 1000 + idx)
            self.addSubview(container)
            self.containers.append(container)
            
            print("ESTabBar.reload: Added container \(idx) with frame: \(container.frame)")
            
            // Disable user interaction for hijacked tabs to prevent any visual feedback
            if let customDelegate = customDelegate,
               customDelegate.tabBar(self, shouldHijack: item) {
                container.isUserInteractionEnabled = false
                print("ESTabBar.reload: disabled interaction for hijacked container \(idx)")
            } else {
                container.isUserInteractionEnabled = true
            }
            
            if let item = item as? ESTabBarItem {
                container.addSubview(item.contentView)
                print("ESTabBar.reload: Added ESTabBarItem content view for item \(idx)")
            } else {
                print("ESTabBar.reload: Using system UITabBarItem for item \(idx)")
            }
            
            if self.isMoreItem(idx), let moreContentView = moreContentView {
                container.addSubview(moreContentView)
            }
        }
        
        print("ESTabBar.reload: Total containers created: \(containers.count)")
        self.updateAccessibilityLabels()
        self.setNeedsLayout()
        // Force layout update to ensure proper visibility
        DispatchQueue.main.async {
            self.updateLayout()
            // Update system button states after layout to handle hijacked tabs
            self.updateSystemButtonStates()
        }
    }
    
    @objc func highlightAction(_ sender: AnyObject?) {
        guard let container = sender as? ESTabBarItemContainer else {
            return
        }
        let newIndex = max(0, container.tag - 1000)
        guard newIndex < items?.count ?? 0, let item = self.items?[newIndex], item.isEnabled == true else {
            return
        }
        
        if (customDelegate?.tabBar(self, shouldSelect: item) ?? true) == false {
            return
        }
        
        if let item = item as? ESTabBarItem {
            item.contentView.highlight(animated: true, completion: nil)
        } else if self.isMoreItem(newIndex) {
            moreContentView?.highlight(animated: true, completion: nil)
        }
    }
    
    @objc func dehighlightAction(_ sender: AnyObject?) {
        guard let container = sender as? ESTabBarItemContainer else {
            return
        }
        let newIndex = max(0, container.tag - 1000)
        guard newIndex < items?.count ?? 0, let item = self.items?[newIndex], item.isEnabled == true else {
            return
        }
        
        if (customDelegate?.tabBar(self, shouldSelect: item) ?? true) == false {
            return
        }
        
        if let item = item as? ESTabBarItem {
            item.contentView.dehighlight(animated: true, completion: nil)
        } else if self.isMoreItem(newIndex) {
            moreContentView?.dehighlight(animated: true, completion: nil)
        }
    }
    
    @objc func selectAction(_ sender: AnyObject?) {
        guard let container = sender as? ESTabBarItemContainer else {
            return
        }
        
        let index = container.tag - 1000
        guard index >= 0 && index < items?.count ?? 0, let item = items?[index] else {
            return
        }
        
        print("ESTabBar.selectAction: index=\(index)")
        
        // Check if this is a hijacked tab
        if let customDelegate = customDelegate,
           customDelegate.tabBar(self, shouldHijack: item) {
            print("ESTabBar.selectAction: HIJACKED tab - calling didHijack directly")
            // For hijacked tabs, call the hijack handler directly
            customDelegate.tabBar(self, didHijack: item)
            return
        }
        
        print("ESTabBar.selectAction: NON-HIJACKED tab - skipping to prevent crash")
        // For non-hijacked tabs, don't call our custom select method
        // Let the system UITabBar handle the selection through normal mechanisms
        // This prevents "Directly modifying a tab bar managed by a tab bar controller is not allowed" crash
    }
    
    @objc func select(itemAtIndex idx: Int, animated: Bool) {
        let newIndex = max(0, idx)
        let currentIndex = (selectedItem != nil) ? (items?.firstIndex(of: selectedItem!) ?? -1) : -1
        guard newIndex < items?.count ?? 0, let item = self.items?[newIndex], item.isEnabled == true else {
            return
        }
        
        print("ESTabBar.select: index=\(newIndex), current=\(currentIndex)")
        
        // Check if this tab should be hijacked first
        if (customDelegate?.tabBar(self, shouldHijack: item) ?? false) == true {
            print("ESTabBar.select: HIJACKED - blocking selection")
            // Hijacked tabs are treated as modal actions - no selection state change
            // Prevent any system glass/slide effects by not touching selectedItem at all
            
            if animated {
                if let item = item as? ESTabBarItem {
                    item.contentView.select(animated: animated, completion: { [weak self] in
                        item.contentView.deselect(animated: false, completion: nil)
                        // Don't restore selection - this prevents glass effect
                        // Call didHijack after animation completes with a small delay for modal presentation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self?.customDelegate?.tabBar(self!, didHijack: item)
                        }
                    })
                } else if self.isMoreItem(newIndex) {
                    moreContentView?.select(animated: animated, completion: { [weak self] in
                        self?.moreContentView?.deselect(animated: false, completion: nil)
                        // Don't restore selection - this prevents glass effect
                        // Call didHijack after animation completes with a small delay for modal presentation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self?.customDelegate?.tabBar(self!, didHijack: item)
                        }
                    })
                }
            } else {
                // If not animated, call didHijack with a small delay for modal presentation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.customDelegate?.tabBar(self, didHijack: item)
                }
            }
            // Early return for hijacked tabs - skip delegate call and selectedIndex change
            print("ESTabBar.select: HIJACKED - early return, no delegate call")
            self.updateAccessibilityLabels()
            return
        }
        
        print("ESTabBar.select: NON-HIJACKED - proceeding with selection")
        // For non-hijacked tabs, check if selection should proceed
        if (customDelegate?.tabBar(self, shouldSelect: item) ?? true) == false {
            return
        }
        
        if currentIndex != newIndex {
            if currentIndex != -1 && currentIndex < items?.count ?? 0{
                if let currentItem = items?[currentIndex] as? ESTabBarItem {
                    currentItem.contentView.deselect(animated: animated, completion: nil)
                } else if self.isMoreItem(currentIndex) {
                    moreContentView?.deselect(animated: animated, completion: nil)
                }
            }
            if let item = item as? ESTabBarItem {
                item.contentView.select(animated: animated, completion: nil)
            } else if self.isMoreItem(newIndex) {
                moreContentView?.select(animated: animated, completion: nil)
            }
        } else if currentIndex == newIndex {
            if let item = item as? ESTabBarItem {
                item.contentView.reselect(animated: animated, completion: nil)
            } else if self.isMoreItem(newIndex) {
                moreContentView?.reselect(animated: animated, completion: nil)
            }
            
            if let tabBarController = tabBarController {
                var navVC: UINavigationController?
                if let n = tabBarController.selectedViewController as? UINavigationController {
                    navVC = n
                } else if let n = tabBarController.selectedViewController?.navigationController {
                    navVC = n
                }
                
                if let navVC = navVC {
                    if navVC.viewControllers.contains(tabBarController) {
                        if navVC.viewControllers.count > 1 && navVC.viewControllers.last != tabBarController {
                            navVC.popToViewController(tabBarController, animated: true);
                        }
                    } else {
                        if navVC.viewControllers.count > 1 {
                            navVC.popToRootViewController(animated: animated)
                        }
                    }
                }
            
            }
        }
        
        // Only notify delegate for non-hijacked tabs - double check before calling
        if let customDelegate = customDelegate,
           customDelegate.tabBar(self, shouldHijack: item) {
            print("ESTabBar: BLOCKING delegate call for hijacked item")
            // Don't call delegate for hijacked tabs
        } else {
            print("ESTabBar: NON-HIJACKED tab - skipping delegate call to prevent crash")
            // Skip delegate call to prevent "Directly modifying a tab bar managed by a tab bar controller is not allowed" crash
            // The tab bar controller will handle the selection through normal UITabBar mechanisms
        }
        self.updateAccessibilityLabels()
    }
    
    func updateAccessibilityLabels() {
        guard let tabBarItems = self.items, tabBarItems.count == self.containers.count else {
            return
        }
        
        for (idx, item) in tabBarItems.enumerated() {
            let container = self.containers[idx]
            container.accessibilityIdentifier = item.accessibilityIdentifier
            container.accessibilityTraits = item.accessibilityTraits
            
            if item == selectedItem {
                container.accessibilityTraits = container.accessibilityTraits.union(.selected)
            }
            
            if let explicitLabel = item.accessibilityLabel {
                container.accessibilityLabel = explicitLabel
                container.accessibilityHint = item.accessibilityHint ?? container.accessibilityHint
            } else {
                var accessibilityTitle = ""
                if let item = item as? ESTabBarItem {
                    accessibilityTitle = item.accessibilityLabel ?? item.title ?? ""
                }
                if self.isMoreItem(idx) {
                    accessibilityTitle = NSLocalizedString("More_TabBarItem", bundle: Bundle(for:ESTabBarController.self), comment: "")
                }
                
                let formatString = NSLocalizedString(item == selectedItem ? "TabBarItem_Selected_AccessibilityLabel" : "TabBarItem_AccessibilityLabel",
                                                     bundle: Bundle(for: ESTabBarController.self),
                                                     comment: "")
                container.accessibilityLabel = String(format: formatString, accessibilityTitle, idx + 1, tabBarItems.count)
            }
            
        }
    }
}
