//
//  ViewController.swift
//  test fluidité
//
//  Created by Jérôme Binachon on 05/05/2026.
//

import Cocoa
import SpriteKit

// MARK: - ViewController

class ViewController: NSViewController, NSWindowDelegate {

    @IBOutlet var skView: SKView!
    
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 120
        skView.showsFPS = true
        skView.showsNodeCount = true
        skView.showsDrawCount = true
        
        // Pinch to zoom
        let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        skView.addGestureRecognizer(magnifyGesture)
        
        // Two-finger scroll for pan — intercept at app level
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
        
        // Intercept Cmd+key before macOS consumes them
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  event.modifierFlags.contains(.command),
                  let scene = self.skView.scene as? GameScene else { return event }
            let key = (event.charactersIgnoringModifiers ?? "").lowercased()
            let shift = event.modifierFlags.contains(.shift)
            if ["z", "y", "c", "v", "d", "a"].contains(key) {
                scene.handleCommandKey(key, shift: shift)
                return nil // consume event
            }
            return event
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.delegate = self
    }
    
    // Disable macOS fullscreen "optimization" that causes SpriteKit stutter
    func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
        return NSSize(width: proposedSize.width, height: proposedSize.height - 1)
    }
    
    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        guard let scene = skView.scene as? GameScene else { return }
        scene.handleMagnification(gesture.magnification)
        if gesture.state == .ended || gesture.state == .cancelled {
            gesture.magnification = 0
        }
    }
    
    private func handleScroll(_ event: NSEvent) {
        guard let scene = skView.scene as? GameScene else { return }
        
        // Only handle scroll events that target our view
        guard let eventWindow = event.window,
              eventWindow == skView.window else { return }
        
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        
        // Use precise (trackpad) deltas directly, scale mouse wheel deltas
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        
        scene.handleScrollDelta(dx: dx * scale, dy: dy * scale)
        
        // When the gesture ends, apply inertia from momentum phase
        if event.phase == .ended {
            scene.handleScrollEnded()
        }
    }
}

