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
}

// MARK: - Handle side enum

enum HandleSide {
    case left, right, top, bottom
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
    
    // Edit mode
    private var isEditing = false
    private var selectedSprites: Set<SKSpriteNode> = []
    private var selectionRect: SKShapeNode?
    private var selectionOrigin: CGPoint = .zero
    private var isDraggingSelection = false
    private var isDraggingSprites = false
    private var dragLastPoint: CGPoint = .zero
    
    // Handle dragging
    private var isDraggingHandle = false
    private var activeHandleSide: HandleSide = .left
    private var activeHandleSpriteIndex: Int = -1
    
    // Bounds visuals
    private let boundsRectPrefix = "boundsRect_"
    private let handlePrefix = "handle_"
    private let handleSize: CGFloat = 10
    
    // Clipboard
    private var clipboard: [(imageName: String, isAsset: Bool, velocity: CGVector, scale: CGFloat, offset: CGPoint, bounds: CGRect)] = []
    
    // Undo
    private var undoStack: [[BouncingSprite]] = []
    
    // Highlight
    private let highlightName = "selectionHighlight"
    
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
    
    private func makeBouncingSprite(node: SKSpriteNode, velocity: CGVector, imageName: String, isAsset: Bool, bounds: CGRect) -> BouncingSprite {
        BouncingSprite(
            node: node,
            velocity: velocity,
            imageName: imageName,
            isAsset: isAsset,
            halfW: node.size.width / 2,
            halfH: node.size.height / 2,
            movingRight: velocity.dx > 0,
            bounds: bounds
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
            panVelocity.dx *= panFriction
            panVelocity.dy *= panFriction
        } else {
            panVelocity = .zero
        }
        
        guard !isEditing, dt > 0, dt < 1 else { return }
        
        for i in sprites.indices {
            let node = sprites[i].node
            var vel = sprites[i].velocity
            let halfW = sprites[i].halfW
            let halfH = sprites[i].halfH
            let b = sprites[i].bounds
            
            var posX = node.position.x + vel.dx * dt
            var posY = node.position.y + vel.dy * dt
            
            if posX <= b.minX + halfW {
                posX = b.minX + halfW
                vel.dx = abs(vel.dx)
            } else if posX >= b.maxX - halfW {
                posX = b.maxX - halfW
                vel.dx = -abs(vel.dx)
            }
            
            if posY <= b.minY + halfH {
                posY = b.minY + halfH
                vel.dy = abs(vel.dy)
            } else if posY >= b.maxY - halfH {
                posY = b.maxY - halfH
                vel.dy = -abs(vel.dy)
            }
            
            node.position = CGPoint(x: posX, y: posY)
            
            let nowRight = vel.dx > 0
            if nowRight != sprites[i].movingRight {
                sprites[i].movingRight = nowRight
                node.xScale = nowRight ? abs(node.xScale) : -abs(node.xScale)
            }
            
            sprites[i].velocity = vel
        }
    }
    
    // MARK: - Scroll Pan (called from ViewController scroll monitor)
    
    func handleScrollDelta(dx: CGFloat, dy: CGFloat) {
        let zoomScale = cameraNode.xScale
        // Scroll delta: positive dx = scroll right = move camera left
        cameraNode.position.x -= dx * zoomScale
        // Scroll delta: positive dy = scroll up = move camera up (SpriteKit Y is up)
        cameraNode.position.y += dy * zoomScale
        
        // Accumulate velocity for inertia
        panVelocity = CGVector(dx: -dx * zoomScale, dy: dy * zoomScale)
    }
    
    func handleScrollEnded() {
        // panVelocity is already set from the last scroll delta — inertia kicks in via update()
    }
    
    // MARK: - Magnify (Zoom)
    
    func handleMagnification(_ magnification: CGFloat) {
        let newScale = cameraNode.xScale / (1.0 + magnification * 0.08)
        let clamped = max(0.1, min(5.0, newScale))
        cameraNode.setScale(clamped)
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
        
        if isEditing {
            menu.addItem(.separator())
            
            let selectAllItem = NSMenuItem(title: "Tout sélectionner", action: #selector(selectAllSprites), keyEquivalent: "")
            selectAllItem.target = self
            menu.addItem(selectAllItem)
            
            if !selectedSprites.isEmpty {
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
        
        // Random position within camera view
        let camPos = cameraNode.position
        let viewHalfW = (self.view?.bounds.width ?? 800) * cameraNode.xScale / 2
        let viewHalfH = (self.view?.bounds.height ?? 600) * cameraNode.yScale / 2
        let pos = position ?? CGPoint(
            x: CGFloat.random(in: (camPos.x - viewHalfW + 50)...(camPos.x + viewHalfW - 50)),
            y: CGFloat.random(in: (camPos.y - viewHalfH + 50)...(camPos.y + viewHalfH - 50))
        )
        sprite.position = pos
        addChild(sprite)
        
        let vel = velocity ?? CGVector(
            dx: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1),
            dy: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1)
        )
        
        let spriteBounds = bounds ?? defaultBounds(around: pos)
        sprites.append(makeBouncingSprite(node: sprite, velocity: vel, imageName: imageName, isAsset: false, bounds: spriteBounds))
    }
    
    // MARK: - Edit Mode
    
    @objc private func toggleEditMode() {
        isEditing.toggle()
        
        if isEditing {
            updateBoundsVisuals()
        } else {
            clearSelection()
            removeBoundsVisuals()
            lastUpdateTime = 0
        }
    }
    
    @objc private func selectAllSprites() {
        clearSelection()
        for entry in sprites {
            selectSprite(entry.node)
        }
    }
    
    @objc private func randomizeSelected() {
        for node in selectedSprites {
            guard let idx = sprites.firstIndex(where: { $0.node === node }) else { continue }
            
            let b = sprites[idx].bounds
            let halfW = sprites[idx].halfW
            let halfH = sprites[idx].halfH
            node.position = CGPoint(
                x: CGFloat.random(in: (b.minX + halfW)...(b.maxX - halfW)),
                y: CGFloat.random(in: (b.minY + halfH)...(b.maxY - halfH))
            )
            
            sprites[idx].velocity = CGVector(
                dx: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1),
                dy: CGFloat.random(in: 80...200) * (Bool.random() ? 1 : -1)
            )
        }
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        
        let location = event.location(in: self)
        let shift = event.modifierFlags.contains(.shift)
        
        // 1. Check if clicking on a handle
        if let (spriteIdx, side) = handleHitTest(at: location) {
            isDraggingHandle = true
            activeHandleSpriteIndex = spriteIdx
            activeHandleSide = side
            return
        }
        
        // 2. Check if clicking on a sprite
        let clickedNode = sprites.first(where: { $0.node.contains(location) })?.node
        
        if let node = clickedNode {
            if shift {
                if selectedSprites.contains(node) {
                    deselectSprite(node)
                } else {
                    selectSprite(node)
                }
            } else {
                if !selectedSprites.contains(node) {
                    clearSelection()
                    selectSprite(node)
                }
            }
            isDraggingSprites = true
            dragLastPoint = location
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
                if let idx = sprites.firstIndex(where: { $0.node === node }) {
                    sprites[idx].bounds = sprites[idx].bounds.offsetBy(dx: dx, dy: dy)
                }
            }
            dragLastPoint = current
            updateBoundsVisuals()
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
                selectSprite(entry.node)
            }
        }
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
    
    // MARK: - Selection Helpers
    
    private func selectSprite(_ node: SKSpriteNode) {
        selectedSprites.insert(node)
        addHighlight(to: node)
        if isEditing { updateBoundsVisuals() }
    }
    
    private func deselectSprite(_ node: SKSpriteNode) {
        selectedSprites.remove(node)
        removeHighlight(from: node)
        if isEditing { updateBoundsVisuals() }
    }
    
    private func clearSelection() {
        for node in selectedSprites {
            removeHighlight(from: node)
        }
        selectedSprites.removeAll()
        if isEditing { updateBoundsVisuals() }
    }
    
    private func addHighlight(to node: SKSpriteNode) {
        guard node.childNode(withName: highlightName) == nil else { return }
        let border = SKShapeNode(rectOf: CGSize(
            width: node.texture?.size().width ?? node.size.width / abs(node.xScale),
            height: node.texture?.size().height ?? node.size.height / abs(node.yScale)
        ))
        border.strokeColor = .cyan
        border.lineWidth = 2 * cameraNode.xScale / abs(node.xScale)
        border.fillColor = .clear
        border.name = highlightName
        border.zPosition = 1
        node.addChild(border)
    }
    
    private func removeHighlight(from node: SKSpriteNode) {
        node.childNode(withName: highlightName)?.removeFromParent()
    }
    
    // MARK: - Delete & Undo
    
    @objc private func deleteSelected() {
        guard !selectedSprites.isEmpty else { return }
        
        var deleted: [BouncingSprite] = []
        
        for node in selectedSprites {
            if let idx = sprites.firstIndex(where: { $0.node === node }) {
                deleted.append(sprites[idx])
                sprites.remove(at: idx)
                node.removeFromParent()
            }
        }
        
        selectedSprites.removeAll()
        updateBoundsVisuals()
        
        if !deleted.isEmpty {
            undoStack.append(deleted)
        }
    }
    
    private func undoLastDelete() {
        guard let lastDeleted = undoStack.popLast() else { return }
        
        for entry in lastDeleted {
            addChild(entry.node)
            sprites.append(entry)
        }
        updateBoundsVisuals()
    }
    
    // MARK: - Keyboard
    
    override func keyDown(with event: NSEvent) {
        if isEditing {
            let cmd = event.modifierFlags.contains(.command)
            let key = event.charactersIgnoringModifiers ?? ""
            
            if event.keyCode == 51 || event.keyCode == 117 {
                deleteSelected()
                return
            }
            if cmd && key == "z" {
                undoLastDelete()
                return
            }
            if cmd && key == "c" {
                copySelection()
                return
            }
            if cmd && key == "v" {
                pasteClipboard()
                return
            }
            if cmd && key == "d" {
                duplicateSelection()
                return
            }
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
            guard let entry = sprites.first(where: { $0.node === node }) else { continue }
            clipboard.append((
                imageName: entry.imageName,
                isAsset: entry.isAsset,
                velocity: entry.velocity,
                scale: abs(node.yScale),
                offset: CGPoint(x: node.position.x - centerX, y: node.position.y - centerY),
                bounds: entry.bounds
            ))
        }
    }
    
    private func pasteClipboard() {
        guard !clipboard.isEmpty else { return }
        
        let camPos = cameraNode.position
        let centerX = camPos.x + CGFloat.random(in: -30...30)
        let centerY = camPos.y + CGFloat.random(in: -30...30)
        
        clearSelection()
        
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
            
            sprites.append(makeBouncingSprite(node: sprite, velocity: item.velocity, imageName: item.imageName, isAsset: item.isAsset, bounds: newBounds))
            selectSprite(sprite)
        }
    }
    
    private func duplicateSelection() {
        guard !selectedSprites.isEmpty else { return }
        
        let offset: CGFloat = 20
        var newNodes: [SKSpriteNode] = []
        
        for node in selectedSprites {
            guard let entry = sprites.first(where: { $0.node === node }) else { continue }
            guard let texture = cachedTexture(imageName: entry.imageName, isAsset: entry.isAsset) else { continue }
            
            let sprite = SKSpriteNode(texture: texture)
            sprite.setScale(abs(node.yScale))
            sprite.position = CGPoint(x: node.position.x + offset, y: node.position.y - offset)
            addChild(sprite)
            
            let newBounds = entry.bounds.offsetBy(dx: offset, dy: -offset)
            sprites.append(makeBouncingSprite(node: sprite, velocity: entry.velocity, imageName: entry.imageName, isAsset: entry.isAsset, bounds: newBounds))
            newNodes.append(sprite)
        }
        
        clearSelection()
        for node in newNodes {
            selectSprite(node)
        }
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
                        boundsH: entry.bounds.size.height
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
                sprites.append(makeBouncingSprite(node: sprite, velocity: vel, imageName: spriteData.imageName, isAsset: spriteData.isAsset, bounds: bounds))
            }
            
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
                        self.sprites.append(self.makeBouncingSprite(node: sprite, velocity: vel, imageName: spriteData.imageName, isAsset: spriteData.isAsset, bounds: bounds))
                    }
                    
                    self.lastUpdateTime = 0
                } catch {
                    print("Load error: \(error)")
                }
            }
        }
    }
}
