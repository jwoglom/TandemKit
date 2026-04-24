import LoopKit
import LoopKitUI
import SwiftUI

struct TandemKitInsulinType: View {
    @Environment(\.dismissAction) private var dismiss

    @State private var insulinType: InsulinType?
    private var label: Text
    private var supportedInsulinTypes: [InsulinType]
    private var didConfirm: (InsulinType) -> Void

    init(
        initialValue: InsulinType?,
        supportedInsulinTypes: [InsulinType],
        label: String,
        didConfirm: @escaping (InsulinType) -> Void
    ) {
        insulinType = initialValue
        self.supportedInsulinTypes = supportedInsulinTypes
        self.label = Text(label)
        self.didConfirm = didConfirm
    }

    func continueWithType(_ insulinType: InsulinType?) {
        guard let insulinType else {
            return
        }

        didConfirm(insulinType)
    }

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section {
                    InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                        .padding(.horizontal)
                }
            }

            Spacer()

            ContinueButton(text: label) {
                self.continueWithType(insulinType)
            }
            .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .navigationTitle(String(localized: "Select insulin type", comment: "Title for insulin type"))
    }
}
