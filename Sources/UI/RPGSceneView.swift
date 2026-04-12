import SwiftUI
import os

// MARK: - RPG Scene Container

struct RPGSceneView: View {
    @StateObject private var scene = RPGSceneState()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background layer
                BackgroundLayer()

                // Foreground ground layer
                ForegroundLayer()

                // Characters layer
                CharacterLayer(state: scene, sceneWidth: geo.size.width)

                // Enemy layer
                EnemyLayer(state: scene)

                // Damage numbers
                DamageNumbersLayer(state: scene)

                // Hero HUD - top left
                HeroHUDView(state: scene)
                    .frame(width: min(140, geo.size.width * 0.3))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Enemy HUD - top right
                if scene.enemyAlive {
                    EnemyHUDView(state: scene)
                        .frame(width: min(140, geo.size.width * 0.3))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                // XP bar overlay - bottom
                XPBarOverlay(state: scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .onAppear {
                scene.sceneWidth = geo.size.width
                Log.rpg.info("RPG scene sized to width \(geo.size.width, privacy: .public)")
            }
            .onChange(of: geo.size.width) { _, newWidth in
                scene.sceneWidth = newWidth
                Log.rpg.debug("RPG scene resized to width \(newWidth, privacy: .public)")
            }
        }
        .frame(minHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.85))
        )
        .onAppear {
            Log.rpg.info("RPG scene appeared, starting game loop")
            scene.startGameLoop()
        }
        .onDisappear {
            Log.rpg.info("RPG scene disappeared, stopping game loop")
            scene.stopGameLoop()
        }
    }
}

// MARK: - Scene State

@MainActor
class RPGSceneState: ObservableObject {
    // Hero
    @Published var heroHP: Double = 85
    @Published var heroMaxHP: Double = 100
    @Published var heroMana: Double = 60
    @Published var heroMaxMana: Double = 80
    @Published var heroXP: Double = 0.65
    @Published var heroLevel: Int = 7
    @Published var heroAttacking: Bool = false
    @Published var heroY: CGFloat = 0  // bounce offset

    // Companions (small helpers behind hero)
    @Published var companion1Y: CGFloat = 0
    @Published var companion2Y: CGFloat = 0

    // Scene dimensions (updated by GeometryReader)
    var sceneWidth: CGFloat = 300

    // Enemy
    @Published var enemyX: CGFloat = 300  // starts off-screen right
    @Published var enemyHP: Double = 100
    @Published var enemyMaxHP: Double = 100
    @Published var enemyAlive: Bool = false
    @Published var enemyName: String = "Slime"
    @Published var enemyColor: Color = .red
    @Published var enemyHit: Bool = false
    @Published var enemyLevel: Int = 5

    // Combat
    @Published var inCombat: Bool = false
    @Published var damageNumbers: [DamageNumber] = []

    // Background scroll
    @Published var bgOffset: CGFloat = 0

    private var gameTimer: Timer?
    private var tick: Int = 0
    private var combatCooldown: Int = 0
    private var spawnDelay: Int = 0
    private var enemiesDefeated: Int = 0

    struct DamageNumber: Identifiable {
        let id = UUID()
        var value: Int
        var x: CGFloat
        var y: CGFloat
        var opacity: Double = 1.0
        var isHeroDamage: Bool = false
    }

    func startGameLoop() {
        let startTime = CFAbsoluteTimeGetCurrent()
        tick = 0
        spawnDelay = 60  // ~2s before first enemy
        Log.rpg.notice("Game loop starting, first enemy spawn in ~2s")

        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Log.rpg.notice("Game loop initialized in \(elapsed, privacy: .public)s")
    }

    func stopGameLoop() {
        gameTimer?.invalidate()
        gameTimer = nil
        Log.rpg.notice("Game loop stopped after \(self.enemiesDefeated, privacy: .public) enemies defeated")
    }

    private func update() {
        tick += 1

        // Scroll background slowly
        bgOffset -= 0.3
        if bgOffset < -60 { bgOffset = 0 }

        // Hero idle bounce
        heroY = sin(Double(tick) * 0.08) * 2

        // Companion idle bounces (offset phase)
        companion1Y = sin(Double(tick) * 0.07 + 1.0) * 1.5
        companion2Y = sin(Double(tick) * 0.09 + 2.0) * 1.5

        // Spawn enemy if none alive
        if !enemyAlive {
            spawnDelay -= 1
            if spawnDelay <= 0 {
                spawnEnemy()
            }
            return
        }

        // Enemy approaching
        if !inCombat {
            let targetX: CGFloat = sceneWidth * 0.25  // where combat happens (proportional)
            let travelSpeed: CGFloat = sceneWidth / 200.0  // scale speed with width
            if enemyX > targetX {
                enemyX -= travelSpeed
            } else {
                inCombat = true
                combatCooldown = 0
                Log.rpg.debug("Combat engaged with \(self.enemyName, privacy: .public) at x=\(self.enemyX, privacy: .public)")
            }
        }

        // Combat logic
        if inCombat {
            combatCooldown -= 1
            if combatCooldown <= 0 {
                performCombatRound()
                combatCooldown = 25  // ~0.8s between hits
            }
        }

        // Update damage numbers (float up and fade)
        damageNumbers = damageNumbers.compactMap { num in
            var n = num
            n.y -= 0.8
            n.opacity -= 0.02
            return n.opacity > 0 ? n : nil
        }

        // Hero attack animation reset
        if heroAttacking && tick % 6 == 0 {
            heroAttacking = false
        }

        // Enemy hit flash reset
        if enemyHit && tick % 4 == 0 {
            enemyHit = false
        }
    }

    private func spawnEnemy() {
        let enemies: [(String, Color, Double, Int)] = [
            ("Slime", .green, 80, 3),
            ("Goblin", .red, 120, 5),
            ("Bat", .purple, 60, 2),
            ("Skeleton", .gray, 150, 7),
            ("Imp", .orange, 100, 4),
            ("Mushroom", .brown, 70, 3),
        ]
        let pick = enemies[Int.random(in: 0..<enemies.count)]
        enemyName = pick.0
        enemyColor = pick.1
        enemyMaxHP = pick.2
        enemyHP = pick.2
        enemyLevel = pick.3
        enemyX = sceneWidth + 30  // spawn off-screen right
        enemyAlive = true
        inCombat = false
        Log.rpg.notice("Enemy spawned: \(self.enemyName, privacy: .public) (HP: \(self.enemyMaxHP, privacy: .public), Lv: \(self.enemyLevel, privacy: .public))")
    }

    private func performCombatRound() {
        // Hero hits enemy
        let heroDmg = Int.random(in: 12...28)
        enemyHP -= Double(heroDmg)
        heroAttacking = true
        enemyHit = true

        // Damage number on enemy
        damageNumbers.append(DamageNumber(
            value: heroDmg,
            x: enemyX + CGFloat.random(in: -10...10),
            y: 80 + CGFloat.random(in: -10...5)
        ))

        // Enemy hits hero back (sometimes)
        if Int.random(in: 0...2) > 0 {
            let enemyDmg = Int.random(in: 3...10)
            heroHP = max(0, heroHP - Double(enemyDmg))
            let heroX = sceneWidth * 0.12
            damageNumbers.append(DamageNumber(
                value: enemyDmg,
                x: heroX + CGFloat.random(in: -10...10),
                y: 80 + CGFloat.random(in: -10...5),
                isHeroDamage: true
            ))
        }

        // Hero regen
        heroHP = min(heroMaxHP, heroHP + 2)
        heroMana = min(heroMaxMana, heroMana + 1)

        Log.rpg.debug("Combat round: hero dealt \(heroDmg, privacy: .public), enemy HP: \(self.enemyHP, privacy: .public)/\(self.enemyMaxHP, privacy: .public)")

        // Check enemy death
        if enemyHP <= 0 {
            enemyHP = 0
            enemyAlive = false
            inCombat = false
            enemiesDefeated += 1

            // XP gain
            heroXP += 0.15
            if heroXP >= 1.0 {
                heroXP = 0
                heroLevel += 1
                heroMaxHP += 10
                heroHP = heroMaxHP
                heroMaxMana += 5
                heroMana = heroMaxMana
                Log.rpg.notice("LEVEL UP! Hero is now level \(self.heroLevel, privacy: .public)")
            }

            spawnDelay = Int.random(in: 45...90)  // 1.5-3s pause
            Log.rpg.notice("Enemy \(self.enemyName, privacy: .public) defeated (#\(self.enemiesDefeated, privacy: .public)), next spawn in ~\(Double(self.spawnDelay) / 30.0, privacy: .public)s")
        }
    }
}

// MARK: - Hero HUD (top-left in scene)

struct HeroHUDView: View {
    @ObservedObject var state: RPGSceneState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Hero Lv.\(state.heroLevel)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            StatBarView(label: "HP", current: state.heroHP, maxValue: state.heroMaxHP, color: .red)
            StatBarView(label: "MP", current: state.heroMana, maxValue: state.heroMaxMana, color: .blue)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.6))
        )
    }
}

// MARK: - Enemy HUD (top-right in scene)

struct EnemyHUDView: View {
    @ObservedObject var state: RPGSceneState

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Text(state.enemyName)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Lv.\(state.enemyLevel)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.8))
            }

            StatBarView(label: "HP", current: state.enemyHP, maxValue: state.enemyMaxHP, color: .red)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.6))
        )
    }
}

// MARK: - XP Bar Overlay (bottom of scene)

struct XPBarOverlay: View {
    @ObservedObject var state: RPGSceneState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Lv.\(state.heroLevel)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .frame(width: 32, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.gray.opacity(0.3))
                        Rectangle()
                            .fill(.yellow.opacity(0.7))
                            .frame(width: geo.size.width * state.heroXP)
                    }
                }
                .frame(height: 6)

                Text("\(Int(state.heroXP * 100))%")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.8))
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5))
        }
    }
}

// MARK: - Stat Bar

struct StatBarView: View {
    let label: String
    let current: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 16, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.gray.opacity(0.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.8))
                        .frame(width: maxValue > 0 ? geo.size.width * (current / maxValue) : 0)
                }
            }
            .frame(height: 6)

            Text("\(Int(current))/\(Int(maxValue))")
                .font(.system(size: 6, weight: .medium, design: .monospaced))
                .foregroundStyle(.gray)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

// MARK: - Background Layer

struct BackgroundLayer: View {
    var body: some View {
        ZStack {
            // Sky gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.25),
                    Color(red: 0.15, green: 0.15, blue: 0.35),
                    Color(red: 0.2, green: 0.12, blue: 0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Stars (simple dots)
            Canvas { context, size in
                let starPositions: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.1, 0.15, 1.5), (0.3, 0.08, 1.0), (0.5, 0.2, 1.2),
                    (0.7, 0.05, 1.8), (0.85, 0.18, 1.0), (0.15, 0.3, 0.8),
                    (0.45, 0.12, 1.3), (0.65, 0.25, 0.9), (0.9, 0.1, 1.1),
                    (0.25, 0.22, 1.0), (0.55, 0.06, 1.4), (0.78, 0.28, 0.7),
                ]
                for (x, y, r) in starPositions {
                    let rect = CGRect(
                        x: x * size.width - r / 2,
                        y: y * size.height - r / 2,
                        width: r, height: r
                    )
                    context.fill(Circle().path(in: rect), with: .color(.white.opacity(0.6)))
                }
            }

            // Distant mountains silhouette
            Canvas { context, size in
                var path = Path()
                let baseY = size.height * 0.65
                path.move(to: CGPoint(x: 0, y: baseY))
                path.addLine(to: CGPoint(x: size.width * 0.1, y: baseY - 20))
                path.addLine(to: CGPoint(x: size.width * 0.2, y: baseY - 45))
                path.addLine(to: CGPoint(x: size.width * 0.3, y: baseY - 25))
                path.addLine(to: CGPoint(x: size.width * 0.45, y: baseY - 55))
                path.addLine(to: CGPoint(x: size.width * 0.55, y: baseY - 30))
                path.addLine(to: CGPoint(x: size.width * 0.7, y: baseY - 50))
                path.addLine(to: CGPoint(x: size.width * 0.8, y: baseY - 20))
                path.addLine(to: CGPoint(x: size.width * 0.95, y: baseY - 40))
                path.addLine(to: CGPoint(x: size.width, y: baseY - 15))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(Color(red: 0.08, green: 0.08, blue: 0.15)))
            }
        }
    }
}

// MARK: - Foreground Layer

struct ForegroundLayer: View {
    var body: some View {
        VStack {
            Spacer()
            // Ground
            ZStack(alignment: .top) {
                // Grass top edge
                Rectangle()
                    .fill(Color(red: 0.15, green: 0.4, blue: 0.15))
                    .frame(height: 4)

                // Dirt/ground
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.2, green: 0.35, blue: 0.15),
                                Color(red: 0.15, green: 0.25, blue: 0.1),
                                Color(red: 0.1, green: 0.15, blue: 0.08),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(height: 50)
        }
    }
}

// MARK: - Character Layer (Hero + Companions)

struct CharacterLayer: View {
    @ObservedObject var state: RPGSceneState
    let sceneWidth: CGFloat

    var body: some View {
        let heroX = sceneWidth * 0.12

        ZStack {
            // Companion 1 - small helper (positioned behind hero)
            PlaceholderCharacter(
                bodyColor: .cyan,
                size: 16,
                label: "C1"
            )
            .offset(x: -10, y: state.companion1Y)
            .position(x: heroX - 25, y: 145)

            // Companion 2 - small helper
            PlaceholderCharacter(
                bodyColor: .mint,
                size: 14,
                label: "C2"
            )
            .offset(x: -5, y: state.companion2Y)
            .position(x: heroX - 32, y: 158)

            // Hero character
            PlaceholderCharacter(
                bodyColor: .blue,
                size: 30,
                label: "H",
                isAttacking: state.heroAttacking
            )
            .offset(x: state.heroAttacking ? 8 : 0, y: state.heroY)
            .position(x: heroX, y: 135)
            .animation(.easeOut(duration: 0.1), value: state.heroAttacking)
        }
    }
}

// MARK: - Enemy Layer

struct EnemyLayer: View {
    @ObservedObject var state: RPGSceneState

    var body: some View {
        if state.enemyAlive {
            PlaceholderCharacter(
                bodyColor: state.enemyColor,
                size: 26,
                label: String(state.enemyName.prefix(2)),
                isHit: state.enemyHit,
                facingLeft: true
            )
            .position(x: state.enemyX, y: 138)
            .animation(.easeOut(duration: 0.5), value: state.enemyX)
            .opacity(state.enemyHP > 0 ? 1.0 : 0.3)
        }
    }
}

// MARK: - Damage Numbers Layer

struct DamageNumbersLayer: View {
    @ObservedObject var state: RPGSceneState

    var body: some View {
        ForEach(state.damageNumbers) { dmg in
            Text("\(dmg.value)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(dmg.isHeroDamage ? .red : .yellow)
                .shadow(color: .black, radius: 2)
                .position(x: dmg.x, y: dmg.y)
                .opacity(dmg.opacity)
        }
    }
}

// MARK: - Placeholder Character Shape

struct PlaceholderCharacter: View {
    let bodyColor: Color
    let size: CGFloat
    var label: String = ""
    var isAttacking: Bool = false
    var isHit: Bool = false
    var facingLeft: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            // Head (circle)
            ZStack {
                Circle()
                    .fill(bodyColor.opacity(0.9))
                    .frame(width: size * 0.6, height: size * 0.6)

                // Eyes
                HStack(spacing: size * 0.12) {
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.12, height: size * 0.12)
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.12, height: size * 0.12)
                }
                .offset(y: -size * 0.02)
            }

            // Body (rounded rectangle)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(bodyColor)
                    .frame(width: size * 0.7, height: size * 0.8)

                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: max(7, size * 0.25), weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }

            // Legs (two small rectangles)
            HStack(spacing: size * 0.1) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(bodyColor.opacity(0.7))
                    .frame(width: size * 0.2, height: size * 0.3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(bodyColor.opacity(0.7))
                    .frame(width: size * 0.2, height: size * 0.3)
            }
        }
        .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
        .brightness(isHit ? 0.5 : 0)
        .overlay(
            // Weapon (small line extending from body)
            RoundedRectangle(cornerRadius: 1)
                .fill(.gray)
                .frame(width: size * 0.5, height: size * 0.08)
                .offset(x: facingLeft ? -size * 0.5 : size * 0.5, y: size * 0.1)
                .rotationEffect(.degrees(isAttacking ? -30 : 0))
                .animation(.easeOut(duration: 0.15), value: isAttacking)
        )
    }
}
