import LoopKit
import LoopKitUI
import SwiftUI

struct TandemKitInsulinType: View {
    @Environment(\.dismissAction) private var dismiss

    @State private var insulinType: InsulinType?
    private var label: String
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
        self.label = label
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
            title

            ScrollView {
                InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                    .padding(.horizontal)
            }

            Spacer()

            ContinueButton(text: label) {
                self.continueWithType(insulinType)
            }
            .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Select insulin type", comment: "Title for insulin type"))
            .font(.title)
            .bold()
            .padding(.horizontal)

        Text(LocalizedString(
            "Select the type of insulin that you will be using in this pump",
            comment: "Title text for insulin type confirmation page"
        ))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

        Divider()
            .padding(.vertical)
    }
}
