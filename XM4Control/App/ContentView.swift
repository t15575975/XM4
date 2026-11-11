import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = BLEScanner()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("XM4Control")
                    .font(.largeTitle.bold())

                Text("Phase 2 · GATT observation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("No ANC commands are sent. This research build reads available values and subscribes to GATT notifications.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(scanner.isScanning ? "Stop scan" : "Scan BLE") {
                    scanner.isScanning ? scanner.stop() : scanner.start()
                }
                .buttonStyle(.borderedProminent)

                if let error = scanner.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                HStack {
                    Text("Observations: \(scanner.observations.count)")
                    Spacer()
                    Button("Copy log") { UIPasteboard.general.string = scanner.observations.reversed().joined(separator: "\\n") }
                    Button("Clear") { scanner.clearObservations() }
                }
                .font(.caption)

                List {
                  Section("BLE devices") {
                    ForEach(scanner.devices) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.headline)
                        Button("Inspect GATT services") { scanner.inspect(device.id) }
                            .font(.caption)
                        ForEach(device.details, id: \.self) { detail in
                            Text(detail).font(.caption2).textSelection(.enabled)
                        }
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
                  Section("GATT observations (newest first)") {
                    ForEach(Array(scanner.observations.enumerated()), id: \.offset) { _, observation in
                        Text(observation).font(.caption2).textSelection(.enabled)
                    }
                  }
                }
            }
            .padding()
            .navigationTitle("Research")
        }
    }
}
