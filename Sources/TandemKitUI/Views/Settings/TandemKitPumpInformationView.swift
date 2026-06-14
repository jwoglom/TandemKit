import SwiftUI

struct TandemKitPumpInformationView: View {
    @ObservedObject var viewModel: TandemKitPumpInformationViewModel

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section {
                    SectionRow(
                        title: Text("Api Version", comment: "pump information api version"),
                        value: viewModel.apiVersion
                    )
                    SectionRow(
                        title: Text("Serial Number", comment: "pump information serial number"),
                        value: viewModel.serialNumber
                    )
                    SectionRow(
                        title: Text("Software Version", comment: "pump information software version"),
                        value: viewModel.softwareName
                    )
                    SectionRow(
                        title: Text("ConfigA Bits", comment: "pump information configA"),
                        value: viewModel.controlBitsA
                    )
                    SectionRow(
                        title: Text("ConfigB Bits", comment: "pump information config B"),
                        value: viewModel.controlBitsB
                    )
                    SectionRow(
                        title: Text("Pump serial", comment: "pump information pumpSerial"),
                        value: viewModel.pumpSerial
                    )
                    SectionRow(
                        title: Text("PCBA serial", comment: "pump information pcbA serial"),
                        value: viewModel.pcbSerialNumber
                    )
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationTitle(String(localized: "Pump Information", comment: "Title for pump information"))
    }

    func SectionRow(title: Text, value: String) -> some View {
        HStack {
            title
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
