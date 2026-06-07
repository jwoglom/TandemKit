import SwiftUI

struct TandemKitPumpInformationView: View {
    @ObservedObject var viewModel: TandemKitPumpInformationViewModel

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section {
                    SectionRow(
                        title: Text("Serial Number", comment: "pump information serial number"),
                        value: viewModel.pumpSerial
                    )
                    SectionRow(
                        title: Text("Software Version", comment: "pump information software version"),
                        value: viewModel.softwareName
                    )
                    SectionRow(
                        title: Text("Api Version", comment: "pump information api version"),
                        value: viewModel.apiVersion
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
