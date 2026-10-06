import Foundation

/// Frame definitions for the placeholder character, keyed by sheet name
/// (directional animations share the walk/run definitions). When the
/// final sprite sheets ship in the bundle they take precedence and this
/// table simply stops being consulted for those animations.
///
/// Note: `CookiePose` arguments must stay in declaration order.
enum CookiePoseCatalog {
    static func frames(forSheet sheetName: String) -> [CookiePose]? {
        poses[sheetName]
    }

    private static let poses: [String: [CookiePose]] = [
        "idle": [
            CookiePose(tailAngle: -8),
            CookiePose(squash: 1.02),
            CookiePose(tailAngle: 8),
            CookiePose(squash: 0.99)
        ],
        "idleBlink": [
            CookiePose(),
            CookiePose(eyeStyle: .closed),
            CookiePose(),
            CookiePose()
        ],
        "sit": [
            CookiePose(squash: 0.97, bodyY: -4),
            CookiePose(squash: 0.98, bodyY: -3)
        ],
        "sleep": [
            CookiePose(squash: 0.96, bodyY: -4, headY: 2, headTilt: 6, tailAngle: 4, eyeStyle: .closed),
            CookiePose(squash: 0.94, bodyY: -5, headY: 3, headTilt: 6, tailAngle: -4, eyeStyle: .closed)
        ],
        "wake": [
            CookiePose(squash: 0.94, headTilt: -4, eyeStyle: .closed),
            CookiePose(bodyY: -2, headTilt: -8, eyeStyle: .half),
            CookiePose(squash: 1.02)
        ],
        "stretch": [
            CookiePose(squash: 0.92, bodyY: -5, pawLift: 4, eyeStyle: .happy),
            CookiePose(squash: 1.05, bodyY: 2, pawLift: 6, eyeStyle: .happy),
            CookiePose(pawLift: 2, eyeStyle: .happy)
        ],
        "yawn": [
            CookiePose(eyeStyle: .half, mouthStyle: .open),
            CookiePose(squash: 1.03, eyeStyle: .closed, mouthStyle: .openWide),
            CookiePose(eyeStyle: .half, mouthStyle: .open),
            CookiePose()
        ],
        "groom": [
            CookiePose(headX: 5, headY: -7, headTilt: 12, eyeStyle: .closed),
            CookiePose(headX: 6, headY: -9, headTilt: 14, eyeStyle: .closed),
            CookiePose(headX: 5, headY: -7, headTilt: 12, eyeStyle: .closed)
        ],
        "walk": [
            CookiePose(bodyY: -1, tailAngle: 6, pawOffsetX: 3),
            CookiePose(bodyY: 1),
            CookiePose(bodyY: -1, tailAngle: -6, pawOffsetX: -3),
            CookiePose(bodyY: 1)
        ],
        "run": [
            CookiePose(squash: 1.02, bodyY: -3, tailAngle: 12, pawOffsetX: 5),
            CookiePose(bodyY: 2),
            CookiePose(squash: 1.02, bodyY: -3, tailAngle: -12, pawOffsetX: -5),
            CookiePose(bodyY: 2)
        ],
        "curious": [
            CookiePose(headTilt: 6, gazeX: 3),
            CookiePose(headTilt: 6, tailAngle: 8, gazeX: -2)
        ],
        "happy": [
            CookiePose(squash: 0.92, bodyY: -4, eyeStyle: .happy),
            CookiePose(squash: 1.08, bodyY: 6, eyeStyle: .happy),
            CookiePose(squash: 0.98, eyeStyle: .happy)
        ],
        "surprised": [
            CookiePose(squash: 1.02, bodyY: 2, eyeStyle: .wide, mouthStyle: .open),
            CookiePose(squash: 0.98, eyeStyle: .wide, mouthStyle: .open)
        ],
        "scared": [
            CookiePose(squash: 0.94, bodyY: -4, tailAngle: 20, earStyle: .back, eyeStyle: .wide),
            CookiePose(squash: 0.92, bodyY: -5, tailAngle: -20, earStyle: .back, eyeStyle: .wide)
        ],
        "annoyed": [
            CookiePose(tailAngle: -6, eyeStyle: .half, mouthStyle: .flat),
            CookiePose(tailAngle: 6, eyeStyle: .half, mouthStyle: .flat)
        ],
        "playful": [
            CookiePose(squash: 0.9, bodyY: -5, tailAngle: 18, eyeStyle: .wide),
            CookiePose(squash: 0.94, bodyY: -3, tailAngle: -12, eyeStyle: .happy),
            CookiePose(squash: 0.9, bodyY: -5, tailAngle: 14, eyeStyle: .wide)
        ],
        "eat": [
            CookiePose(headY: -6, mouthStyle: .open),
            CookiePose(headY: -8, mouthStyle: .open),
            CookiePose(headY: -6, mouthStyle: .open),
            CookiePose(headY: -7, mouthStyle: .openWide)
        ],
        "drink": [
            CookiePose(headY: -9, mouthStyle: .open),
            CookiePose(headY: -11, mouthStyle: .open)
        ],
        "pet": [
            CookiePose(squash: 0.9, bodyY: -3, eyeStyle: .happy, blushScale: 1.4),
            CookiePose(squash: 1.06, bodyY: 5, eyeStyle: .happy, blushScale: 1.5),
            CookiePose(squash: 0.98, eyeStyle: .happy, blushScale: 1.4)
        ],
        "meow": [
            CookiePose(headY: 3, eyeStyle: .half, mouthStyle: .open),
            CookiePose(headY: 5, eyeStyle: .half, mouthStyle: .openWide),
            CookiePose(headY: 3, eyeStyle: .half, mouthStyle: .open)
        ],
        "jump": [
            CookiePose(squash: 0.88, bodyY: -4, eyeStyle: .happy),
            CookiePose(squash: 1.1, bodyY: 12, pawLift: 4, eyeStyle: .happy),
            CookiePose(squash: 1.02)
        ],
        "fall": [
            CookiePose(squash: 1.05, tailAngle: 25, pawLift: -4, earStyle: .back, eyeStyle: .wide),
            CookiePose(squash: 1.05, tailAngle: 15, pawLift: -4, earStyle: .back, eyeStyle: .wide)
        ],
        "pickedUp": [
            CookiePose(squash: 1.03, tailAngle: 10, pawLift: -5, eyeStyle: .wide),
            CookiePose(squash: 1.02, tailAngle: -6, pawLift: -4, eyeStyle: .wide)
        ],
        "dropped": [
            CookiePose(squash: 0.85, bodyY: -6, eyeStyle: .closed),
            CookiePose(squash: 0.92, bodyY: -2, eyeStyle: .wide),
            CookiePose()
        ]
    ]
}
