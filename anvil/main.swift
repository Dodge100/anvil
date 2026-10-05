import SwiftUI

if CommandLine.arguments.contains("--daemon") {
    AnvilDaemon.run()
} else {
    AnvilApp.main()
}
