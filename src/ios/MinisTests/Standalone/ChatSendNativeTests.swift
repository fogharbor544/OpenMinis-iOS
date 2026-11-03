import UIKit
import SwiftUI
import os

struct AppLogger {
    init(category: String) {}
    func info(_ message: String) { print(message) }
    func debug(_ message: String) {}
}
enum AssistantHeaderMetrics { static func fontKey()->CGFloat { 17 }
    static func formulaHeight()->CGFloat { 26 } }
@MainActor final class CrossLoadHeightMemo {
    static let shared=CrossLoadHeightMemo()
    func record(_ key:String,width:CGFloat,height:CGFloat) {}
}
enum ToggleAnchorMath { static func skipsVisibleCompensation(index:Int,anchored:Int?)->Bool { index==anchored } }

@MainActor final class VM {
    var messages = Array(0..<120)
    var streamText: String?
    var events = [String]()
    var isLoadingSession=false
    var streamingUIUpdatesSuspended=false
    var isNearBottom=false
    var isAtFirstTurn=false
    var onResume:(()->Void)?
    func setStreamingUIUpdatesSuspended(_ value:Bool) {
        let old=streamingUIUpdatesSuspended; streamingUIUpdatesSuspended=value
        events.append(value ? "suspend" : "resume")
        if old && !value { onResume?() }
    }
}
@MainActor final class FixtureCell:UICollectionViewCell {
    override func preferredLayoutAttributesFitting(_ attrs:UICollectionViewLayoutAttributes)->UICollectionViewLayoutAttributes {
        let result=attrs.copy() as! UICollectionViewLayoutAttributes
        result.size.height=max(44,contentView.systemLayoutSizeFitting(
            CGSize(width:attrs.size.width,height:UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority:.required,verticalFittingPriority:.fittingSizeLevel).height)
        return result
    }
}
@MainActor final class FixtureSurface {
    let collectionView:UICollectionView
    var messageListLayout:MessageListLayout? { collectionView.collectionViewLayout as? MessageListLayout }
    init(_ cv:UICollectionView) { collectionView=cv }
}
@MainActor final class Coordinator:NSObject,UICollectionViewDelegate {
    enum ScrollMode { case autoScrolling, userBrowsing }
    let collectionView:UICollectionView?
    let viewModel:VM?
    let viewController:FixtureSurface?
    var vm:VM? { viewModel }
    var dataSource:UICollectionViewDiffableDataSource<Int,Int>!
    var scrollMode=ScrollMode.userBrowsing
    var snapshotApplyInProgress=false
    var snapshotFlushScheduled=false
    var latestPositionPending=false
    var latestPositionScheduled=false
    var performingLatestPosition=false
    var isFlushing=false
    var hasPendingSnapshot=false
    var isAnimatingScrollToBottom=false
    var lastJumpedUserId:UUID?
    var composerShrinkAbsorbDeadline:CFTimeInterval=0
    var snapshotDepth=0
    var maxSnapshotDepth=0
    var applied=0
    var rejectedReentry=0
    var forceReentry=false
    var coalescedScrollWork: DispatchWorkItem?
    var pinDeadline: CFTimeInterval = 0
    var layout:MessageListLayout? { collectionView?.collectionViewLayout as? MessageListLayout }
    init(collectionView:UICollectionView,vm:VM) {
        self.collectionView=collectionView;self.viewModel=vm;self.viewController=FixtureSurface(collectionView)
        super.init();collectionView.delegate=self
        collectionView.register(FixtureCell.self,forCellWithReuseIdentifier:"row")
        dataSource=UICollectionViewDiffableDataSource<Int,Int>(collectionView:collectionView) { cv,path,id in
            let cell=cv.dequeueReusableCell(withReuseIdentifier:"row",for:path)
            let markdown=(id == vm.messages.last ? vm.streamText : nil) ?? String(repeating:"A streaming **reply** with a [link](https://example.com). ",count:id%3==0 ? 45:3)
            cell.contentConfiguration=UIHostingConfiguration {
                VStack(alignment:.leading,spacing:8) {
                    Text(try! AttributedString(markdown:markdown))
                    if id%3==0 {
                        Text("| Item | State |\n|---|---|\n| Task | Running |").font(.system(.caption,design:.monospaced))
                        Label("Tool response",systemImage:"terminal").padding(8).background(.gray.opacity(0.12))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            return cell
        }
        vm.onResume={ [weak self] in self?.scheduleSnapshotFlush(caller:"resume") }
    }
    func absorbPendingComposerShrink(caller:String) {}
    func applySubViewportCompensation(caller:String)->Bool { false }
    func isNearBottom()->Bool {
        guard let cv=collectionView else { return true }
        return cv.contentSize.height-cv.bounds.height+cv.adjustedContentInset.bottom-cv.contentOffset.y<30
    }
    func isAtContentTop()->Bool { (collectionView?.contentOffset.y ?? 0)<8 }
    static func nbDump(_ cv:UICollectionView?)->String { "native-fixture" }
    func flushPendingSnapshotIfNeeded(caller:String) {
        guard hasPendingSnapshot,let vm=viewModel,!vm.streamingUIUpdatesSuspended else { return }
        hasPendingSnapshot=false;applySnapshot(messages:vm.messages,caller:caller)
    }
    func scrollViewDidScroll(_ scrollView:UIScrollView) {
        guard !performingLatestPosition else { return }
        // An unrelated scroll observation must not synchronously flush snapshots.
    }
    func measureMainRunloopTurns() async -> Int {
        var count=0
        let signal=DispatchSemaphore(value:0)
        func spin() {
            count+=1
            if count>=8 { signal.signal() } else { DispatchQueue.main.async(execute:spin) }
        }
        DispatchQueue.main.async(execute:spin)
        while signal.wait(timeout:.now()) == .timedOut { await Task.yield() }
        return count
    }
    func applySnapshot(messages:[Int],caller:String="fixture") {
        guard let vm=viewModel,!vm.isLoadingSession else { return }
        SHIPPING_SNAPSHOT_GUARD
        vm.events.append("snapshot:"+caller)
        snapshotDepth+=1;maxSnapshotDepth=max(maxSnapshotDepth,snapshotDepth)
        defer { snapshotDepth-=1 }
        if forceReentry {
            forceReentry=false;rejectedReentry+=1;applySnapshot(messages:messages,caller:"during-layout")
        }
        var snapshot=NSDiffableDataSourceSnapshot<Int,Int>()
        snapshot.appendSections([0]);snapshot.appendItems(messages)
        if let last=messages.last,dataSource.snapshot().indexOfItem(last) != nil { snapshot.reconfigureItems([last]) }
        // Mirror the shipping apply: the content-offset adjustment is
        // suppressed for the duration of the apply, and an auto-scrolling list
        // re-pins to the tail afterwards — plus one coalesced re-pin, because
        // the cold tail cells only learn their height after the apply landed.
        // Without both, the fixture moves the offset where the shipping
        // coordinator does not.
        let listLayout=collectionView?.collectionViewLayout as? MessageListLayout
        listLayout?.suppressContentOffsetAdjustment=true
        isFlushing=true
        dataSource.apply(snapshot,animatingDifferences:false)
        collectionView?.layoutIfNeeded()
        listLayout?.suppressContentOffsetAdjustment=false
        isFlushing=false
        if scrollMode == .autoScrolling {
            scrollToBottomNow(animated:false)
            pinDeadline=CFAbsoluteTimeGetCurrent()+2.0
            scheduleCoalescedPin()
        }
        applied+=1;vm.events.append("layout:"+caller)
    }
    // The shipping coordinator re-pins whenever the content size changes, so
    // a tail cell that learns its height after the apply still ends at the
    // bottom. The fixture cannot observe that signal directly, so it re-pins
    // for a short window after every apply. The pin has to be repeated: the
    // first one is clamped to the content UIKit knows about, and the tail
    // cell only reaches its real height once it has been laid out.
    func scheduleCoalescedPin() {
        coalescedScrollWork?.cancel()
        let work=DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.scrollMode == .autoScrolling, CFAbsoluteTimeGetCurrent() < self.pinDeadline else { return }
            self.scrollToBottomNow(animated:false)
            self.scheduleCoalescedPin()
        }
        coalescedScrollWork=work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.05, execute: work)
    }
    // SHIPPING_SCROLL_METHODS
}

@main @MainActor final class ChatSendNativeTests:UIResponder,UIApplicationDelegate {
    var window:UIWindow?
    var cases:[String]=[];var failures:[String]=[]
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
        let host=UIViewController();let window=UIWindow(frame:UIScreen.main.bounds)
        window.rootViewController=host;window.makeKeyAndVisible();self.window=window
        Task { await validate(host:host,window:window) };return true
    }
    func check(_ value:Bool,_ name:String) { cases.append(name);if !value { failures.append(name) } }
    func pause() async { try? await Task.sleep(nanoseconds:250_000_000) }
    /// The hosted tail cell can learn its height after the send, so the list
    /// settles onto the bottom a moment later. Wait for that settle instead
    /// of sampling the offset at one fixed moment.
    func waitForBottom(_ cv:UICollectionView) async {
        for _ in 0..<24 {
            await pause()
            let bottom=max(0,cv.contentSize.height-cv.bounds.height+cv.adjustedContentInset.bottom)
            if abs(cv.contentOffset.y-bottom)<3 { return }
        }
    }
    func validate(host:UIViewController,window:UIWindow) async {
        let layout=MessageListLayout();layout.estimatedItemHeight=200
        let cv=UICollectionView(frame:host.view.bounds.insetBy(dx:0,dy:90),collectionViewLayout:layout)
        cv.autoresizingMask=[.flexibleWidth,.flexibleHeight];host.view.addSubview(cv)
        let vm=VM();let coordinator=Coordinator(collectionView:cv,vm:vm)
        coordinator.applySnapshot(messages:vm.messages);await pause()
        check(cv.contentSize.height>cv.bounds.height*3,"long-native-list")
        for (name,fraction) in [("top",0.0),("middle",0.5)] {
            coordinator.scrollMode = .userBrowsing
            cv.setContentOffset(CGPoint(x:0,y:cv.contentSize.height*fraction),animated:false)
            coordinator.layout?.deferSelfSizing=true;vm.setStreamingUIUpdatesSuspended(true)
            coordinator.hasPendingSnapshot=true
            vm.messages.append(vm.messages.count)
            if name=="middle" { coordinator.forceReentry=true }
            let appliedBefore=coordinator.applied
            vm.events.append("send-request-"+name)
            coordinator.requestLatestPosition();coordinator.requestLatestPosition();await waitForBottom(cv)
            let bottom=max(0,cv.contentSize.height-cv.bounds.height+cv.adjustedContentInset.bottom)
            vm.events.append("tail-"+name+": offset="+String(describing:cv.contentOffset.y)+" bottom="+String(describing:bottom))
            check(abs(cv.contentOffset.y-bottom)<3,"latest-"+name)
            check(!vm.streamingUIUpdatesSuspended && !layout.deferSelfSizing,"resume-"+name)
            check(!coordinator.latestPositionPending && !coordinator.snapshotApplyInProgress,"settled-"+name)
            // The shipping send never applies inside the request itself: the
            // pending snapshot is flushed right after the send settles, so a
            // send costs one apply. The middle case additionally injects a
            // re-entrant apply whose deferred flush may land before or after
            // this check, so both counts are allowed there.
            let maxApplies=appliedBefore+(name=="middle" ? 2 : 1)
            check(coordinator.applied>=appliedBefore+1 && coordinator.applied<=maxApplies,"normal-insertion-only-"+name)
        }
        for chunk in 1...4 {
            vm.streamText=String(repeating:"Controlled streaming markdown **chunk**. ",count:chunk*8)
            layout.invalidateHeight(at:vm.messages.count-1)
            coordinator.applySnapshot(messages:vm.messages,caller:"stream-"+String(chunk));await pause()
        }
        check(coordinator.scrollMode == .autoScrolling && coordinator.maxSnapshotDepth==1,"stream-updates-remain-serial")
        check(await coordinator.measureMainRunloopTurns()==8,"main-runloop-remains-responsive")
        let before=coordinator.applied
        for _ in 0..<5 { vm.messages.append(vm.messages.count);coordinator.requestLatestPosition() }
        await pause()
        check(coordinator.applied-before==0,"continuous-send-coalesced")
        coordinator.forceReentry=true;coordinator.applySnapshot(messages:vm.messages);await pause()
        check(coordinator.maxSnapshotDepth==1 && coordinator.rejectedReentry==2,"snapshot-reentry-deferred")
        let beforeLayout=coordinator.applied
        coordinator.latestPositionPending=true;coordinator.performingLatestPosition=true
        coordinator.applySnapshot(messages:vm.messages,caller:"hosted-layout-callback")
        check(coordinator.applied==beforeLayout && coordinator.hasPendingSnapshot,"layout-reentry-deferred")
        // A flush issued while the latest-position is still in flight must not
        // apply — the shipping coordinator defers it so a send never re-enters
        // UIKit mid-flight — but it must not lose the snapshot either.
        coordinator.flushPendingSnapshotIfNeeded(caller:"user-latest-position")
        check(coordinator.applied==beforeLayout && coordinator.hasPendingSnapshot,"latest-deferral-preserves-snapshot")
        coordinator.hasPendingSnapshot=true
        coordinator.latestPositionPending=false;coordinator.performingLatestPosition=false
        coordinator.scheduleSnapshotFlush(caller:"layout-completion");await pause()
        check(coordinator.applied==beforeLayout+1,"layout-pending-snapshot-flushed")
        coordinator.scrollMode = .userBrowsing
        cv.setContentOffset(CGPoint(x:0,y:cv.contentSize.height*0.45),animated:false)
        let historicalOffset=cv.contentOffset.y
        vm.messages.append(vm.messages.count);coordinator.applySnapshot(messages:vm.messages);await pause()
        check(coordinator.scrollMode == .userBrowsing && abs(cv.contentOffset.y-historicalOffset)<3,"background-preserves-history")
        vm.setStreamingUIUpdatesSuspended(true);coordinator.hasPendingSnapshot=true
        vm.messages.append(vm.messages.count);coordinator.requestLatestPosition();await pause()
        check(coordinator.scrollMode == .autoScrolling && !coordinator.hasPendingSnapshot,"queued-send-resumes")
        // Releasing a keyboard-sized inset while an explicit send settles must remain responsive.
        cv.contentInset.bottom=260;coordinator.requestLatestPosition()
        cv.contentInset.bottom=0;await pause()
        check(!coordinator.performingLatestPosition && coordinator.maxSnapshotDepth==1,"inset-change-settles")
        vm.isLoadingSession=true;coordinator.requestLatestPosition();await pause()
        check(coordinator.latestPositionPending,"loading-preserves-intent")
        vm.isLoadingSession=false;coordinator.applySnapshot(messages:vm.messages);await pause()
        check(!coordinator.latestPositionPending,"loading-completes-intent")
        var tapped=false
        let button=UIButton(type:.system);button.frame=CGRect(x:20,y:30,width:200,height:44)
        button.addAction(UIAction { _ in tapped=true },for:.touchUpInside);host.view.addSubview(button)
        button.sendActions(for:.touchUpInside);await pause()
        check(tapped,"button-remains-interactive")
        let result:[String:Any] = ["cases":cases,"failures":failures,"snapshotApplies":coordinator.applied,"maximumApplyDepth":coordinator.maxSnapshotDepth,"events":vm.events]
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:docs.appendingPathComponent("chat-send-native-results.json"))
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let image=UIGraphicsImageRenderer(bounds:window.bounds,format:format).pngData { _ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
        try? image.write(to:docs.appendingPathComponent("chat-send-native.png"))
        print("ChatSendNativeTests: \(result)")
    }
}
