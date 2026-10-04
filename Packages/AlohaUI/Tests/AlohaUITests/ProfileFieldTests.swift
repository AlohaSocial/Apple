import AlohaModels
import Testing
@testable import AlohaUI

@Suite("Profile field editing")
struct ProfileFieldTests {
    @Test("A removed field's binding cannot read or write outside the remaining array")
    func removedField() {
        let fields = [Account.Field(name: "Website", value: "example.org")]
        #expect(EditProfileView.fieldValue(in: fields, at: 1, keyPath: \.name) == "")
        #expect(EditProfileView.updatingField(in: fields, at: 1,
            keyPath: \.value, value: "late edit") == fields)
        #expect(EditProfileView.updatingField(in: [], at: 0,
            keyPath: \.name, value: "late edit").isEmpty)
    }

    @Test("Editing a valid field preserves other values and rows")
    func validField() {
        let fields = [Account.Field(name: "Website", value: "example.org"),
                      Account.Field(name: "Location", value: "Berlin")]
        let updated = EditProfileView.updatingField(in: fields, at: 0,
            keyPath: \.value, value: "example.com")
        #expect(updated[0].name == fields[0].name)
        #expect(updated[0].value == "example.com")
        #expect(updated[1] == fields[1])
    }
}
