import Testing
@testable import ModelForgeKit

@Suite("Naming")
struct NamingTests {

    @Test("SCREAMING_SNAKE handles acronyms the way a Kotlin developer would write them",
          arguments: [
            ("applePay", "APPLE_PAY"),
            ("httpGet", "HTTP_GET"),
            ("userID", "USER_ID"),
            ("id", "ID"),
            ("active", "ACTIVE"),
            ("HTTPGet", "HTTP_GET"),
            ("already_snake", "ALREADY_SNAKE"),
            ("int32Value", "INT32_VALUE")
          ])
    func screamingSnakeCase(input: String, expected: String) {
        #expect(NamingConventions.screamingSnakeCase(input) == expected)
    }

    @Test("file stems become upper camel case",
          arguments: [
            ("user", "User"),
            ("user_profile", "UserProfile"),
            ("user-profile", "UserProfile"),
            ("User", "User"),
            ("api", "Api")
          ])
    func upperCamelCase(input: String, expected: String) {
        #expect(NamingConventions.upperCamelCase(input) == expected)
    }

    @Test("keywords are escaped per language")
    func escaping() {
        #expect(NamingConventions.escapedForSwift("class") == "`class`")
        #expect(NamingConventions.escapedForSwift("object") == "object")
        #expect(NamingConventions.escapedForKotlin("object") == "`object`")
        #expect(NamingConventions.escapedForKotlin("name") == "name")
    }
}
