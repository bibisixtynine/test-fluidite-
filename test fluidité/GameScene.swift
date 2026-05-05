//
//  GameScene.swift
//  test fluidité
//
//  Created by Jérôme Binachon on 05/05/2026.
//

import SpriteKit
import AppKit
import UniformTypeIdentifiers

// MARK: - Data Models

struct SpriteData: Codable {
    var imageName: String
    var isAsset: Bool
    var posX: CGFloat
    var posY: CGFloat
    var velDx: CGFloat
    var velDy: CGFloat
    var scale: CGFloat
    var boundsX: CGFloat?
    var boundsY: CGFloat?
    var boundsW: CGFloat?
    var boundsH: CGFloat?
    var animationType: String?
    var oscillatingRotation: Bool?
    var zOrder: CGFloat?
    var cameraTracked: Bool?
}

struct BouncingSprite {
    let node: SKSpriteNode
    var velocity: CGVector
    var imageName: String
    var isAsset: Bool
    var halfW: CGFloat
    var halfH: CGFloat
    var movingRight: Bool
    var bounds: CGRect
    var animationType: AnimationType
    var oscillatingRotation: Bool
    var animTime: CGFloat
}

// MARK: - Handle side enum

enum HandleSide {
    case left, right, top, bottom
}

// MARK: - Animation Types

enum AnimationType: String, Codable, CaseIterable {
    case bouncing
    case horizontalBounce
    case verticalBounce
    case ellipse
    case circular
    case sinusoidal
    case fixed
    
    var displayName: String {
        switch self {
        case .bouncing:         return "Rebond libre"
        case .horizontalBounce: return "Rebond horizontal"
        case .verticalBounce:   return "Rebond vertical"
        case .ellipse:          return "Ellipse"
        case .circular:         return "Cercle"
        case .sinusoidal:       return "Sinusoïdal"
        case .fixed:            return "Fixe"
        }
    }
}

// MARK: - GameScene

class GameScene: SKScene {
    
    private var sprites: [BouncingSprite] = []
    private var lastUpdateTime: TimeInterval = 0
    private var rightClickLocation: CGPoint = .zero
    
    // Texture cache
    private var textureCache: [String: SKTexture] = [:]
    
    // Camera
    private var cameraNode = SKCameraNode()
    private var panVelocity = CGVector.zero
    private let panFriction: CGFloat = 0.92
    
    // Camera tracking
    private var trackedNode: SKSpriteNode?
    private var trackingOffset: CGVector = .zero
    
    // Grid
    private var showGrid = false
    private var gridAboveSprites = false
    private var gridNode: SKNode?
    private let gridSpacing: CGFloat = 100
    
    // Edit mode
    private var isEditing = false
    private var selectedSprites: Set<SKSpriteNode> = []
    private var cachedSelectionBBox: CGRect = .null
    private var selectionRect: SKShapeNode?
    private var selectionOrigin: CGPoint = .zero
    private var isDraggingSelection = false
    private var isDraggingSprites = false
    private var dragLastPoint: CGPoint = .zero
    private var dragStartPositions: [(node: SKSpriteNode, oldPos: CGPoint, oldBounds: CGRect)] = []
    
    // Handle dragging
    private var isDraggingHandle = false
    private var activeHandleSide: HandleSide = .left
    private var activeHandleSpriteIndex: Int = -1
    
    // Bounds visuals
    private let boundsRectPrefix = "boundsRect_"
    private let handlePrefix = "handle_"
    private let handleSize: CGFloat = 10
    
    // Clipboard
    private var clipboard: [(imageName: String, isAsset: Bool, velocity: CGVector, scale: CGFloat, offset: CGPoint, bounds: CGRect, animationType: AnimationType, oscillatingRotation: Bool)] = []
    
    // Undo
    private enum UndoAction {
        case delete([BouncingSprite])
        case move([(node: SKSpriteNode, oldPos: CGPoint, oldBounds: CGRect)])
    }
    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    
    // Fast node-to-index lookup
    private var nodeToIndex: [SKSpriteNode: Int] = [:]
    
    // Group selection visual
    private var groupSelectionNode: SKShapeNode?
    private let groupSelectionName = "groupSelection"
    
    // MARK: - Grid
    
    private func updateGrid() {
        gridNode?.removeFromParent()
        gridNode = nil
        guard showGrid, let view = self.view else { return }
        
        let zoom = cameraNode.xScale
        let camPos = cameraNode.position
        let halfW = view.bounds.width * zoom / 2
        let halfH = view.bounds.height * zoom / 2
        
        // Visible area with margin
        let visMinX = camPos.x - halfW - gridSpacing
        let visMaxX = camPos.x + halfW + gridSpacing
        let visMinY = camPos.y - halfH - gridSpacing
        let visMaxY = camPos.y + halfH + gridSpacing
        
        // Snap to grid lines
        let startX = floor(visMinX / gridSpacing) * gridSpacing
        let endX = ceil(visMaxX / gridSpacing) * gridSpacing
        let startY = floor(visMinY / gridSpacing) * gridSpacing
        let endY = ceil(visMaxY / gridSpacing) * gridSpacing
        
        let minorPath = CGMutablePath()
        let majorPath = CGMutablePath()
        let minorColor = NSColor.white.withAlphaComponent(0.06)
        let majorColor = NSColor.white.withAlphaComponent(0.15)
        let axisColor = NSColor.white.withAlphaComponent(0.3)
        let majorEvery = gridSpacing * 10
        
        // Draw grid lines
        var x = startX
        while x <= endX {
            if x != 0 { // Skip origin, drawn as axis
                let isMajor = abs(x.remainder(dividingBy: majorEvery)) < 0.1
                let target = isMajor ? majorPath : minorPath
                target.move(to: CGPoint(x: x, y: visMinY))
                target.addLine(to: CGPoint(x: x, y: visMaxY))
            }
            x += gridSpacing
        }
        var y = startY
        while y <= endY {
            if y != 0 {
                let isMajor = abs(y.remainder(dividingBy: majorEvery)) < 0.1
                let target = isMajor ? majorPath : minorPath
                target.move(to: CGPoint(x: visMinX, y: y))
                target.addLine(to: CGPoint(x: visMaxX, y: y))
            }
            y += gridSpacing
        }
        
        let container = SKNode()
        container.zPosition = gridAboveSprites ? 500 : -1000
        
        let minorShape = SKShapeNode(path: minorPath)
        minorShape.strokeColor = minorColor
        minorShape.lineWidth = 1 * zoom
        container.addChild(minorShape)
        
        let majorShape = SKShapeNode(path: majorPath)
        majorShape.strokeColor = majorColor
        majorShape.lineWidth = 1.5 * zoom
        container.addChild(majorShape)
        
        // Draw axes (thicker)
        let axisPath = CGMutablePath()
        // X axis (horizontal, y=0)
        if visMinY <= 0 && visMaxY >= 0 {
            axisPath.move(to: CGPoint(x: visMinX, y: 0))
            axisPath.addLine(to: CGPoint(x: visMaxX, y: 0))
        }
        // Y axis (vertical, x=0)
        if visMinX <= 0 && visMaxX >= 0 {
            axisPath.move(to: CGPoint(x: 0, y: visMinY))
            axisPath.addLine(to: CGPoint(x: 0, y: visMaxY))
        }
        
        let axisShape = SKShapeNode(path: axisPath)
        axisShape.strokeColor = axisColor
        axisShape.lineWidth = 2 * zoom
        container.addChild(axisShape)
        
        addChild(container)
        gridNode = container
    }
    
    @objc private func toggleGrid() {
        showGrid.toggle()
        if showGrid {
            updateGrid()
        } else {
            gridNode?.removeFromParent()
            gridNode = nil
        }
    }
    
    @objc private func toggleGridLayer() {
        gridAboveSprites.toggle()
        if showGrid { updateGrid() }
    }
    
    // MARK: - Index Rebuild
    
    private func rebuildNodeIndex() {
        nodeToIndex.removeAll(keepingCapacity: true)
        for i in sprites.indices {
            nodeToIndex[sprites[i].node] = i
        }
    }
    
    // MARK: - Texture Cache
    
    private func cachedTexture(imageName: String, isAsset: Bool) -> SKTexture? {
        if let cached = textureCache[imageName] {
            return cached
        }
        let texture: SKTexture
        if isAsset {
            texture = SKTexture(imageNamed: imageName)
        } else {
            let fileURL = appSupportDir.appendingPathComponent(imageName)
            guard let image = NSImage(contentsOf: fileURL) else { return nil }
            texture = SKTexture(image: image)
        }
        textureCache[imageName] = texture
        return texture
    }
    
    private func makeBouncingSprite(node: SKSpriteNode, velocity: CGVector, imageName: String, isAsset: Bool, bounds: CGRect, animationType: AnimationType = .bouncing, oscillatingRotation: Bool = false) -> BouncingSprite {
        BouncingSprite(
            node: node,
            velocity: velocity,
            imageName: imageName,
            isAsset: isAsset,
            halfW: node.size.width / 2,
            halfH: node.size.height / 2,
            movingRight: velocity.dx > 0,
            bounds: bounds,
            animationType: animationType,
            oscillatingRotation: oscillatingRotation,
            animTime: 0
        )
    }
    
    private func defaultBounds(around position: CGPoint) -> CGRect {
        CGRect(x: position.x - 400, y: position.y - 300, width: 800, height: 600)
    }
    
    // MARK: - Scene Lifecycle
    
    override func didMove(to view: SKView) {
        backgroundColor = .black
        
        // Setup camera
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        
        if !loadScene() {
            addRobot()
        }
    }
    
    private func addRobot() {
        guard let texture = cachedTexture(imageName: "robot", isAsset: true) else { return }
        let robot = SKSpriteNode(texture: texture)
        let targetHeight: CGFloat = 100
        let scale = targetHeight / robot.size.height
        robot.setScale(scale)
        let pos = CGPoint(x: size.width / 2, y: size.height / 2)
        robot.position = pos
        addChild(robot)
        
        let vel = CGVector(dx: 150, dy: 100)
        let bounds = defaultBounds(around: pos)
        sprites.append(makeBouncingSprite(node: robot, velocity: vel, imageName: "robot", isAsset: true, bounds: bounds))
        rebuildNodeIndex()
    }
    
    // MARK: - Update Loop
    
    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if lastUpdateTime == 0 {
            dt = 0
        } else {
            dt = CGFloat(currentTime - lastUpdateTime)
        }
        lastUpdateTime = currentTime
        
        // Apply camera inertia
        if abs(panVelocity.dx) > 0.5 || abs(panVelocity.dy) > 0.5 {
            cameraNode.position.x += panVelocity.dx
            cameraNode.position.y += panVelocity.dy
            if trackedNode != nil {
                trackingOffset.dx += panVelocity.dx
                trackingOffset.dy += panVelocity.dy
            }
            panVelocity.dx *= panFriction
            panVelocity.dy *= panFriction
        } else {
            panVelocity = .zero
        }
        
        guard !isEditing, dt > 0, dt < 1 else { return }
        
        sprites.withUnsafeMutableBufferPointer { buffer in
            for i in buffer.indices {
                let node = buffer[i].node
                let halfW = buffer[i].halfW
                let halfH = buffer[i].halfH
                let b = buffer[i].bounds
                var vel = buffer[i].velocity
                
                switch buffer[i].animationType {
                case .fixed:
                    buffer[i].animTime += dt
                    
                case .bouncing:
                    var posX = node.position.x + vel.dx * dt
                    var posY = node.position.y + vel.dy * dt
                    if posX <= b.minX + halfW { posX = b.minX + halfW; vel.dx = abs(vel.dx) }
                    else if posX >= b.maxX - halfW { posX = b.maxX - halfW; vel.dx = -abs(vel.dx) }
                    if posY <= b.minY + halfH { posY = b.minY + halfH; vel.dy = abs(vel.dy) }
                    else if posY >= b.maxY - halfH { posY = b.maxY - halfH; vel.dy = -abs(vel.dy) }
                    node.position = CGPoint(x: posX, y: posY)
                    buffer[i].velocity = vel
                    let nowRight = vel.dx > 0
                    if nowRight != buffer[i].movingRight {
                        buffer[i].movingRight = nowRight
                        node.xScale = nowRight ? abs(node.xScale) : -abs(node.xScale)
                    }
                    
                case .horizontalBounce:
                    var posX = node.position.x + vel.dx * dt
                    if posX <= b.minX + halfW { posX = b.minX + halfW; vel.dx = abs(vel.dx) }
                    else if posX >= b.maxX - halfW { posX = b.maxX - halfW; vel.dx = -abs(vel.dx) }
                    node.position.x = posX
                    buffer[i].velocity = vel
                    let nowRight = vel.dx > 0
                    if nowRight != buffer[i].movingRight {
                        buffer[i].movingRight = nowRight
                        node.xScale = nowRight ? abs(node.xScale) : -abs(node.xScale)
                    }
                    
                case .verticalBounce:
                    var posY = node.position.y + vel.dy * dt
                    if posY <= b.minY + halfH { posY = b.minY + halfH; vel.dy = abs(vel.dy) }
                    else if posY >= b.maxY - halfH { posY = b.maxY - halfH; vel.dy = -abs(vel.dy) }
                    node.position.y = posY
                    buffer[i].velocity = vel
                    
                case .ellipse:
                    let speed = hypot(vel.dx, vel.dy)
                    let cx = b.midX, cy = b.midY
                    let rx = max(0, (b.width / 2) - halfW)
                    let ry = max(0, (b.height / 2) - halfH)
                    let perimeter = CGFloat.pi * (3 * (rx + ry) - sqrt((3 * rx + ry) * (rx + 3 * ry)))
                    let angularSpeed = perimeter > 0 ? (speed / perimeter) * 2 * .pi : 1.0
                    buffer[i].animTime += dt * angularSpeed
                    let t = buffer[i].animTime
                    node.position = CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))
                    
                case .circular:
                    let speed = hypot(vel.dx, vel.dy)
                    let cx = b.midX, cy = b.midY
                    let rx = max(0, (b.width / 2) - halfW)
                    let ry = max(0, (b.height / 2) - halfH)
                    let r = min(rx, ry)
                    let circumference = 2 * CGFloat.pi * r
                    let angularSpeed = circumference > 0 ? (speed / circumference) * 2 * .pi : 1.0
                    buffer[i].animTime += dt * angularSpeed
                    let t = buffer[i].animTime
                    node.position = CGPoint(x: cx + r * cos(t), y: cy + r * sin(t))
                    
                case .sinusoidal:
                    let speed = hypot(vel.dx, vel.dy)
                    let cx = b.midX, cy = b.midY
                    let rx = max(0, (b.width / 2) - halfW)
                    let ry = max(0, (b.height / 2) - halfH)
                    buffer[i].animTime += dt * speed * 0.01
                    let t = buffer[i].animTime
                    let phase = t.truncatingRemainder(dividingBy: 2 * .pi) / (2 * .pi)
                    let linearPhase = phase < 0.5 ? phase * 2 : 2.0 - phase * 2
                    node.position = CGPoint(
                        x: (b.minX + halfW) + linearPhase * rx * 2,
                        y: cy + ry * sin(t)
                    )
                }
                
                // Oscillating rotation (additive, on top of any translation)
                if buffer[i].oscillatingRotation {
                    let speed = hypot(vel.dx, vel.dy)
                    let rotSpeed = max(1.0, speed * 0.02)
                    node.zRotation = CGFloat.pi / 6 * sin(buffer[i].animTime * rotSpeed)
                }
            }
        }
        
        // Camera tracking: follow the tracked sprite
        if let tracked = trackedNode {
            cameraNode.position = CGPoint(
                x: tracked.position.x + trackingOffset.dx,
                y: tracked.position.y + trackingOffset.dy
            )
        }
        
        if showGrid { updateGrid() }
    }
    
    // MARK: - Scroll Pan (called from ViewController scroll monitor)
    
    func handleScrollDelta(dx: CGFloat, dy: CGFloat) {
        let zoomScale = cameraNode.xScale
        let offsetDx = -dx * zoomScale
        let offsetDy = dy * zoomScale
        // Scroll delta: positive dx = scroll right = move camera left
        cameraNode.position.x += offsetDx
        // Scroll delta: positive dy = scroll up = move camera up (SpriteKit Y is up)
        cameraNode.position.y += offsetDy
        
        // Update tracking offset so camera keeps following from new position
        if trackedNode != nil {
            trackingOffset.dx += offsetDx
            trackingOffset.dy += offsetDy
        }
        
        // Accumulate velocity for inertia
        panVelocity = CGVector(dx: offsetDx, dy: offsetDy)
        
        if showGrid { updateGrid() }
    }
    
    func handleScrollEnded() {
        // panVelocity is already set from the last scroll delta — inertia kicks in via update()
    }
    
    // MARK: - Magnify (Zoom)
    
    func handleMagnification(_ magnification: CGFloat) {
        let newScale = cameraNode.xScale / (1.0 + magnification * 0.08)
        let clamped = max(0.1, min(20.0, newScale))
        cameraNode.setScale(clamped)
        if showGrid { updateGrid() }
    }
    
    // MARK: - Zoom to Fit
    
    @objc private func togglePerformanceDisplay() {
        guard let skView = self.view as? SKView else { return }
        let show = !skView.showsFPS
        skView.showsFPS = show
        skView.showsNodeCount = show
        skView.showsDrawCount = show
    }
    
    @objc private func zoomToFitAll() {
        guard !sprites.isEmpty, let view = self.view else { return }
        
        // Compute bounding box of all sprites
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for entry in sprites {
            let pos = entry.node.position
            minX = min(minX, pos.x - entry.halfW)
            minY = min(minY, pos.y - entry.halfH)
            maxX = max(maxX, pos.x + entry.halfW)
            maxY = max(maxY, pos.y + entry.halfH)
        }
        
        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        guard contentWidth > 0, contentHeight > 0 else { return }
        
        // Center camera on content
        cameraNode.position = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        
        // Scale to fit with a small margin
        let margin: CGFloat = 1.1
        let scaleX = (contentWidth * margin) / view.bounds.width
        let scaleY = (contentHeight * margin) / view.bounds.height
        let newScale = max(scaleX, scaleY)
        let clamped = max(0.1, min(20.0, newScale))
        cameraNode.setScale(clamped)
        
        panVelocity = .zero
    }
    
    // MARK: - Context Menu
    
    override func rightMouseDown(with event: NSEvent) {
        guard let view = self.view else { return }
        
        rightClickLocation = event.location(in: self)
        
        let menu = NSMenu(title: "Sprites")
        
        let loadItem = NSMenuItem(title: "Charger des sprites...", action: #selector(loadNewSprites), keyEquivalent: "")
        loadItem.target = self
        menu.addItem(loadItem)
        
        menu.addItem(.separator())
        
        let editTitle = isEditing ? "Reprendre l'animation" : "Mode édition"
        let editItem = NSMenuItem(title: editTitle, action: #selector(toggleEditMode), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        
        menu.addItem(.separator())
        
        let saveItem = NSMenuItem(title: "Sauvegarder la scène", action: #selector(saveScene), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)
        
        let restoreItem = NSMenuItem(title: "Charger une scène...", action: #selector(loadSceneFromFile), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)
        
        menu.addItem(.separator())
        
        let zoomFitItem = NSMenuItem(title: "Voir tous les sprites", action: #selector(zoomToFitAll), keyEquivalent: "")
        zoomFitItem.target = self
        menu.addItem(zoomFitItem)
        
        let skView = self.view as? SKView
        let perfTitle = (skView?.showsFPS ?? false) ? "Masquer les performances" : "Afficher les performances"
        let perfItem = NSMenuItem(title: perfTitle, action: #selector(togglePerformanceDisplay), keyEquivalent: "")
        perfItem.target = self
        menu.addItem(perfItem)
        
        let gridTitle = showGrid ? "Masquer le quadrillage" : "Afficher le quadrillage"
        let gridItem = NSMenuItem(title: gridTitle, action: #selector(toggleGrid), keyEquivalent: "")
        gridItem.target = self
        menu.addItem(gridItem)
        
        if showGrid {
            let layerTitle = gridAboveSprites ? "Quadrillage derrière les sprites" : "Quadrillage devant les sprites"
            let layerItem = NSMenuItem(title: layerTitle, action: #selector(toggleGridLayer), keyEquivalent: "")
            layerItem.target = self
            menu.addItem(layerItem)
        }
        
        if isEditing {
            menu.addItem(.separator())
            
            let selectAllItem = NSMenuItem(title: "Tout sélectionner", action: #selector(selectAllSprites), keyEquivalent: "")
            selectAllItem.target = self
            menu.addItem(selectAllItem)
            
            if !selectedSprites.isEmpty {
                // Animation type submenu
                let animMenu = NSMenu(title: "Animation")
                for animType in AnimationType.allCases {
                    let item = NSMenuItem(title: animType.displayName, action: #selector(setAnimationType(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = animType.rawValue
                    let allMatch = selectedSprites.allSatisfy { node in
                        guard let idx = nodeToIndex[node] else { return false }
                        return sprites[idx].animationType == animType
                    }
                    item.state = allMatch ? .on : .off
                    animMenu.addItem(item)
                }
                animMenu.addItem(.separator())
                let oscItem = NSMenuItem(title: "Rotation oscillante", action: #selector(toggleOscillatingRotation), keyEquivalent: "")
                oscItem.target = self
                let allOsc = selectedSprites.allSatisfy { node in
                    guard let idx = nodeToIndex[node] else { return false }
                    return sprites[idx].oscillatingRotation
                }
                oscItem.state = allOsc ? .on : .off
                animMenu.addItem(oscItem)
                
                let animSubmenuItem = NSMenuItem(title: "Type d'animation", action: nil, keyEquivalent: "")
                animSubmenuItem.submenu = animMenu
                menu.addItem(animSubmenuItem)
                
                // Z-order submenu
                let zOrderMenu = NSMenu(title: "Ordre")
                let bringFrontItem = NSMenuItem(title: "Passer en avant-plan", action: #selector(bringSelectionToFront), keyEquivalent: "")
                bringFrontItem.target = self
                zOrderMenu.addItem(bringFrontItem)
                let sendBackItem = NSMenuItem(title: "Passer en arrière-plan", action: #selector(sendSelectionToBack), keyEquivalent: "")
                sendBackItem.target = self
                zOrderMenu.addItem(sendBackItem)
                let zOrderSubmenuItem = NSMenuItem(title: "Ordre d'affichage", action: nil, keyEquivalent: "")
                zOrderSubmenuItem.submenu = zOrderMenu
                menu.addItem(zOrderSubmenuItem)
                
                // Camera tracking
                if selectedSprites.count == 1, let node = selectedSprites.first {
                    let isTracked = trackedNode == node
                    let trackTitle = isTracked ? "Désactiver le suivi caméra" : "Activer le suivi caméra"
                    let trackItem = NSMenuItem(title: trackTitle, action: #selector(toggleCameraTrackingOnSelected), keyEquivalent: "")
                    trackItem.target = self
                    trackItem.state = isTracked ? .on : .off
                    menu.addItem(trackItem)
                }
                
                // Scale submenu
                let scaleMenu = NSMenu(title: "Échelle")
                for factor in [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0] {
                    let pct = Int(factor * 100)
                    let item = NSMenuItem(title: "\(pct)%", action: #selector(setSelectionScale(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = factor
                    scaleMenu.addItem(item)
                }
                scaleMenu.addItem(.separator())
                let scaleUpItem = NSMenuItem(title: "Agrandir ×1.5", action: #selector(scaleSelectionUp), keyEquivalent: "")
                scaleUpItem.target = self
                scaleMenu.addItem(scaleUpItem)
                let scaleDownItem = NSMenuItem(title: "Réduire ×0.67", action: #selector(scaleSelectionDown), keyEquivalent: "")
                scaleDownItem.target = self
                scaleMenu.addItem(scaleDownItem)
                let scaleSubmenuItem = NSMenuItem(title: "Échelle", action: nil, keyEquivalent: "")
                scaleSubmenuItem.submenu = scaleMenu
                menu.addItem(scaleSubmenuItem)
                
                // Speed submenu
                let speedMenu = NSMenu(title: "Vitesse")
                for factor in [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0] {
                    let label: String
                    if factor == 1.0 { label = "×1 (normale)" }
                    else { label = "×\(factor == floor(factor) ? String(Int(factor)) : String(factor))" }
                    let item = NSMenuItem(title: label, action: #selector(setSelectionSpeed(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = factor
                    speedMenu.addItem(item)
                }
                speedMenu.addItem(.separator())
                let speedUpItem = NSMenuItem(title: "Accélérer ×2", action: #selector(speedSelectionUp), keyEquivalent: "")
                speedUpItem.target = self
                speedMenu.addItem(speedUpItem)
                let speedDownItem = NSMenuItem(title: "Ralentir ÷2", action: #selector(speedSelectionDown), keyEquivalent: "")
                speedDownItem.target = self
                speedMenu.addItem(speedDownItem)
                let speedSubmenuItem = NSMenuItem(title: "Vitesse", action: nil, keyEquivalent: "")
                speedSubmenuItem.submenu = speedMenu
                menu.addItem(speedSubmenuItem)
                
                menu.addItem(.separator())
                
                let randomizeItem = NSMenuItem(title: "Position & vitesse aléatoires (\(selectedSprites.count))", action: #selector(randomizeSelected), keyEquivalent: "")
                randomizeItem.target = self
                menu.addItem(randomizeItem)
                
                let deleteItem = NSMenuItem(title: "Supprimer la sélection (\(selectedSprites.count))", action: #selector(deleteSelected), keyEquivalent: "")
                deleteItem.target = self
                menu.addItem(deleteItem)
            }
        }
        
        let screenPoint = event.locationInWindow
        let viewPoint = view.convert(screenPoint, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: view)
    }
    
    // MARK: - Animation Type Actions
    
    @objc private func setAnimationType(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let animType = AnimationType(rawValue: rawValue) else { return }
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            sprites[idx].animationType = animType
            sprites[idx].animTime = 0
            if animType == .fixed {
                node.zRotation = 0
            }
        }
    }
    
    @objc private func toggleOscillatingRotation() {
        let allOn = selectedSprites.allSatisfy { node in
            guard let idx = nodeToIndex[node] else { return false }
            return sprites[idx].oscillatingRotation
        }
        let newValue = !allOn
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            sprites[idx].oscillatingRotation = newValue
            if !newValue { node.zRotation = 0 }
        }
    }
    
    // MARK: - Z-Order Actions
    
    @objc private func bringSelectionToFront() {
        let maxZ = sprites.map { $0.node.zPosition }.max() ?? 0
        for node in selectedSprites {
            node.zPosition = maxZ + 1
        }
    }
    
    @objc private func sendSelectionToBack() {
        let minZ = sprites.map { $0.node.zPosition }.min() ?? 0
        for node in selectedSprites {
            node.zPosition = minZ - 1
        }
    }
    
    // MARK: - Camera Tracking Action
    
    @objc private func toggleCameraTrackingOnSelected() {
        guard selectedSprites.count == 1, let node = selectedSprites.first else { return }
        if trackedNode == node {
            trackedNode = nil
        } else {
            trackedNode = node
            trackingOffset = CGVector(
                dx: cameraNode.position.x - node.position.x,
                dy: cameraNode.position.y - node.position.y
            )
        }
    }
    
    // MARK: - Scale Actions
    
    @objc private func setSelectionScale(_ sender: NSMenuItem) {
        guard let factor = sender.representedObject as? Double else { return }
        let scale = CGFloat(factor)
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            let sign: CGFloat = node.xScale < 0 ? -1 : 1
            node.xScale = sign * scale
            node.yScale = scale
            sprites[idx].halfW = node.size.width * scale / 2
            sprites[idx].halfH = node.size.height * scale / 2
        }
    }
    
    @objc private func scaleSelectionUp() {
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            let sign: CGFloat = node.xScale < 0 ? -1 : 1
            let newScale = abs(node.yScale) * 1.5
            node.xScale = sign * newScale
            node.yScale = newScale
            sprites[idx].halfW = node.size.width * newScale / 2
            sprites[idx].halfH = node.size.height * newScale / 2
        }
    }
    
    @objc private func scaleSelectionDown() {
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            let sign: CGFloat = node.xScale < 0 ? -1 : 1
            let newScale = abs(node.yScale) * 0.67
            node.xScale = sign * newScale
            node.yScale = newScale
            sprites[idx].halfW = node.size.width * newScale / 2
            sprites[idx].halfH = node.size.height * newScale / 2
        }
    }
    
    // MARK: - Speed Actions
    
    @objc private func setSelectionSpeed(_ sender: NSMenuItem) {
        guard let factor = sender.representedObject as? Double else { return }
        let multiplier = CGFloat(factor)
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            let vel = sprites[idx].velocity
            let currentSpeed = hypot(vel.dx, vel.dy)
            guard currentSpeed > 0 else { continue }
            let ratio = (140.0 * multiplier) / currentSpeed
            sprites[idx].velocity = CGVector(dx: vel.dx * ratio, dy: vel.dy * ratio)
        }
    }
    
    @objc private func speedSelectionUp() {
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            sprites[idx].velocity.dx *= 2
            sprites[idx].velocity.dy *= 2
        }
    }
    
    @objc private func speedSelectionDown() {
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            sprites[idx].velocity.dx *= 0.5
            sprites[idx].velocity.dy *= 0.5
        }
    }
    
    // MARK: - Load Sprites
    
    @objc private func loadNewSprites() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Choisir des images de sprites"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK else { return }
            
            DispatchQueue.main.async {
                for url in panel.urls {
                    self.addSpriteFromFile(url: url)
                }
            }
        }
    }
    
    private func addSpriteFromFile(url: URL, position: CGPoint? = nil, velocity: CGVector? = nil, scale: CGFloat? = nil, bounds: CGRect? = nil) {
        let savedName = copyToAppSupport(url: url)
        let imageName = savedName ?? url.lastPathComponent
        
        let texture: SKTexture
        if let cached = textureCache[imageName] {
            texture = cached
        } else {
            guard let image = NSImage(contentsOf: url) else { return }
            let t = SKTexture(image: image)
            textureCache[imageName] = t
            texture = t
        }
        
        let sprite = SKSpriteNode(texture: texture)
        
        let targetHeight: CGFloat = 100
        let spriteScale = scale ?? (targetHeight / sprite.size.height)
        sprite.setScale(spriteScale)
        
        // Random position within visible screen area
        let camPos = cameraNode.position
        let zoom = cameraNode.xScale
        let viewHalfW = (self.view?.bounds.width ?? 800) * zoom / 2
        let viewHalfH = (self.view?.bounds.height ?? 600) * zoom / 2
        let margin: CGFloat = 50 * zoom
        let minX = camPos.x - viewHalfW + margin
        let maxX = camPos.x + viewHalfW - margin
        let minY = camPos.y - viewHalfH + margin
        let maxY = camPos.y + viewHalfH - margin
        let pos = position ?? CGPoint(
            x: minX < maxX ? CGFloat.random(in: minX...maxX) : camPos.x,
            y: minY < maxY ? CGFloat.random(in: minY...maxY) : camPos.y
        )
        sprite.position = pos
        addChild(sprite)
        
        let vel = velocity ?? CGVector(
            dx: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1),
            dy: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1)
        )
        
        let spriteBounds = bounds ?? defaultBounds(around: pos)
        sprites.append(makeBouncingSprite(node: sprite, velocity: vel, imageName: imageName, isAsset: false, bounds: spriteBounds))
        rebuildNodeIndex()
    }
    
    // MARK: - Edit Mode
    
    @objc private func toggleEditMode() {
        isEditing.toggle()
        trackedNode = nil
        
        if isEditing {
            updateBoundsVisuals()
        } else {
            clearSelection()
            removeBoundsVisuals()
            lastUpdateTime = 0
        }
    }
    
    @objc private func selectAllSprites() {
        clearSelection(updateVisuals: false)
        for entry in sprites {
            selectSprite(entry.node, updateVisuals: false)
        }
        updateGroupSelectionVisual()
        if isEditing { updateBoundsVisuals() }
    }
    
    @objc private func randomizeSelected() {
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            
            let b = sprites[idx].bounds
            let halfW = sprites[idx].halfW
            let halfH = sprites[idx].halfH
            
            let minX = b.minX + halfW
            let maxX = b.maxX - halfW
            let minY = b.minY + halfH
            let maxY = b.maxY - halfH
            
            node.position = CGPoint(
                x: minX < maxX ? CGFloat.random(in: minX...maxX) : b.midX,
                y: minY < maxY ? CGFloat.random(in: minY...maxY) : b.midY
            )
            
            sprites[idx].velocity = CGVector(
                dx: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1),
                dy: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1)
            )
        }
        rebuildSelectionBBox()
        updateGroupSelectionVisual()
    }
    
    // MARK: - Hit Test Helper
    
    /// Returns the topmost sprite at the given location.
    /// Prefers highest zPosition, then smallest area to avoid selecting large backgrounds.
    private func topmostSprite(at location: CGPoint) -> BouncingSprite? {
        var best: BouncingSprite?
        var bestZ: CGFloat = -.greatestFiniteMagnitude
        var bestArea: CGFloat = .greatestFiniteMagnitude
        for sprite in sprites {
            guard sprite.node.contains(location) else { continue }
            let z = sprite.node.zPosition
            let area = sprite.halfW * sprite.halfH
            if z > bestZ || (z == bestZ && area < bestArea) {
                best = sprite
                bestZ = z
                bestArea = area
            }
        }
        return best
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        if !isEditing {
            let location = event.location(in: self)
            if let clicked = topmostSprite(at: location) {
                // Track this sprite: camera follows it, keeping it at click position on screen
                trackedNode = clicked.node
                trackingOffset = CGVector(
                    dx: cameraNode.position.x - clicked.node.position.x,
                    dy: cameraNode.position.y - clicked.node.position.y
                )
                panVelocity = .zero
            } else {
                trackedNode = nil
            }
            return
        }
        
        let location = event.location(in: self)
        let shift = event.modifierFlags.contains(.shift)
        
        // 1. If there's a selection and we click inside it, drag the group (fast path)
        if !shift && !selectedSprites.isEmpty && cachedSelectionBBox.contains(location) {
            isDraggingSprites = true
            dragLastPoint = location
            saveDragStartPositions()
            // Change color to indicate active drag
            groupSelectionNode?.strokeColor = .green
            groupSelectionNode?.fillColor = NSColor.green.withAlphaComponent(0.08)
            return
        }
        
        // 2. Check if clicking on a handle (only when bounds are visible, i.e. 1 selected)
        if selectedSprites.count == 1, let (spriteIdx, side) = handleHitTest(at: location) {
            isDraggingHandle = true
            activeHandleSpriteIndex = spriteIdx
            activeHandleSide = side
            return
        }
        
        // 3. Check if clicking on an individual sprite (topmost first)
        let clickedNode = topmostSprite(at: location)?.node
        
        if let node = clickedNode {
            if shift {
                if selectedSprites.contains(node) {
                    deselectSprite(node)
                } else {
                    selectSprite(node)
                }
            } else {
                clearSelection()
                selectSprite(node)
            }
            isDraggingSprites = true
            dragLastPoint = location
            saveDragStartPositions()
        } else {
            // 3. Start rectangle selection
            if !shift {
                clearSelection()
            }
            selectionOrigin = location
            isDraggingSelection = true
            isDraggingSprites = false
            
            let rect = SKShapeNode(rect: CGRect(origin: location, size: .zero))
            rect.strokeColor = .cyan
            rect.lineWidth = 1 * cameraNode.xScale
            rect.fillColor = NSColor.cyan.withAlphaComponent(0.1)
            rect.zPosition = 1000
            selectionRect = rect
            addChild(rect)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isEditing else { return }
        
        let current = event.location(in: self)
        
        // Handle dragging
        if isDraggingHandle, activeHandleSpriteIndex >= 0, activeHandleSpriteIndex < sprites.count {
            var b = sprites[activeHandleSpriteIndex].bounds
            switch activeHandleSide {
            case .left:   b.size.width += b.origin.x - current.x; b.origin.x = current.x
            case .right:  b.size.width = current.x - b.origin.x
            case .bottom: b.size.height += b.origin.y - current.y; b.origin.y = current.y
            case .top:    b.size.height = current.y - b.origin.y
            }
            // Minimum size
            if b.size.width < 50 { b.size.width = 50 }
            if b.size.height < 50 { b.size.height = 50 }
            sprites[activeHandleSpriteIndex].bounds = b
            updateBoundsVisuals()
            return
        }
        
        // Sprite dragging (move sprite + its bounds together)
        if isDraggingSprites {
            let dx = current.x - dragLastPoint.x
            let dy = current.y - dragLastPoint.y
            for node in selectedSprites {
                node.position.x += dx
                node.position.y += dy
                if let idx = nodeToIndex[node] {
                    sprites[idx].bounds = sprites[idx].bounds.offsetBy(dx: dx, dy: dy)
                }
            }
            cachedSelectionBBox = cachedSelectionBBox.offsetBy(dx: dx, dy: dy)
            groupSelectionNode?.position.x += dx
            groupSelectionNode?.position.y += dy
            dragLastPoint = current
            return
        }
        
        // Selection rectangle
        guard isDraggingSelection else { return }
        
        let origin = selectionOrigin
        let x = min(origin.x, current.x)
        let y = min(origin.y, current.y)
        let w = abs(current.x - origin.x)
        let h = abs(current.y - origin.y)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        
        selectionRect?.removeFromParent()
        let shape = SKShapeNode(rect: rect)
        shape.strokeColor = .cyan
        shape.lineWidth = 1 * cameraNode.xScale
        shape.fillColor = NSColor.cyan.withAlphaComponent(0.1)
        shape.zPosition = 1000
        selectionRect = shape
        addChild(shape)
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }
        
        if isDraggingHandle {
            isDraggingHandle = false
            activeHandleSpriteIndex = -1
            return
        }
        
        if isDraggingSprites {
            isDraggingSprites = false
            // Push undo if sprites actually moved
            if let first = dragStartPositions.first,
               first.node.position != first.oldPos {
                undoStack.append(.move(dragStartPositions))
                redoStack.removeAll()
            }
            dragStartPositions.removeAll()
            rebuildSelectionBBox()
            updateGroupSelectionVisual()
            updateBoundsVisuals()
            return
        }
        
        guard isDraggingSelection else { return }
        isDraggingSelection = false
        
        let current = event.location(in: self)
        let origin = selectionOrigin
        let shift = event.modifierFlags.contains(.shift)
        
        let x = min(origin.x, current.x)
        let y = min(origin.y, current.y)
        let w = abs(current.x - origin.x)
        let h = abs(current.y - origin.y)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        
        selectionRect?.removeFromParent()
        selectionRect = nil
        
        guard w > 3 || h > 3 else { return }
        
        if !shift {
            clearSelection()
        }
        
        for entry in sprites {
            if rect.contains(entry.node.position) {
                selectSprite(entry.node, updateVisuals: false)
            }
        }
        updateGroupSelectionVisual()
        if isEditing { updateBoundsVisuals() }
    }
    
    // MARK: - Handle Hit Test
    
    private func handleHitTest(at point: CGPoint) -> (Int, HandleSide)? {
        let hitRadius: CGFloat = handleSize * cameraNode.xScale
        
        for i in sprites.indices {
            guard selectedSprites.contains(sprites[i].node) else { continue }
            let b = sprites[i].bounds
            
            let sides: [(CGPoint, HandleSide)] = [
                (CGPoint(x: b.minX, y: b.midY), .left),
                (CGPoint(x: b.maxX, y: b.midY), .right),
                (CGPoint(x: b.midX, y: b.minY), .bottom),
                (CGPoint(x: b.midX, y: b.maxY), .top),
            ]
            
            for (handlePos, side) in sides {
                if hypot(point.x - handlePos.x, point.y - handlePos.y) < hitRadius {
                    return (i, side)
                }
            }
        }
        return nil
    }
    
    // MARK: - Bounds Visuals
    
    private func removeBoundsVisuals() {
        children.filter { ($0.name ?? "").hasPrefix(boundsRectPrefix) || ($0.name ?? "").hasPrefix(handlePrefix) }
            .forEach { $0.removeFromParent() }
    }
    
    private func updateBoundsVisuals() {
        removeBoundsVisuals()
        
        guard isEditing else { return }
        
        // Only show individual bounds for a single selected sprite
        guard selectedSprites.count == 1 else { return }
        
        let zoom = cameraNode.xScale
        
        for i in sprites.indices {
            guard selectedSprites.contains(sprites[i].node) else { continue }
            let b = sprites[i].bounds
            
            // Draw bounds rectangle
            let rectNode = SKShapeNode(rect: b)
            rectNode.strokeColor = .orange
            rectNode.lineWidth = 1.5 * zoom
            rectNode.fillColor = .clear
            rectNode.zPosition = 999
            rectNode.name = "\(boundsRectPrefix)\(i)"
            // Dashed line
            let pattern: [CGFloat] = [8 * zoom, 4 * zoom]
            rectNode.path = {
                let path = CGMutablePath()
                path.addRect(b)
                return path.copy(dashingWithPhase: 0, lengths: pattern)
            }()
            addChild(rectNode)
            
            // Draw 4 handles
            let hSize = handleSize * zoom
            let sides: [(CGPoint, String)] = [
                (CGPoint(x: b.minX, y: b.midY), "\(handlePrefix)left_\(i)"),
                (CGPoint(x: b.maxX, y: b.midY), "\(handlePrefix)right_\(i)"),
                (CGPoint(x: b.midX, y: b.minY), "\(handlePrefix)bottom_\(i)"),
                (CGPoint(x: b.midX, y: b.maxY), "\(handlePrefix)top_\(i)"),
            ]
            
            for (pos, name) in sides {
                let handle = SKShapeNode(rectOf: CGSize(width: hSize, height: hSize))
                handle.fillColor = .orange
                handle.strokeColor = .white
                handle.lineWidth = 1 * zoom
                handle.position = pos
                handle.zPosition = 1001
                handle.name = name
                addChild(handle)
            }
        }
    }
    
    private func rebuildSelectionBBox() {
        guard !selectedSprites.isEmpty else {
            cachedSelectionBBox = .null
            return
        }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for node in selectedSprites {
            let pos = node.position
            let hw = node.size.width / 2
            let hh = node.size.height / 2
            minX = min(minX, pos.x - hw)
            minY = min(minY, pos.y - hh)
            maxX = max(maxX, pos.x + hw)
            maxY = max(maxY, pos.y + hh)
        }
        cachedSelectionBBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func expandSelectionBBox(with node: SKSpriteNode) {
        let pos = node.position
        let hw = node.size.width / 2
        let hh = node.size.height / 2
        let nodeRect = CGRect(x: pos.x - hw, y: pos.y - hh, width: hw * 2, height: hh * 2)
        if cachedSelectionBBox.isNull {
            cachedSelectionBBox = nodeRect
        } else {
            cachedSelectionBBox = cachedSelectionBBox.union(nodeRect)
        }
    }
    
    // MARK: - Selection Helpers
    
    private func selectSprite(_ node: SKSpriteNode, updateVisuals: Bool = true) {
        selectedSprites.insert(node)
        expandSelectionBBox(with: node)
        if updateVisuals { updateGroupSelectionVisual() }
        if updateVisuals && isEditing { updateBoundsVisuals() }
    }
    
    private func deselectSprite(_ node: SKSpriteNode, updateVisuals: Bool = true) {
        selectedSprites.remove(node)
        rebuildSelectionBBox()
        if updateVisuals { updateGroupSelectionVisual() }
        if updateVisuals && isEditing { updateBoundsVisuals() }
    }
    
    private func clearSelection(updateVisuals: Bool = true) {
        selectedSprites.removeAll()
        cachedSelectionBBox = .null
        removeGroupSelectionVisual()
        if updateVisuals && isEditing { updateBoundsVisuals() }
    }
    
    private func updateGroupSelectionVisual() {
        removeGroupSelectionVisual()
        guard !selectedSprites.isEmpty, !cachedSelectionBBox.isNull else { return }
        
        let zoom = cameraNode.xScale
        let shape = SKShapeNode(rect: cachedSelectionBBox)
        shape.strokeColor = .cyan
        shape.lineWidth = 2 * zoom
        shape.fillColor = NSColor.cyan.withAlphaComponent(0.08)
        shape.zPosition = 998
        shape.name = groupSelectionName
        addChild(shape)
        groupSelectionNode = shape
    }
    
    private func removeGroupSelectionVisual() {
        groupSelectionNode?.removeFromParent()
        groupSelectionNode = nil
    }
    
    // MARK: - Delete & Undo
    
    @objc private func deleteSelected() {
        guard !selectedSprites.isEmpty else { return }
        
        var deleted: [BouncingSprite] = []
        var kept: [BouncingSprite] = []
        
        for entry in sprites {
            if selectedSprites.contains(entry.node) {
                deleted.append(entry)
                entry.node.removeFromParent()
            } else {
                kept.append(entry)
            }
        }
        
        sprites = kept
        rebuildNodeIndex()
        selectedSprites.removeAll()
        cachedSelectionBBox = .null
        removeGroupSelectionVisual()
        updateBoundsVisuals()
        
        if !deleted.isEmpty {
            undoStack.append(.delete(deleted))
            redoStack.removeAll()
        }
    }
    
    private func saveDragStartPositions() {
        dragStartPositions.removeAll()
        for node in selectedSprites {
            if let idx = nodeToIndex[node] {
                dragStartPositions.append((node: node, oldPos: node.position, oldBounds: sprites[idx].bounds))
            }
        }
    }
    
    private func undoLast() {
        guard let action = undoStack.popLast() else { return }
        
        switch action {
        case .delete(let deleted):
            for entry in deleted {
                addChild(entry.node)
                sprites.append(entry)
            }
            rebuildNodeIndex()
            redoStack.append(action)
            
        case .move(let positions):
            // Save current positions for redo
            var currentPositions: [(node: SKSpriteNode, oldPos: CGPoint, oldBounds: CGRect)] = []
            for item in positions {
                if let idx = nodeToIndex[item.node] {
                    currentPositions.append((node: item.node, oldPos: item.node.position, oldBounds: sprites[idx].bounds))
                }
            }
            redoStack.append(.move(currentPositions))
            // Restore old positions
            for item in positions {
                item.node.position = item.oldPos
                if let idx = nodeToIndex[item.node] {
                    sprites[idx].bounds = item.oldBounds
                }
            }
            rebuildSelectionBBox()
            updateGroupSelectionVisual()
        }
        updateBoundsVisuals()
    }
    
    private func redoLast() {
        guard let action = redoStack.popLast() else { return }
        
        switch action {
        case .delete(let deleted):
            // Re-delete the sprites
            let deletedNodes = Set(deleted.map { $0.node })
            for entry in deleted {
                entry.node.removeFromParent()
            }
            sprites.removeAll { deletedNodes.contains($0.node) }
            rebuildNodeIndex()
            selectedSprites.subtract(deletedNodes)
            cachedSelectionBBox = .null
            rebuildSelectionBBox()
            removeGroupSelectionVisual()
            undoStack.append(action)
            
        case .move(let positions):
            // Save current positions for undo
            var currentPositions: [(node: SKSpriteNode, oldPos: CGPoint, oldBounds: CGRect)] = []
            for item in positions {
                if let idx = nodeToIndex[item.node] {
                    currentPositions.append((node: item.node, oldPos: item.node.position, oldBounds: sprites[idx].bounds))
                }
            }
            undoStack.append(.move(currentPositions))
            // Apply redo positions
            for item in positions {
                item.node.position = item.oldPos
                if let idx = nodeToIndex[item.node] {
                    sprites[idx].bounds = item.oldBounds
                }
            }
            rebuildSelectionBBox()
            updateGroupSelectionVisual()
        }
        updateBoundsVisuals()
    }
    
    // MARK: - Keyboard
    
    override func keyDown(with event: NSEvent) {
        if isEditing {
            if event.keyCode == 51 || event.keyCode == 117 {
                deleteSelected()
                return
            }
        }
    }
    
    /// Called from ViewController's key monitor for Cmd shortcuts
    func handleCommandKey(_ key: String, shift: Bool) {
        guard isEditing else { return }
        switch key {
        case "z":
            if shift { redoLast() } else { undoLast() }
        case "y": redoLast()
        case "c": copySelection()
        case "v": pasteClipboard()
        case "d": duplicateSelection()
        case "a": selectAllSprites()
        default: break
        }
    }
    
    // MARK: - Copy / Paste / Duplicate
    
    private func copySelection() {
        guard !selectedSprites.isEmpty else { return }
        
        var centerX: CGFloat = 0
        var centerY: CGFloat = 0
        for node in selectedSprites {
            centerX += node.position.x
            centerY += node.position.y
        }
        centerX /= CGFloat(selectedSprites.count)
        centerY /= CGFloat(selectedSprites.count)
        
        clipboard.removeAll()
        for node in selectedSprites {
            guard let idx = nodeToIndex[node] else { continue }
            let entry = sprites[idx]
            clipboard.append((
                imageName: entry.imageName,
                isAsset: entry.isAsset,
                velocity: entry.velocity,
                scale: abs(node.yScale),
                offset: CGPoint(x: node.position.x - centerX, y: node.position.y - centerY),
                bounds: entry.bounds,
                animationType: entry.animationType,
                oscillatingRotation: entry.oscillatingRotation
            ))
        }
    }
    
    private func pasteClipboard() {
        guard !clipboard.isEmpty else { return }
        
        let camPos = cameraNode.position
        let centerX = camPos.x + CGFloat.random(in: -30...30)
        let centerY = camPos.y + CGFloat.random(in: -30...30)
        
        clearSelection(updateVisuals: false)
        
        for item in clipboard {
            guard let texture = cachedTexture(imageName: item.imageName, isAsset: item.isAsset) else { continue }
            
            let sprite = SKSpriteNode(texture: texture)
            sprite.setScale(item.scale)
            let newPos = CGPoint(x: centerX + item.offset.x, y: centerY + item.offset.y)
            sprite.position = newPos
            addChild(sprite)
            
            // Offset bounds to match new position
            let newBounds = item.bounds.offsetBy(dx: centerX - (item.bounds.midX - item.offset.x),
                                                  dy: centerY - (item.bounds.midY - item.offset.y))
            
            sprites.append(makeBouncingSprite(node: sprite, velocity: item.velocity, imageName: item.imageName, isAsset: item.isAsset, bounds: newBounds, animationType: item.animationType, oscillatingRotation: item.oscillatingRotation))
            selectSprite(sprite, updateVisuals: false)
        }
        rebuildNodeIndex()
        updateGroupSelectionVisual()
        if isEditing { updateBoundsVisuals() }
    }
    
    private func duplicateSelection() {
        guard !selectedSprites.isEmpty else { return }
        
        let offset: CGFloat = 20
        var newNodes: [SKSpriteNode] = []
        
        for node in selectedSprites {
            guard let entry = nodeToIndex[node].map({ sprites[$0] }) else { continue }
            guard let texture = cachedTexture(imageName: entry.imageName, isAsset: entry.isAsset) else { continue }
            
            let sprite = SKSpriteNode(texture: texture)
            sprite.setScale(abs(node.yScale))
            sprite.position = CGPoint(x: node.position.x + offset, y: node.position.y - offset)
            addChild(sprite)
            
            let newBounds = entry.bounds.offsetBy(dx: offset, dy: -offset)
            sprites.append(makeBouncingSprite(node: sprite, velocity: entry.velocity, imageName: entry.imageName, isAsset: entry.isAsset, bounds: newBounds, animationType: entry.animationType, oscillatingRotation: entry.oscillatingRotation))
            newNodes.append(sprite)
        }
        
        rebuildNodeIndex()
        clearSelection(updateVisuals: false)
        for node in newNodes {
            selectSprite(node, updateVisuals: false)
        }
        updateGroupSelectionVisual()
        if isEditing { updateBoundsVisuals() }
    }
    
    // MARK: - Persistence
    
    private var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("test fluidité", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var sceneFilePath: URL {
        appSupportDir.appendingPathComponent("scene.json")
    }
    
    private func copyToAppSupport(url: URL) -> String? {
        let fileName = UUID().uuidString + "-" + url.lastPathComponent
        let dest = appSupportDir.appendingPathComponent(fileName)
        try? FileManager.default.copyItem(at: url, to: dest)
        return fileName
    }
    
    @objc private func saveScene() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "scene.json"
        panel.title = "Sauvegarder la scène"
        panel.prompt = "Sauvegarder"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            
            DispatchQueue.main.async {
                var dataList: [SpriteData] = []
                
                for entry in self.sprites {
                    let node = entry.node
                    dataList.append(SpriteData(
                        imageName: entry.imageName,
                        isAsset: entry.isAsset,
                        posX: node.position.x,
                        posY: node.position.y,
                        velDx: entry.velocity.dx,
                        velDy: entry.velocity.dy,
                        scale: abs(node.yScale),
                        boundsX: entry.bounds.origin.x,
                        boundsY: entry.bounds.origin.y,
                        boundsW: entry.bounds.size.width,
                        boundsH: entry.bounds.size.height,
                        animationType: entry.animationType.rawValue,
                        oscillatingRotation: entry.oscillatingRotation,
                        zOrder: node.zPosition,
                        cameraTracked: self.trackedNode == node ? true : nil
                    ))
                }
                
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(dataList)
                    try data.write(to: url)
                    // Also save to app support for auto-load on next launch
                    try data.write(to: self.sceneFilePath)
                } catch {
                    print("Save error: \(error)")
                }
            }
        }
    }
    
    @discardableResult
    private func loadScene() -> Bool {
        guard FileManager.default.fileExists(atPath: sceneFilePath.path) else { return false }
        
        do {
            let data = try Data(contentsOf: sceneFilePath)
            let dataList = try JSONDecoder().decode([SpriteData].self, from: data)
            
            for entry in sprites {
                entry.node.removeFromParent()
            }
            sprites.removeAll()
            
            for spriteData in dataList {
                guard let texture = cachedTexture(imageName: spriteData.imageName, isAsset: spriteData.isAsset) else { continue }
                
                let sprite = SKSpriteNode(texture: texture)
                sprite.setScale(spriteData.scale)
                sprite.position = CGPoint(x: spriteData.posX, y: spriteData.posY)
                addChild(sprite)
                
                let vel = CGVector(dx: spriteData.velDx, dy: spriteData.velDy)
                let bounds: CGRect
                if let bx = spriteData.boundsX, let by = spriteData.boundsY, let bw = spriteData.boundsW, let bh = spriteData.boundsH {
                    bounds = CGRect(x: bx, y: by, width: bw, height: bh)
                } else {
                    bounds = defaultBounds(around: sprite.position)
                }
                let animType = spriteData.animationType.flatMap { AnimationType(rawValue: $0) } ?? .bouncing
                let oscRot = spriteData.oscillatingRotation ?? false
                sprite.zPosition = spriteData.zOrder ?? 0
                sprites.append(makeBouncingSprite(node: sprite, velocity: vel, imageName: spriteData.imageName, isAsset: spriteData.isAsset, bounds: bounds, animationType: animType, oscillatingRotation: oscRot))
                if spriteData.cameraTracked == true {
                    trackedNode = sprite
                    trackingOffset = .zero
                }
            }
            
            rebuildNodeIndex()
            return true
        } catch {
            print("Load error: \(error)")
            return false
        }
    }
    
    @objc private func loadSceneFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Charger une scène"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            
            DispatchQueue.main.async {
                do {
                    let data = try Data(contentsOf: url)
                    let dataList = try JSONDecoder().decode([SpriteData].self, from: data)
                    
                    for entry in self.sprites {
                        entry.node.removeFromParent()
                    }
                    self.sprites.removeAll()
                    self.clearSelection()
                    self.undoStack.removeAll()
                    
                    for spriteData in dataList {
                        guard let texture = self.cachedTexture(imageName: spriteData.imageName, isAsset: spriteData.isAsset) else { continue }
                        
                        let sprite = SKSpriteNode(texture: texture)
                        sprite.setScale(spriteData.scale)
                        sprite.position = CGPoint(x: spriteData.posX, y: spriteData.posY)
                        self.addChild(sprite)
                        
                        let vel = CGVector(dx: spriteData.velDx, dy: spriteData.velDy)
                        let bounds: CGRect
                        if let bx = spriteData.boundsX, let by = spriteData.boundsY, let bw = spriteData.boundsW, let bh = spriteData.boundsH {
                            bounds = CGRect(x: bx, y: by, width: bw, height: bh)
                        } else {
                            bounds = self.defaultBounds(around: sprite.position)
                        }
                        let animType = spriteData.animationType.flatMap { AnimationType(rawValue: $0) } ?? .bouncing
                        let oscRot = spriteData.oscillatingRotation ?? false
                        sprite.zPosition = spriteData.zOrder ?? 0
                        self.sprites.append(self.makeBouncingSprite(node: sprite, velocity: vel, imageName: spriteData.imageName, isAsset: spriteData.isAsset, bounds: bounds, animationType: animType, oscillatingRotation: oscRot))
                        if spriteData.cameraTracked == true {
                            self.trackedNode = sprite
                            self.trackingOffset = .zero
                        }
                    }
                    
                    self.rebuildNodeIndex()
                    self.lastUpdateTime = 0
                } catch {
                    print("Load error: \(error)")
                }
            }
        }
    }
}
