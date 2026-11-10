import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = BLEScanner()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("XM4Control")
                    .font(.largeTitle.bold())

                Text("Phase 1 · BLE discovery only")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("This build does not control ANC. It only checks whether iOS can discover an advertised BLE peripheral.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(scanner.isScanning ? "Stop scan" : "Scan BLE") {
                    scanner.isScanning ? scanner.stop() : scanner.start()
                }
                .buttonStyle(.borderedProminent)

                if let error = scanner.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                List(scanner.devices) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.headline)
                        Text(device.id.uuidString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Signal: \(device.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .navigationTitle("Research")
        }
    }
}
