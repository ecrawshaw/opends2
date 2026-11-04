// swift-tools-version:5.9
// KLine: car diagnostics for macOS and iOS. Generic OBD-II (CAN and K-line) plus an independent
// implementation of the BMW E-series K-line protocols (DS2 and BMW's KWP2000* framing).
// Contains no BMW data files and no EdiabasLib code.
import PackageDescription

let package = Package(
    name: "KLine",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "KLine", targets: ["KLine"]), .executable(name: "kline", targets: ["klinecli"])],
    targets: [
        .target(name: "KLine"),
        .executableTarget(name: "klinecli", dependencies: ["KLine"]),
    ]
)
