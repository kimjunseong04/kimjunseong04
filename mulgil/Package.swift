// swift-tools-version: 6.0
import PackageDescription

// 물길(Mulgil) 핵심 로직. Foundation만 쓰므로 macOS 앱과 Linux CI에서 같은 코드가 돈다.
// UI(메뉴바 앱)는 이 패키지를 의존하는 별도 타깃으로 맥에서 만든다.
let package = Package(
    name: "Mulgil",
    platforms: [.macOS(.v15)],
    products: [.library(name: "MulgilCore", targets: ["MulgilCore"])],
    targets: [
        .target(name: "MulgilCore"),
        .testTarget(name: "MulgilCoreTests", dependencies: ["MulgilCore"]),
    ]
)
