import Foundation

/// The document a new project starts from.
///
/// It lives here rather than in the app so the test suite can compile it. This is the
/// first thing anyone sees, and a starter that failed to parse would be both embarrassing
/// and invisible until someone opened the app — so `StarterDocumentTests` holds it to the
/// same standard as any other source.
///
/// It is deliberately a worked example of all four declaration kinds rather than an empty
/// file: both preview panes are populated the moment a window opens, and the language
/// teaches itself.
public enum StarterDocument {

    public static let fileName = "Models.model"

    public static let source = """
    // Welcome to ModelForge.
    //
    // Define your shared data models here and the Swift and Kotlin panes will
    // keep up as you type. Every .model file in this project shares one
    // namespace, so types can refer to each other without any imports.

    /// A registered user of the application.
    model User {
        /// Stable, server-issued identifier.
        @json("user_id")
        id: UUID

        name: String
        email: String?

        status: UserStatus = .active
        createdAt: Instant
    }

    /// Where an account stands right now.
    enum UserStatus {
        active
        suspended
        deleted
    }

    /// How someone proved who they were.
    ///
    /// A union becomes a Swift enum with associated values and a Kotlin sealed
    /// interface. Each case carries a model, and the discriminator is written
    /// alongside that model's own fields.
    @discriminator("method")
    union SignIn {
        password(PasswordSignIn)
        passkey(PasskeySignIn)
    }

    model PasswordSignIn {
        emailAddress: String
    }

    model PasskeySignIn {
        credentialID: String
    }

    """
}
