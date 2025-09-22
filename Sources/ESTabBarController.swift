//  SearchResultViewController.swift
//  Rentr
//
//  Created by bon.ryan.m.benaojan on 3/19/25.
//

import UIKit
import EmptyDataSet_Swift
import LGButton
import ESPullToRefresh
import SwiftyJSON
import SwiftIconFont
import CurrencyText
import AwesomeEnum
import AACarousel
import ImageSlideshow
import Nantes
import SwiftyAttributes
import RxSwift
import RxCocoa
import RxAppState
import SPPermissions
import Pulsator
import ESTabBarController_swift


class SearchResultViewController: UIViewController, UISearchBarDelegate, SPPermissionsDelegate, UITabBarControllerDelegate {
    
    // MARK: - ViewModel integration
    private lazy var propertyListViewModel: PropertyListViewModel = {
        let vm = CompositionRoot.makePropertyListViewModel()
        
        vm.onDataUpdated = { [weak self] in
            guard let self = self else { return }
            
            // Nuclear option: ignore all callbacks during pull refresh
            if self.ignoreViewModelCallbacks {
                print("🚫 IGNORING onDataUpdated - callbacks disabled during pull refresh")
                return
            }
            
            self.isLoading = false
            self.emptyData = self.propertyListViewModel.isEmpty
            
            // PRIORITY 1: Skip pulse for load more operations
            if self.isLoadingMore {
                print("⏭️ SKIPPING PULSE - this is a load more operation")
                // Ensure table is visible and interactive for load more
                self.pulseCompletionGate = false
                self.view.isUserInteractionEnabled = true
                self.tableView.isHidden = false
                self.tableView.alpha = 1
                self.tableView.reloadData()
                self.tableView.reloadEmptyDataSet()
                self.tableView.es.stopPullToRefresh()
                self.isLoadingMore = false // Reset the flag after handling load more
                // Ensure loading is hidden for load more operations
                Utils.hideLoading()
                return
            }
            
            // PRIORITY 2: Skip pulse for pull refresh operations - ABSOLUTE BLOCK
            if self.isPullRefresh || self.pullRefreshInProgress {
                print("⏭️ ABSOLUTE BLOCK - this is a pull refresh operation (isPullRefresh: \(self.isPullRefresh), pullRefreshInProgress: \(self.pullRefreshInProgress))")
                // FORCE stop any pulse that might be running
                if self.isPulseActive {
                    self.pulsator.stop()
                    self.pulsator.removeFromSuperlayer()
                    self.avatarView.removeFromSuperview()
                    self.pulseWindow?.isHidden = true
                    self.pulseWindow = nil
                    self.pulseShownAt = nil
                    self.isPulseActive = false
                    self.revealScheduled = false
                }
                // Ensure table is visible and interactive for pull refresh
                self.pulseCompletionGate = false
                self.view.isUserInteractionEnabled = true
                self.tableView.isHidden = false
                self.tableView.alpha = 1
                self.tableView.reloadData()
                self.tableView.reloadEmptyDataSet()
                self.tableView.es.stopPullToRefresh()
                // Reset both flags only here after everything is complete
                self.isPullRefresh = false
                self.pullRefreshInProgress = false
                return
            }
            
            print("📊 DATA UPDATED - starting pulse sequence")
            // Start the pulse sequence for initial loading only
            self.startPulseSequence {
                print("✅ REVEALING TABLE DATA")
                self.view.isUserInteractionEnabled = true
                self.tableView.isHidden = false
                self.tableView.alpha = 1
                self.tableView.reloadData()
                self.tableView.reloadEmptyDataSet()
                self.tableView.es.stopPullToRefresh()
                
                // Hide loading overlay after data is revealed with small delay
                Utils.delay(interval: 0.1) {
                    Utils.hideLoading()
                }
            }
        }
        
        vm.onError = { [weak self] _ in
            guard let self = self else { return }
            print("❌ ERROR OCCURRED - starting pulse sequence")
            self.isLoading = false
            self.emptyData = self.propertyListViewModel.isEmpty || self.isExplicitSearch
            self.startPulseSequence {
                print("✅ REVEALING ERROR/EMPTY STATE")
                self.view.isUserInteractionEnabled = true
                self.tableView.isHidden = false
                self.tableView.alpha = 1
                self.tableView.reloadEmptyDataSet()
                
                // Hide loading overlay after error/empty state is revealed with small delay
                Utils.delay(interval: 0.1) {
                    Utils.hideLoading()
                }
            }
        }
        
        vm.onReloadMoreData = { [weak self] startIndex in
            guard let self = self else { return }
            self.isLoadingMore = true // Mark as load more operation
            self.reloadMoreData(startIndex)
            self.tableView.es.stopLoadingMore()
            // Don't reset isLoadingMore here - let onDataUpdated handle it
        }
        
        vm.onNoMoreData = { [weak self] in
            self?.tableView.es.noticeNoMoreData()
        }
        
        vm.onShowLoading = { [weak self] in
            guard let self = self else { return }
            
            // Nuclear option: ignore all callbacks during pull refresh
            if self.ignoreViewModelCallbacks {
                print("🚫 IGNORING onShowLoading - callbacks disabled during pull refresh")
                return
            }
            
            // ABSOLUTE BLOCK for pull refresh - don't even set loading states
            if self.isPullRefresh || self.pullRefreshInProgress {
                print("⏭️ ABSOLUTE BLOCK onShowLoading - this is a pull refresh operation (isPullRefresh: \(self.isPullRefresh), pullRefreshInProgress: \(self.pullRefreshInProgress))")
                return
            }
            
            // ABSOLUTE BLOCK for load more - don't even set loading states  
            if self.isLoadingMore {
                print("⏭️ ABSOLUTE BLOCK onShowLoading - this is a load more operation")
                return
            }
            
            print("🔄 onShowLoading - setting up pulse for initial loading")
            self.isLoading = true
            self.emptyData = false
            
            // IMMEDIATELY block all content and start pulse for initial loading only
            self.pulseCompletionGate = true
            self.view.isUserInteractionEnabled = false
            self.tableView.alpha = 0
            self.tableView.isHidden = true
            self.tableView.reloadEmptyDataSet()
            // Show global overlay first, then overlay pulse on top in the next runloop
           // Utils.showLoading(gradient: .gradient)
            DispatchQueue.main.async {
                self.showPulse()
            }
        }
        
    vm.onHideLoading = { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.tableView.reloadEmptyDataSet()
            Utils.hideLoading()
        }
        
        return vm
    }()
    
    
    private let pulsator = Pulsator()
    private var customPulseLayers: [CAShapeLayer] = []
    private var pulseWindow: UIWindow?
    private var pulseShownAt: Date?
    private var isPulseActive: Bool = false
    private var revealScheduled: Bool = false
    private var pulseCompletionGate: Bool = false // Blocks all data rendering until pulse finishes
    private var isLoadingMore: Bool = false // Track if this is a "load more" operation
    private var isPullRefresh: Bool = false // Track if this is a "pull to refresh" operation
    private var pullRefreshInProgress: Bool = false // Persistent flag that doesn't get reset until completion
    private var ignoreViewModelCallbacks: Bool = false // Nuclear option to ignore all ViewModel callbacks
    private var pulseStartTime: Date?
    private var pulseEndTime: Date?
    private class PulseHostViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }
    }
    private let avatarView: UIImageView = {
        let imageView = UIImageView(image: AwesomePro.Solid.houseBuilding.asImage(size: 80, color: AssetTheme.buttonColor.color))
        imageView.contentMode = .scaleAspectFill
        imageView.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        return imageView
    }()
    
    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.delegate = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = "Search property..."
        sc.searchBar.autocapitalizationType = .words
        sc.searchBar.sizeToFit()
        sc.searchBar.delegate = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.searchTextField.leftView?.tintColor = AssetTheme.mainWhite.color
        sc.searchBar.searchTextField.textColor = AssetTheme.mainWhite.color
        sc.searchBar.searchTextField.tintColor = AssetTheme.mainWhite.color
        sc.searchBar.searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Search property...",
            attributes: [.foregroundColor: AssetTheme.mainWhite.color]
        )
        return sc
    }()
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var emptyImageView: UIImageView!
    @IBOutlet weak var emptyLabel: UILabel!
    @IBOutlet weak var emptyAddPropertyButton: LGButton!
    @IBOutlet var emptyDataView: UIView!
    
    var titleArray = [String]()
    var pathArray: [InputSource]!
    
    var emptyData: Bool = false
    var fromStart: Bool = false
    var showSearchBar: Bool = false
    
    var location = LocationManager()
    
    private var isLoading = false
    private var isExplicitSearch = false
    private var lastIssuedQuery: String = ""
    private var lastNonEmptySearch: String = ""
    
    // Receives search text from SearchPropertyViewController
    var searchQuery: String?
    
    let application = UIApplication.shared
    let disposeBag = DisposeBag()
    
    // Track one-time delegate setup
    private var didSetTabBarDelegate = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.emptyDataSetSource = self
        tableView.emptyDataSetDelegate = self
        self.configureUI()
        self.pullRefresh()
        
        // Set up tab bar delegate to detect same tab taps
      //  self.setupTabBarDelegate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Ensure any stuck loading states are cleared when returning to the page
        Utils.hideLoading()
        
        // Clean up any stuck pulse states
        if isPulseActive {
            pulsator.stop()
            pulsator.removeFromSuperlayer()
            avatarView.removeFromSuperview()
            pulseWindow?.isHidden = true
            pulseWindow = nil
            pulseShownAt = nil
            isPulseActive = false
            revealScheduled = false
        }
        
        if showSearchBar ==  true {
            self.showSearchNav()
        } else {
            self.showHomeNav()
        }
        self.navigationItem.hidesSearchBarWhenScrolling = false
        // FORCE hide content and block interactions until pulse completes
        self.pulseCompletionGate = true
        self.view.isUserInteractionEnabled = false
        self.tableView.alpha = 0
        self.tableView.isHidden = true
        
        if let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            // Enter search mode
            lastNonEmptySearch = query
            isExplicitSearch = true
            lastIssuedQuery = query
            isLoading = true
            emptyData = false
            tableView.reloadEmptyDataSet()
            
            propertyListViewModel.clearList()
            tableView.reloadData()
            
            searchController.searchBar.text = query
            searchController.isActive = true
            performSearch(with: query)
        } else {
            // Browse mode: empty search shows all
            isExplicitSearch = false
            isLoading = true
            emptyData = false
            tableView.reloadEmptyDataSet()
            self.isPullRefresh = false // Ensure pulse shows for initial loading
            self.refresh()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Immediate cleanup in case Utils.hideLoading() was missed
        Utils.hideLoading()
        // Additional delayed cleanup as backup
        Utils.delay(interval: 1) { Utils.hideLoading() }
        
        // Ensure ESTabBarController delegate is set when we’re visible in the tab hierarchy
        if !didSetTabBarDelegate {
            setupTabBarDelegate()
            didSetTabBarDelegate = true
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // CRITICAL: Stop pulse and hide loading when navigating away
        print("🔄 viewWillDisappear - cleaning up pulse and loading")
        
        // Force stop any active pulse
        if isPulseActive {
            print("🛑 FORCE STOPPING PULSE during navigation")
            pulsator.stop()
            pulsator.removeFromSuperlayer()
            avatarView.removeFromSuperview()
            pulseWindow?.isHidden = true
            pulseWindow = nil
            pulseShownAt = nil
            isPulseActive = false
            revealScheduled = false
        }
        
        // Force hide any loading overlay
        Utils.hideLoading()
        
        // Reset all blocking states
        pulseCompletionGate = false
        view.isUserInteractionEnabled = true
        tableView.isHidden = false
        tableView.alpha = 1
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.layoutIfNeeded()
    }
    
    func configureUI() {
        
        
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationController?.hidesBarsOnSwipe = true
        
        Navigation.hideBackTitleButton(controller: self)
        
        self.tableView.separatorInset = .zero
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.separatorStyle = .none
        
        self.emptyImageView.image = AwesomePro.Solid.houseBuilding.asImage(size: 200, color: AssetTheme.accentColor.color)
        self.emptyLabel.text = "Empty Properties"
        self.emptyLabel.font = Fonts.sfProTextBold(size: 20)
        self.emptyLabel.textColor = AssetTheme.mainBlack.color
        
        let nextImg = AwesomePro.Solid.rotateReverse.asImage(size: 25, color: AssetTheme.mainWhite.color)
        self.emptyAddPropertyButton.rightImageSrc = nextImg
        self.emptyAddPropertyButton.bgColor = AssetTheme.buttonColor.color
        self.emptyAddPropertyButton.rightImageColor = AssetTheme.mainWhite.color
        self.emptyAddPropertyButton.cornerRadius = 25
        self.emptyAddPropertyButton.titleString = "Refresh"
        self.emptyAddPropertyButton.leftImageWidth = 30
        self.emptyAddPropertyButton.leftImageHeight = 30
        self.emptyAddPropertyButton.fullyRoundedCorners = true
        self.emptyAddPropertyButton.spacingLeading = 12
        self.emptyAddPropertyButton.spacingTitleIcon = -30
        self.emptyAddPropertyButton.titleFontSize = 17
        self.emptyAddPropertyButton.borderWidth = 1
        self.emptyAddPropertyButton.shadowRadius = 0
        self.emptyAddPropertyButton.shadowOffset = CGSize(width: 2, height: 2)
        self.emptyAddPropertyButton.isLoading = false
        self.emptyAddPropertyButton.loadingString = "loading..."
        self.emptyAddPropertyButton.loadingColor = AssetTheme.mainWhite.color
        self.emptyAddPropertyButton.loadingSpinnerColor = AssetTheme.mainWhite.color
        self.emptyAddPropertyButton.loadingFontSize = 17
        self.emptyAddPropertyButton.leftImageColor = AssetTheme.mainWhite.color
        self.emptyAddPropertyButton.titleColor = AssetTheme.mainWhite.color
        self.emptyAddPropertyButton.addTarget(self, action: #selector(refeshData), for: .touchUpInside)
        
        //self.emptyAddPropertyButton.addTarget(self, action: #selector(startReviewButtonAction), for: .touchUpInside)
        
        self.searchController.searchBar.resignFirstResponder()
    }

    // Ensure pulse loader covers content before any data fetch begins
    private func beginPulseLoadingIfNeeded() {
        // Skip pulse for load more or pull refresh operations
        if isLoadingMore || isPullRefresh || pullRefreshInProgress {
            print("⏭️ SKIPPING beginPulseLoadingIfNeeded - isLoadingMore: \(isLoadingMore), isPullRefresh: \(isPullRefresh), pullRefreshInProgress: \(pullRefreshInProgress)")
            return
        }
        
        // FORCE hide content and block interactions while pulse is active
        self.pulseCompletionGate = true
        self.view.isUserInteractionEnabled = false
        self.tableView.alpha = 0
        self.tableView.isHidden = true
        // Block any accidental reloads
        self.tableView.reloadData() // Clear any existing data
        self.showPulse()
    }
    
    @IBAction func filterAction(_ sender: Any) {
        self.performSegue(withIdentifier: Segues.toSearchFilterSegue.rawValue, sender: nil)
    }

    
    
    func showSearchNav() {
        
        self.navigationItem.searchController = searchController
        self.title = "Properties"
        
        if fromStart == true {
            let xmark = AwesomePro.Light.xmarkLarge.asImage(size: 25, color: AssetTheme.mainWhite.color)
            Navigation().setLeftButton(image: xmark, title: "", target: self, action: #selector(dismissAction(_:)), controller: self, size: CGRect(x: 0, y: 0, width: 30, height: 30))
        }
        
        let filterImage = AwesomePro.Solid.sliders.asImage(size: 30, color: AssetTheme.mainWhite.color)
        Navigation().setRightButton(image: filterImage, title: "", target: self, action: #selector(filterAction(_:)), controller: self)
    }
    
    func showHomeNav() {
    
    application.rx.didOpenApp
        .subscribe(onNext: { _ in
            print("didOpenApp!")
            self.checkingLocationPermission(showAlert: true)
        })
        .disposed(by: disposeBag)
    
    Navigation.setTitleNavigation(controller: self, title: "rentr.", fontSize: 40, position: "left")
    
    // Configure images with iOS 26 support
    let searchImage: UIImage
    let filterImage: UIImage
    
    if #available(iOS 26, *) {
        // Enhanced symbol configuration for iOS 26
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: 30,
            weight: .medium,
            scale: .default
        )
        
        searchImage = AwesomePro.Solid.magnifyingGlass.asImage(size: 30, color: AssetTheme.mainWhite.color)
            .withConfiguration(symbolConfig)
        filterImage = AwesomePro.Solid.sliders.asImage(size: 30, color: AssetTheme.mainWhite.color)
            .withConfiguration(symbolConfig)
    } else {
        // Fallback for earlier iOS versions
        searchImage = AwesomePro.Solid.magnifyingGlass.asImage(size: 30, color: AssetTheme.mainWhite.color)
        filterImage = AwesomePro.Solid.sliders.asImage(size: 30, color: AssetTheme.mainWhite.color)
    }
    
    let searchButton = UIBarButtonItem(image: searchImage, style: .plain, target: self, action: #selector(searchActionButton(_:)))
    let filterButton = UIBarButtonItem(image: filterImage, style: .plain, target: self, action: #selector(filterAction(_:)))
    
    // iOS 26+ specific styling
    if #available(iOS 26, *) {
        searchButton.hidesSharedBackground = true
        filterButton.hidesSharedBackground = true
        
        // Ensure tint color for iOS 26
        searchButton.tintColor = AssetTheme.mainWhite.color
        filterButton.tintColor = AssetTheme.mainWhite.color
        
        // Additional iOS 26 properties
        searchButton.isSelected = false
        filterButton.isSelected = false
    } else {
        // Fallback for earlier iOS versions
        searchButton.tintColor = AssetTheme.mainWhite.color
        filterButton.tintColor = AssetTheme.mainWhite.color
        filterButton.imageInsets = UIEdgeInsets(top: 0.0, left: 20, bottom: 0, right: 0)
    }
    
    
    
    self.navigationItem.rightBarButtonItems = [searchButton, filterButton]
}
    
    
    @IBAction func searchActionButton(_ sender: Any) {
        self.performSegue(withIdentifier: Segues.toSearchFromHome.rawValue, sender: nil)
    }
    
    func checkingLocationPermission(showAlert:Bool) {
        Utils.locationPermission { (status, error) in
            
            print("status = \(status)")
            print("error = \(error)")
            
            if status == false {
                //  self.showPulse()
                if showAlert {
                    Alerts().showLocationPermission(viewcontroller: self)
                }
            } else {
                Utils.delay(interval: 3.0) {
                }
                
            }
        }
    }
    
    @objc private func refeshData() {
        Utils.delay(interval: 0.5) {
            self.isPullRefresh = false // Ensure pulse shows for manual refresh
            self.refresh()
        }
    }
    
    @objc private func startReviewButtonAction() {
        self.emptyAddPropertyButton.isLoading = true
        Utils.delay(interval: 0.5) {
            self.performSegue(withIdentifier: Segues.toFindLocationFromSearchSegue.rawValue, sender: nil)
        }
    }
    
    
    
    // Manages the complete pulse sequence and prevents any reveal until fully complete
    private func startPulseSequence(completion: @escaping () -> Void) {
        // Skip pulse sequence for load more or pull refresh operations
        if isLoadingMore || isPullRefresh || pullRefreshInProgress {
            print("⏭️ SKIPPING startPulseSequence - isLoadingMore: \(isLoadingMore), isPullRefresh: \(isPullRefresh), pullRefreshInProgress: \(pullRefreshInProgress)")
            completion()
            return
        }
        
        print("🟣 STARTING PULSE SEQUENCE")
        // If already scheduled, ignore
        if revealScheduled { return }
        revealScheduled = true
        pulseCompletionGate = true
        
        // FORCE hide all content immediately
        self.view.isUserInteractionEnabled = false
        self.tableView.alpha = 0
        self.tableView.isHidden = true
        
        // Hide content and show pulse if not already active
        if pulseShownAt == nil { 
            beginPulseLoadingIfNeeded() 
        }
        
        // Show loading overlay after pulse is initiated but before data reveal
        
        // Wait for pulse to complete (3s min), then reveal
        hidePulse { [weak self] in
            guard let self = self else { return }
            
            // Show loading overlay after pulse finishes but before data reveal
            Utils.showLoading(gradient: .gradient)
            
            self.pulseCompletionGate = false
            self.revealScheduled = false
            completion()
        }
    }
    
    func showPulse() {
        // COMPLETELY BLOCK pulse for load more or pull refresh operations
        if isLoadingMore || isPullRefresh || pullRefreshInProgress {
            print("🛑 showPulse() COMPLETELY BLOCKED - isLoadingMore: \(isLoadingMore), isPullRefresh: \(isPullRefresh), pullRefreshInProgress: \(pullRefreshInProgress)")
            // Reset any blocking states that might have been set
            self.pulseCompletionGate = false
            self.view.isUserInteractionEnabled = true
            self.tableView.isHidden = false
            self.tableView.alpha = 1
            return
        }
        
        // If already active, do nothing
        if isPulseActive { 
            print("⚠️ showPulse() called but pulse already active")
            return 
        }
        
        print("🟣 showPulse() STARTING - isLoadingMore: \(isLoadingMore), isPullRefresh: \(isPullRefresh)")
        
        isPulseActive = true
        pulseShownAt = Date()
        pulseStartTime = Date()
        print("🟣 PULSE STARTED at \(pulseStartTime!)")
        // Ensure a dedicated top-level window so the pulse is above all overlays
        let allWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { !$0.isHidden && $0.alpha > 0 }
        let topWindow = allWindows.max(by: { $0.windowLevel.rawValue < $1.windowLevel.rawValue })
        if pulseWindow == nil {
            if let scene = topWindow?.windowScene {
                let win = UIWindow(windowScene: scene)
                win.frame = scene.coordinateSpace.bounds
                pulseWindow = win
            } else {
                pulseWindow = UIWindow(frame: UIScreen.main.bounds)
            }
            pulseWindow?.rootViewController = PulseHostViewController()
            pulseWindow?.windowLevel = .alert + 1
            // Keep background completely clear - no gray overlay
            pulseWindow?.backgroundColor = .clear
            pulseWindow?.alpha = 1.0
            pulseWindow?.isUserInteractionEnabled = false
            pulseWindow?.isHidden = false
        }

        guard let hostWindow = pulseWindow else { return }
        if avatarView.superview !== hostWindow {
            avatarView.removeFromSuperview()
            
            // Position pulsator at screen center for optimal visibility
            avatarView.center = CGPoint(x: hostWindow.bounds.midX, y: hostWindow.bounds.midY)
            print("🎯 Positioning at screen center: \(avatarView.center)")
            print("🎯 Window bounds: \(hostWindow.bounds)")
            
            hostWindow.addSubview(avatarView)
        }

        if pulsator.superlayer !== hostWindow.layer {
            pulsator.removeFromSuperlayer()
            hostWindow.layer.addSublayer(pulsator)
        }

        hostWindow.layoutIfNeeded()
        // Set pulsator position directly to match avatarView position
        pulsator.position = avatarView.layer.position
        // Ensure avatar is above the pulse waves
        avatarView.layer.zPosition = 1000
        pulsator.zPosition = 999

        // 2. Setup pulsator using imageView bounds for pulse rays
        let imageFrame = emptyImageView.frame
        let imageDimension = max(imageFrame.width, imageFrame.height)
        let imageRadius = imageDimension / 2 // Distance from center to image border
        
        pulsator.radius = Utils.screenWidth() - 150
        print("🎯 Image radius: \(imageRadius), pulse expansion radius: \(pulsator.radius)")
        pulsator.numPulse = 6
        pulsator.speed = 0.5
        pulsator.animationDuration = 3
        pulsator.repeatCount = .infinity
        avatarView.layer.superlayer?.insertSublayer(pulsator, below: avatarView.layer)
        pulsator.backgroundColor = AssetTheme.buttonColor.color.withAlphaComponent(0.6).cgColor
        pulsator.start()
        hostWindow.bringSubviewToFront(avatarView)

        // Defensive: if any overlay appears after, keep bringing front briefly
        Utils.delay(interval: 0.05) { [weak self] in
            guard let self = self else { return }
            self.pulseWindow?.bringSubviewToFront(self.avatarView)
        }
    }

    func hidePulse(extraDelay: TimeInterval = 0, completion: (() -> Void)? = nil) {
        let minVisible: TimeInterval = 3.0
        let elapsed = pulseShownAt.map { Date().timeIntervalSince($0) } ?? minVisible
        let remaining = max(0, minVisible - elapsed)
        // Step 1: after minimum visibility, stop the pulse and remove the avatar
        Utils.delay(interval: remaining) { [weak self] in
            guard let self = self else { return }
            print("🟡 PULSE WAVES STOPPED after \(remaining)s minimum wait")
            self.pulsator.stop()
            self.pulsator.removeFromSuperlayer()
            self.avatarView.removeFromSuperview()
            // Step 2: hold the overlay for the extra delay, then fade it out and cleanup
            Utils.delay(interval: max(0, extraDelay)) { [weak self] in
                guard let self = self else { return }
                self.pulseEndTime = Date()
                let totalDuration = self.pulseStartTime.map { self.pulseEndTime!.timeIntervalSince($0) } ?? 0
                print("🔴 PULSE FULLY ENDED after total \(String(format: "%.2f", totalDuration))s")
                if let win = self.pulseWindow {
                    UIView.animate(withDuration: 0.2, animations: { win.alpha = 0 }) { _ in
                        win.isHidden = true
                        self.pulseWindow = nil
                        self.pulseShownAt = nil
                        self.isPulseActive = false
                        print("🟢 PULSE CLEANUP COMPLETE - calling completion")
                        completion?()
                    }
                } else {
                    self.pulseWindow?.isHidden = true
                    self.pulseWindow = nil
                    self.pulseShownAt = nil
                    self.isPulseActive = false
                    print("🟢 PULSE CLEANUP COMPLETE (no window) - calling completion")
                    completion?()
                }
            }
        }
    }
    
    
    
    
    
    
    func pullRefresh() {
        let animatorFooter = ESRefreshFooterAnimator()
        animatorFooter.loadingMoreDescription = "Load more properties"
        animatorFooter.noMoreDataDescription = "No more properties"
        animatorFooter.loadingDescription = "Loading properties..."
        
        self.tableView.es.addPullToRefresh { [unowned self] in
            print("🔄 PULL TO REFRESH TRIGGERED")
            
            // Nuclear option: disable all ViewModel callbacks
            self.ignoreViewModelCallbacks = true
            
            // Set persistent flags
            self.isPullRefresh = true
            self.pullRefreshInProgress = true
            
           // IMMEDIATELY stop any pulse and reset all pulse states
            if self.isPulseActive {
                print("🛑 FORCE STOPPING PULSE for pull refresh")
                self.pulsator.stop()
                self.pulsator.removeFromSuperlayer()
                self.avatarView.removeFromSuperview()
                self.pulseWindow?.isHidden = true
                self.pulseWindow = nil
                self.pulseShownAt = nil
                self.isPulseActive = false
                self.revealScheduled = false
            }
            
            //  Reset all blocking states
            self.pulseCompletionGate = false
            self.view.isUserInteractionEnabled = true
            self.tableView.isHidden = false
            self.tableView.alpha = 1
            
            // Use direct refresh without pulse and handle manually
            self.refreshDirectlyWithManualHandling()
        }
        self.tableView.es.addInfiniteScrolling { [unowned self] in
            self.loadMore()
        }
    }
    
    // MARK: - Refresh / Load more with online/offline policy
    func refresh() {
        isLoadingMore = false // Ensure this is not a load more operation
        
        // Only show pulse for initial loading, not for pull-to-refresh
        let shouldShowPulse = !isPullRefresh
        print("🔄 REFRESH CALLED - isPullRefresh: \(isPullRefresh), shouldShowPulse: \(shouldShowPulse)")
        if shouldShowPulse {
            beginPulseLoadingIfNeeded()
        }
        
        Utils.delay(interval: 1.0) { [weak self] in
            guard let self = self else { return }
            let isOnline = Network.Connectivity()
            self.location.currentCoorditanates { coordinates, _ in
                let barText = self.searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let effectiveSearch = !barText.isEmpty ? barText : self.lastNonEmptySearch
                
                var params: [String: Any] = [
                    "remoteFirst": isOnline,
                    "syncDeletions": isOnline,
                    "localOnly": !isOnline
                ]
                if !effectiveSearch.isEmpty {
                    params["search"] = effectiveSearch
                    params["search_fields"] = ["name","type","subtype","furnishing","features","location"]
                }
                if let c = coordinates {
                    params["current_latitude"] = c.latitude
                    params["current_longitude"] = c.longitude
                }
                
                self.propertyListViewModel.resetPaging()
                self.propertyListViewModel.fetchData(parameters: params, page: 1, position: .top)
            }
        }
    }
    
    // Direct refresh for pull-to-refresh without pulse animation
    func refreshDirectly() {
        print("🔄 DIRECT REFRESH (no pulse)")
        isLoadingMore = false
        // DO NOT call beginPulseLoadingIfNeeded() for pull refresh
        
        Utils.delay(interval: 1.0) { [weak self] in
            guard let self = self else { return }
            let isOnline = Network.Connectivity()
            self.location.currentCoorditanates { coordinates, _ in
                let barText = self.searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let effectiveSearch = !barText.isEmpty ? barText : self.lastNonEmptySearch
                
                var params: [String: Any] = [
                    "remoteFirst": isOnline,
                    "syncDeletions": isOnline,
                    "localOnly": !isOnline
                ]
                if !effectiveSearch.isEmpty {
                    params["search"] = effectiveSearch
                    params["search_fields"] = ["name","type","subtype","furnishing","features","location"]
                }
                if let c = coordinates {
                    params["current_latitude"] = c.latitude
                    params["current_longitude"] = c.longitude
                }
                
                self.propertyListViewModel.resetPaging()
                self.propertyListViewModel.fetchData(parameters: params, page: 1, position: .top)
            }
        }
    }
    
    // Complete manual refresh for pull-to-refresh that bypasses ViewModel callbacks
    func refreshDirectlyWithManualHandling() {
        print("🔄 MANUAL REFRESH (completely disconnecting ViewModel)")
        isLoadingMore = false
        
        // Clear any existing loading states before starting pull-to-refresh
        Utils.hideLoading()
        
        Utils.delay(interval: 1.0) { [weak self] in
            guard let self = self else { return }
            let isOnline = Network.Connectivity()
            
            self.location.currentCoorditanates { coordinates, _ in
                let barText = self.searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let effectiveSearch = !barText.isEmpty ? barText : self.lastNonEmptySearch
                
                var params: [String: Any] = [
                    "remoteFirst": isOnline,
                    "syncDeletions": isOnline,
                    "localOnly": !isOnline
                ]
                if !effectiveSearch.isEmpty {
                    params["search"] = effectiveSearch
                    params["search_fields"] = ["name","type","subtype","furnishing","features","location"]
                }
                if let c = coordinates {
                    params["current_latitude"] = c.latitude
                    params["current_longitude"] = c.longitude
                }
                
                // Manually handle data fetch and update without ViewModel callbacks
                self.propertyListViewModel.resetPaging()
                
                // COMPLETE DISCONNECTION: Set all callbacks to nil first
                self.propertyListViewModel.onDataUpdated = nil
                self.propertyListViewModel.onShowLoading = nil
                self.propertyListViewModel.onHideLoading = nil
                
                //Now fetch data WITHOUT any callbacks
                self.propertyListViewModel.fetchData(parameters: params, page: 1, position: .top)
                
                // Handle the update manually after a delay to ensure fetch completes
                Utils.delay(interval: 2.0) { [weak self] in
                    guard let self = self else { return }
                    print("📊 MANUAL DATA UPDATE - handling without any ViewModel callbacks")
                    self.isLoading = false
                    self.emptyData = self.propertyListViewModel.isEmpty
                    self.tableView.reloadData()
                    self.tableView.reloadEmptyDataSet()
                    self.tableView.es.stopPullToRefresh()
                    
                    // Ensure Utils.hideLoading() is called during manual handling
                    Utils.hideLoading()
                    
                    // Reset flags and restore ViewModel callbacks
                    self.ignoreViewModelCallbacks = false
                    self.isPullRefresh = false
                    self.pullRefreshInProgress = false
                    
                    // Restore original ViewModel callbacks
                    self.setupViewModelCallbacks()
                }
            }
        }
    }
    
    func loadMore() {
        isLoadingMore = true // Mark as load more operation
        Utils.delay(interval: 1.0) { [weak self] in
            guard let self = self else { return }
            let isOnline = Network.Connectivity()
            
            self.location.currentCoorditanates { coordinates, _ in
                var params: [String: Any] = [
                    "remoteFirst": isOnline,
                    "syncDeletions": isOnline,
                    "localOnly": !isOnline
                ]
                
                if let searchText = self.searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !searchText.isEmpty {
                    params["search"] = searchText
                    params["search_fields"] = ["name", "type", "subtype", "furnishing", "features", "location"]
                }
                
                if let coordinates = coordinates {
                    params["current_latitude"] = coordinates.latitude
                    params["current_longitude"] = coordinates.longitude
                }
                
                self.propertyListViewModel.fetchData(
                    parameters: params,
                    page: self.propertyListViewModel.currentPage,
                    position: .bottom
                )
            }
        }
    }
    
    // MARK: - ViewModel Callbacks Setup
    func setupViewModelCallbacks() {
        propertyListViewModel.onDataUpdated = { [weak self] in
            guard let self = self else { return }
            
            // Nuclear option: ignore all callbacks during pull refresh
            if self.ignoreViewModelCallbacks {
                print("🚫 IGNORING onDataUpdated - callbacks disabled during pull refresh")
                return
            }
            
            self.isLoading = false
            self.emptyData = self.propertyListViewModel.isEmpty
            
            // PRIORITY 1: Skip pulse for load more operations
            if self.isLoadingMore {
                print("⏭️ SKIPPING PULSE - this is a load more operation")
                // Ensure table is visible and interactive for load more
                self.pulseCompletionGate = false
                self.view.isUserInteractionEnabled = true
                self.tableView.isHidden = false
                self.tableView.alpha = 1
                self.tableView.reloadData()
                self.tableView.reloadEmptyDataSet()
                self.tableView.es.stopPullToRefresh()
                self.isLoadingMore = false // Reset the flag after handling load more
                // Ensure loading is hidden for load more operations
                Utils.hideLoading()
                return
            }
            
            // PRIORITY 2: Skip pulse for pull refresh operations - ABSOLUTE BLOCK
            if self.isPullRefresh || self.pullRefreshInProgress {
                print("⏭️ ABSOLUTE BLOCK - this is a pull refresh operation (isPullRefresh: \(self.isPullRefresh), pullRefreshInProgress: \(self.pullRefreshInProgress))")
                // FORCE stop any pulse that might be running
                if self.isPulseActive {
                    self.pulsator.stop()
                    self.pulsator.removeFromSuperlayer()
                    self.avatarView.removeFromSuperview()
                    self.pulseWindow?.isHidden = true
                    self.pulseWindow = nil
                    self.pulseShownAt = nil
                    self.isPulseActive = false
                    self.revealScheduled = false
                }
                // Ensure table is visible and interactive for pull refresh
                self.pulseCompletionGate = false
                self.view.isUserInteractionEnabled = true
                self.tableView.isHidden = false
                self.tableView.alpha = 1
                self.tableView.reloadData()
                self.tableView.reloadEmptyDataSet()
                self.tableView.es.stopPullToRefresh()
                return
            }
            
            print("📊 DATA UPDATED - starting pulse sequence (isLoadingMore: \(self.isLoadingMore), isPullRefresh: \(self.isPullRefresh))")
            
            // For initial loading, start the reveal sequence after pulse completes
            self.startPulseSequence {
                print("✅ REVEALING TABLE DATA")
                self.view.isUserInteractionEnabled = true
                self.tableView.isHidden = false
                self.tableView.alpha = 1
                self.tableView.reloadData()
                self.tableView.reloadEmptyDataSet()
                self.tableView.es.stopPullToRefresh()
            }
        }
        
        propertyListViewModel.onShowLoading = { [weak self] in
            guard let self = self else { return }
            
            // Nuclear option: ignore all callbacks during pull refresh
            if self.ignoreViewModelCallbacks {
                print("🚫 IGNORING onShowLoading - callbacks disabled during pull refresh")
                return
            }
            
            // ABSOLUTE BLOCK for pull refresh - don't even set loading states
            if self.isPullRefresh || self.pullRefreshInProgress {
                print("⏭️ ABSOLUTE BLOCK onShowLoading - this is a pull refresh operation (isPullRefresh: \(self.isPullRefresh), pullRefreshInProgress: \(self.pullRefreshInProgress))")
                return
            }
            
            // ABSOLUTE BLOCK for load more - don't even set loading states  
            if self.isLoadingMore {
                print("⏭️ ABSOLUTE BLOCK onShowLoading - this is a load more operation")
                return
            }
            
            print("🔄 onShowLoading - setting up pulse for initial loading")
            self.isLoading = true
            self.emptyData = false
            
            // IMMEDIATELY block all content and start pulse for initial loading only
            self.pulseCompletionGate = true
            self.view.isUserInteractionEnabled = false
            self.tableView.alpha = 0
            self.tableView.isHidden = true
            self.tableView.reloadEmptyDataSet()
            
            DispatchQueue.main.async {
                self.showPulse()
            }
        }
        
        propertyListViewModel.onHideLoading = { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.tableView.reloadEmptyDataSet()
            Utils.hideLoading()
        }
        
        propertyListViewModel.onNoMoreData = { [weak self] in
            self?.tableView.es.noticeNoMoreData()
        }
    }
    
    // MARK: - Batch insert rows for "load more"
    func reloadMoreData(_ startingRow:Int) {
        // If pulse gate is active, just reload the entire table to avoid batch update crashes
        if pulseCompletionGate {
            tableView.reloadData()
            return
        }
        
        let endingRow = propertyListViewModel.properties.count
        var rowStart: Int = startingRow
        var indexPath = [IndexPath]()
        while rowStart < endingRow {
            indexPath.append(IndexPath(row: rowStart, section: 0))
            rowStart += 1
        }
        
        // Only do batch updates if we have valid index paths and pulse gate is not active
        guard !indexPath.isEmpty else {
            tableView.reloadData()
            return
        }
        
        tableView.performBatchUpdates {
            tableView.insertRows(at: indexPath, with: .none)
        } completion: { _ in }
    }
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == Segues.toFindLocationFromSearchSegue.rawValue {
            if let destination = segue.destination as? UINavigationController {
                let viewController = destination.topViewController as! FindLocationViewController
                viewController.inputType = "add"
                viewController.indentifier = "fromsearch"
            }
        } else if segue.identifier == Segues.toSearchFilterSegue.rawValue {
            if let destination = segue.destination as? UINavigationController {
                _ = destination.topViewController as? SearchFilterTableViewController
            }
        } else if segue.identifier == Segues.toSearchFromHome.rawValue {
            
            if let destination = segue.destination as? UINavigationController {
                let viewController = destination.topViewController as! SearchPropertyViewController
            }
        } else if segue.identifier == Segues.toSearchFilterSegue.rawValue {
            if let destination = segue.destination as? UINavigationController {
                let viewController = destination.topViewController as! SearchFilterTableViewController
            }
        }
    }
    
    func downloadImages(_ url: String, _ index: Int) {}
    
    @IBAction func dismissAction(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    

    
    private func reloadCurrentView() {
        print("🔄 Reloading SearchResultViewController")
        
        // Scroll to top
        if tableView.numberOfRows(inSection: 0) > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        }
        
        // Clear search if active
        if searchController.isActive {
            searchController.searchBar.text = ""
            searchController.isActive = false
            lastNonEmptySearch = ""
            isExplicitSearch = false
        }
        
        // Trigger a refresh
        isPullRefresh = false // Ensure pulse shows for same tab reload
        refresh()
    }
}

extension SearchResultViewController: EmptyDataSetSource, EmptyDataSetDelegate {
    func customView(forEmptyDataSet scrollView: UIScrollView) -> UIView? { return self.emptyDataView }
    func emptyDataSetShouldDisplay(_ scrollView: UIScrollView) -> Bool { 
        // Block empty state while pulse is active
        if pulseCompletionGate { return false }
        return !isLoading && emptyData 
    }
    func emptyDataSetShouldAllowTouch(_ scrollView: UIScrollView) -> Bool { return true }
    func emptyDataSetShouldAllowScroll(_ scrollView: UIScrollView) -> Bool { return true }
}

// MARK: - UISearchResult Updating and UISearchControllerDelegate
extension SearchResultViewController: UISearchResultsUpdating, UISearchControllerDelegate {
    func updateSearchResults(for searchController: UISearchController) {
        guard let raw = searchController.searchBar.text else { return }
        let searchText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        
        if searchText.isEmpty {
            // Browse mode (empty) → show all
            lastNonEmptySearch = ""
            isExplicitSearch = false
            lastIssuedQuery = ""
            isLoading = true
            emptyData = false
            tableView.reloadEmptyDataSet()
            self.isPullRefresh = false // Ensure pulse shows for search clearing
            self.refresh()
        } else {
            // Search mode (non-empty) → clear immediately, then search
            isExplicitSearch = true
            lastIssuedQuery = searchText
            lastNonEmptySearch = searchText
            propertyListViewModel.clearList()
            emptyData = true
            tableView.reloadData()
            
            isLoading = true
            tableView.reloadEmptyDataSet()
            
            perform(#selector(executeSearch), with: searchText, afterDelay: 0.5)
        }
    }
    
    @objc private func executeSearch(_ searchText: String) {
        performSearch(with: searchText)
    }
}

// MARK: - UITableView
extension SearchResultViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { UITableView.automaticDimension }
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { UITableView.automaticDimension }
}

extension SearchResultViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Block data rendering while pulse is active
        if pulseCompletionGate { return 0 }
        return propertyListViewModel.properties.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Block data rendering while pulse is active
        if pulseCompletionGate { return UITableViewCell() }
        
        guard
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as? CellSearchResultTableViewCell,
            let property = propertyListViewModel.properties[safe: indexPath.row]
        else { return UITableViewCell() }
        
        let urlsFromModel: [String] = property.images.map { $0.url }
        let sourcesFromModel: [InputSource] = urlsFromModel.compactMap { KingfisherSource(urlString: $0) }
        
        cell.imageHeaderView.activityIndicator = DefaultActivityIndicator(style: .medium, color: AssetTheme.mainWhite.color)
        cell.imageHeaderView.setImageInputs(sourcesFromModel)
        
        cell.propertyName.text = property.name
        cell.furnishLabel.text = property.furnishing.isEmpty ? "n/a" : property.furnishing
        cell.otherSubCatType.text = property.subtype
        
        let categoryEnum = Properties.propertyCatId(rawValue: property.categoryId) ?? .residential
        let mainColor = AssetTheme.mainBlack.color
        let (imageProperty, othersubcatImage): (UIImage, UIImage) = {
            switch categoryEnum {
            case .residential:
                return (AwesomePro.Solid.houseBuilding.asImage(size: 25, color: mainColor),
                        AwesomePro.Solid.bedFront.asImage(size: 25, color: mainColor))
            case .leisure:
                return (AwesomePro.Solid.houseWater.asImage(size: 25, color: mainColor),
                        AwesomePro.Solid.hotel.asImage(size: 25, color: mainColor))
            case .commercial:
                return (AwesomePro.Solid.city.asImage(size: 25, color: mainColor),
                        AwesomePro.Solid.buildingMemo.asImage(size: 25, color: mainColor))
            case .industrial:
                return (AwesomePro.Solid.industryWindows.asImage(size: 25, color: mainColor),
                        AwesomePro.Solid.warehouseFull.asImage(size: 25, color: mainColor))
            case .special:
                return (AwesomePro.Solid.garageCar.asImage(size: 25, color: mainColor),
                        AwesomePro.Solid.farm.asImage(size: 25, color: mainColor))
            case .mixUse:
                return (AwesomePro.Solid.apartment.asImage(size: 25, color: mainColor),
                        AwesomePro.Solid.store.asImage(size: 25, color: mainColor))
            }
        }()
        cell.catTypeImageView.image = imageProperty
        cell.otherSubCatTypeImageView.image = othersubcatImage
        cell.catTypeLabel.text = "\(categoryEnum.displayName) / \(property.type)"
        
        let loc = property.location
        let address = "\(loc.unit) \(loc.building) \(loc.addressLine1) \(loc.addressLine2) \(loc.barangay) \(loc.city) \(loc.province) \(loc.country)"
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cell.addressLabel.text = address
        
        let formatter = CurrencyFormatter { $0.locale = CurrencyLocale.current }
        let formattedRate = formatter.string(from: property.rate) ?? "0.0"
        cell.rateLabel.text = (property.rate <= 0 || formattedRate == "0.0" || formattedRate == "0.00")
        ? "n/a" : "\(formattedRate)\n\(property.terms)"
        
        let area = property.floorArea
        if area == 0 {
            cell.floorAreaLabel.text = "n/a"
        } else {
            let nf = NumberFormatter()
            nf.numberStyle = .decimal
            nf.minimumFractionDigits = 0
            nf.maximumFractionDigits = 2
            let areaNumber = NSDecimalNumber(decimal: area)
            let areaStr = nf.string(from: areaNumber) ?? areaNumber.stringValue
            cell.floorAreaLabel.text = "\(areaStr) sqm"
        }
        
        if property.reviewCount > 1 {
            cell.reviewCountLabel.attributedText = "\(property.reviewCount) reviews".withUnderlineStyle(.single).withFont(Fonts.sfProTextRegular(size: 17)).withTextColor(AssetTheme.mainWhite.color)
        } else {
            cell.reviewCountLabel.attributedText = "\(property.reviewCount) review".withUnderlineStyle(.single).withFont(Fonts.sfProTextRegular(size: 17)).withTextColor(AssetTheme.mainWhite.color)
        }
        
        cell.propertyRateView.rating = property.overallScoreReview
        let overallStr = NumberFormatter.localizedString(from: NSNumber(value: property.overallScoreReview), number: .decimal)
        
        print("PUtae= \(overallStr) === \(property.overallScoreReview)")
        
        cell.propertyRateView.text = "\(property.overallScoreReview)"
        cell.distanceLabel.text = property.distanceText
        
        let groupedByType = Dictionary(grouping: property.features, by: { $0.typeId })
        let allowedTypeIds: Set<Int> = [
            FeaturesAndRulesType.amenities.rawValue,
            FeaturesAndRulesType.features.rawValue
        ]
        
        let groupedLines: [NSAttributedString] = groupedByType.keys
            .filter { allowedTypeIds.contains($0) }
            .sorted()
            .compactMap { (typeId) -> NSAttributedString? in
                let title = FeaturesAndRulesType(rawValue: typeId)?.title ?? ""
                let items = (groupedByType[typeId] ?? [])
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !items.isEmpty else { return nil }
                
                let titleAttr = NSAttributedString(
                    string: "\(title):\n",
                    attributes: [.font: Fonts.sfProTextBold(size: 17), .foregroundColor: AssetTheme.mainBlack.color]
                )
                let itemsAttr = NSAttributedString(
                    string: items.joined(separator: " • "),
                    attributes: [.font: Fonts.sfProTextRegular(size: 17), .foregroundColor: AssetTheme.mainGray.color]
                )
                
                let combined = NSMutableAttributedString()
                combined.append(titleAttr)
                combined.append(itemsAttr)
                return combined
            }
        
        let featuresText = groupedLines.reduce(into: NSMutableAttributedString()) { acc, line in
            if acc.length > 0 { acc.append(NSAttributedString(string: "\n\n")) }
            acc.append(line)
        }
        
        let itemNotAvailable = NSAttributedString(
            string: "No ameneties available",
            attributes: [.font: Fonts.sfProTextRegular(size: 17), .foregroundColor: AssetTheme.mainGray.color]
        )
        cell.amenitiesLabel.attributedText = featuresText.length == 0 ? itemNotAvailable : featuresText
        
        UIView.performWithoutAnimation {
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
        }
        cell.contentView.clipsToBounds = true
        cell.separatorInset = .zero
        cell.layoutMargins = .zero
        cell.preservesSuperviewLayoutMargins = false
        
        return cell
    }
}

extension SearchResultViewController {
    // Remote-first search if online, else local-only
    private func performSearch(with searchText: String) {
        isLoadingMore = false // Ensure this is not a load more operation
        isPullRefresh = false // Ensure this is not a pull refresh operation
        beginPulseLoadingIfNeeded()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastNonEmptySearch = ""
            isExplicitSearch = true
            lastIssuedQuery = ""
            propertyListViewModel.clearList()
            emptyData = true
            tableView.reloadData()
            tableView.reloadEmptyDataSet()
            // Ensure loading is hidden when returning early for empty search
            Utils.hideLoading()
            return
        }
        
        lastNonEmptySearch = trimmed
        let isOnline = Network.Connectivity()
        
        Utils.delay(interval: 0.5) { [weak self] in
            guard let self = self else { return }
            self.location.currentCoorditanates { coordinates, _ in
                var params: [String: Any] = [
                    "search": trimmed,
                    "search_fields": ["name","type","subtype","furnishing","features","location"],
                    "remoteFirst": isOnline,
                    "syncDeletions": isOnline,
                    "localOnly": !isOnline
                ]
                if let c = coordinates {
                    params["current_latitude"] = c.latitude
                    params["current_longitude"] = c.longitude
                }
                
                self.propertyListViewModel.resetPaging()
                self.propertyListViewModel.fetchData(parameters: params, page: 1, position: .top)
            }
        }
    }
}

// MARK: - Safe subscript
extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - UISearchBarDelegate
extension SearchResultViewController {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        performSearch(with: text)
        searchBar.resignFirstResponder()
    }
}
extension SearchResultViewController {
    
        // MARK: - Tab Navigation Methods
        func switchToTab(at index: Int) {
            // Method 1: Access through navigation controller's ESTabBarController
            if let esTabBarController = self.navigationController?.tabBarController as? ESTabBarController {
                esTabBarController.selectedIndex = index
                print("🔄 Switched to ESTabBar index: \(index)")
            }
            // Method 2: Access through presenting view controller (if presented modally)
            else if let presentingVC = self.presentingViewController as? ESTabBarController {
                presentingVC.selectedIndex = index
                print("🔄 Switched to ESTabBar index: \(index)")
            }
            // Method 3: Find ESTabBarController in view hierarchy
            else if let esTabBarController = self.findESTabBarController() {
                esTabBarController.selectedIndex = index
                print("🔄 Switched to ESTabBar index: \(index)")
            } else {
                print("❌ Could not find ESTabBarController")
            }
        }
    
        private func findESTabBarController() -> ESTabBarController? {
            var currentVC: UIViewController? = self
            while currentVC != nil {
                if let esTabBarController = currentVC as? ESTabBarController {
                    return esTabBarController
                }
                currentVC = currentVC?.parent
            }
            return nil
        }
    
        // Convenience methods for your specific tab structure
        func switchToSearchTab() {
            switchToTab(at: 0) // NavSearchViewController
        }
    
        func switchToMyReviewsTab() {
            switchToTab(at: 1) // NavMyReviewsViewController
        }
    
        func switchToAddTab() {
            // Note: This will trigger the hijack handler and present modally
            switchToTab(at: 2) // NavAddViewController (special handling)
        }
    
        func switchToNotificationsTab() {
            switchToTab(at: 3) // NavNotificationsViewController
        }
    
        func switchToProfileTab() {
            switchToTab(at: 4) // NavProfileViewController
        }
    
        // MARK: - Tab Bar Delegate Setup
        private func setupTabBarDelegate() {
            // Find and set delegate for ESTabBarController (uses UITabBarControllerDelegate)
            if let esTabBarController = findESTabBarController() {
                esTabBarController.delegate = self
                print("🔄 ESTabBarController delegate set")
            } else if let esTabBarController = self.navigationController?.tabBarController as? ESTabBarController {
                esTabBarController.delegate = self
                print("🔄 ESTabBarController delegate set via navigationController")
            } else if let presentingVC = self.presentingViewController as? ESTabBarController {
                presentingVC.delegate = self
                print("🔄 ESTabBarController delegate set via presentingViewController")
            } else {
                print("❌ Could not set ESTabBarController delegate (controller not found yet)")
            }
        }
    
        // MARK: - UITabBarControllerDelegate
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            // Note: With ESTabBar’s custom selection path, shouldSelect may not be called.
            print("🔄 shouldSelect called with VC: \(viewController)")
            return true
        }
    
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            // This is reliably called by ESTabBarController after selection for non-hijacked tabs
            print("✅ didSelect called. selectedIndex=\(tabBarController.selectedIndex)")
            // Detect same-tab reselect (user tapped the already selected tab)
            if let nav = viewController as? UINavigationController,
               nav == tabBarController.selectedViewController {
                // If this VC corresponds to the first tab, trigger your reload
                if tabBarController.selectedIndex == 0 {
                    print("🔁 Same tab reselected - reloading current view")
                    self.reloadCurrentView()
                }
            } else {
                // Fallback: if not embedded or type differs, still handle index
                if tabBarController.selectedIndex == 0 {
                    print("🔁 Selected tab index 0 - optional reload logic")
                }
            }
        }
    
}
