import Foundation

/// The runtime support each language needs alongside the generated models.
///
/// Some of the DSL's scalars have no representation the two platforms agree on out of the
/// box, and two of them do not even compile on the Kotlin side without help. Rather than
/// asking every app to configure its `JSONEncoder` correctly — which fails silently when
/// somebody forgets, or uses a second encoder — ModelForge generates the coders and the
/// models reference them explicitly. The generated code is then correct regardless of how
/// the app is set up.
///
/// A happy side effect: supplying our own serializers means the Kotlin output no longer
/// depends on `kotlinx-datetime`, and works on kotlinx-serialization 1.8 as well as 1.9,
/// which only added the built-in `kotlin.time.Instant` serializer.
enum SupportFile {

    static let baseName = "ModelForgeSupport"

    /// Names the generated Swift and Kotlin both use, so the two files stay recognisably
    /// the same shape.
    enum Name {
        static let date = "ModelForgeDate"
        static let instantCoder = "ModelForgeInstant"
        static let durationCoder = "ModelForgeDuration"
        static let dateSerializer = "ModelForgeDateSerializer"
        static let instantSerializer = "ModelForgeInstantSerializer"
        static let durationSerializer = "ModelForgeDurationSerializer"
        static let decimalSerializer = "ModelForgeDecimalSerializer"
    }

    // MARK: Swift

    static func swift(configuration: SwiftEmitterConfiguration) -> String {
        let access = configuration.accessLevel.prefix
        return """
        \(ProjectConfiguration.generatedFileHeader)

        import Foundation

        // Wire formats shared with the Kotlin models generated from the same schema:
        //
        //   Instant   ISO-8601 in UTC, as "YYYY-MM-DDThh:mm:ssZ"
        //   Date      "yyyy-MM-dd"
        //   Duration  ISO-8601 duration, such as PT1M30S
        //
        // Foundation's own Codable conformances do not produce any of these, which is why
        // the generated models route these fields through the helpers below.

        // MARK: - Date

        /// A calendar date with no time and no time zone.
        ///
        /// Foundation has no date-only type — `Date` is an instant — so the schema's
        /// `Date` becomes this, and means the same thing here as it does in the Kotlin
        /// models.
        \(access)struct \(Name.date): Codable, Hashable, Sendable, Comparable, CustomStringConvertible {

            \(access)var year: Int
            \(access)var month: Int
            \(access)var day: Int

            \(access)init(year: Int, month: Int, day: Int) {
                self.year = year
                self.month = month
                self.day = day
            }

            \(access)var description: String {
                String(format: "%04d-%02d-%02d", year, month, day)
            }

            \(access)static func < (lhs: \(Name.date), rhs: \(Name.date)) -> Bool {
                (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
            }

            \(access)init(from decoder: any Decoder) throws {
                let text = try decoder.singleValueContainer().decode(String.self)
                let parts = text.split(separator: "-", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count == 3,
                      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
                      (1...12).contains(month), (1...31).contains(day) else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected a date as yyyy-MM-dd, found \\(text)."))
                }
                self.init(year: year, month: month, day: day)
            }

            \(access)func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(description)
            }
        }

        // MARK: - Instant

        /// Codes a `Date` as an ISO-8601 instant in UTC.
        ///
        /// Fractional seconds are written only when there are any, which is what the
        /// Kotlin side does too, so identical values usually produce identical text.
        struct \(Name.instantCoder): Codable, Hashable, Sendable {

            var value: Date

            init(_ value: Date) { self.value = value }

            private static let withFraction: ISO8601DateFormatter = {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter
            }()

            private static let withoutFraction: ISO8601DateFormatter = {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                return formatter
            }()

            init(from decoder: any Decoder) throws {
                let text = try decoder.singleValueContainer().decode(String.self)
                guard let date = Self.withFraction.date(from: text)
                        ?? Self.withoutFraction.date(from: text) else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected an ISO-8601 instant, found \\(text)."))
                }
                self.value = date
            }

            func encode(to encoder: any Encoder) throws {
                let seconds = value.timeIntervalSince1970
                let text = seconds == seconds.rounded()
                    ? Self.withoutFraction.string(from: value)
                    : Self.withFraction.string(from: value)
                var container = encoder.singleValueContainer()
                try container.encode(text)
            }
        }

        // MARK: - Duration

        /// Codes a `Duration` as an ISO-8601 duration.
        ///
        /// Swift's own conformance writes a two-element array of internal components,
        /// which nothing on the other platform can read.
        struct \(Name.durationCoder): Codable, Hashable, Sendable {

            var value: Duration

            init(_ value: Duration) { self.value = value }

            init(from decoder: any Decoder) throws {
                let text = try decoder.singleValueContainer().decode(String.self)
                guard let duration = Self.parse(text) else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected an ISO-8601 duration, found \\(text)."))
                }
                self.value = duration
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(Self.format(value))
            }

            /// `PT1M30S`, `PT0.5S`, `P1DT2H`, `PT0S`.
            static func format(_ duration: Duration) -> String {
                let components = duration.components
                var seconds = components.seconds
                let attoseconds = components.attoseconds
                let negative = seconds < 0 || attoseconds < 0
                if negative {
                    seconds = -seconds
                }
                let fraction = abs(Double(attoseconds)) / 1e18

                let days = seconds / 86_400
                let hours = (seconds % 86_400) / 3_600
                let minutes = (seconds % 3_600) / 60
                let wholeSeconds = seconds % 60

                var text = negative ? "-P" : "P"
                if days != 0 { text += "\\(days)D" }
                if hours != 0 || minutes != 0 || wholeSeconds != 0 || fraction != 0 || days == 0 {
                    text += "T"
                    if hours != 0 { text += "\\(hours)H" }
                    if minutes != 0 { text += "\\(minutes)M" }
                    if wholeSeconds != 0 || fraction != 0 || (hours == 0 && minutes == 0) {
                        if fraction == 0 {
                            text += "\\(wholeSeconds)S"
                        } else {
                            let combined = Double(wholeSeconds) + fraction
                            text += String(format: "%gS", combined)
                        }
                    }
                }
                return text
            }

            static func parse(_ text: String) -> Duration? {
                var remainder = Substring(text)
                var sign = 1.0
                if remainder.hasPrefix("-") { sign = -1; remainder = remainder.dropFirst() }
                else if remainder.hasPrefix("+") { remainder = remainder.dropFirst() }
                guard remainder.hasPrefix("P") else { return nil }
                remainder = remainder.dropFirst()

                var total = 0.0
                var inTime = false
                var number = ""

                for character in remainder {
                    if character == "T" {
                        inTime = true
                        continue
                    }
                    if character.isNumber || character == "." || character == "," {
                        number.append(character == "," ? "." : character)
                        continue
                    }
                    guard let magnitude = Double(number) else { return nil }
                    number = ""
                    switch (character, inTime) {
                    case ("D", _): total += magnitude * 86_400
                    case ("H", true): total += magnitude * 3_600
                    case ("M", true): total += magnitude * 60
                    case ("S", true): total += magnitude
                    default: return nil
                    }
                }
                guard number.isEmpty else { return nil }
                return .seconds(sign * total)
            }
        }
        """
    }

    // MARK: Kotlin

    static func kotlin(configuration: KotlinEmitterConfiguration) -> String {
        """
        \(ProjectConfiguration.generatedFileHeader)

        @file:OptIn(kotlin.time.ExperimentalTime::class, kotlinx.serialization.ExperimentalSerializationApi::class)

        package \(configuration.package)

        import kotlinx.serialization.KSerializer
        import kotlinx.serialization.Serializable
        import kotlinx.serialization.descriptors.PrimitiveKind
        import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
        import kotlinx.serialization.descriptors.SerialDescriptor
        import kotlinx.serialization.encoding.Decoder
        import kotlinx.serialization.encoding.Encoder
        import kotlinx.serialization.json.JsonDecoder
        import kotlinx.serialization.json.JsonEncoder
        import kotlinx.serialization.json.JsonUnquotedLiteral
        import kotlinx.serialization.json.jsonPrimitive
        import java.math.BigDecimal
        import kotlin.time.Duration
        import kotlin.time.Instant

        // Wire formats shared with the Swift models generated from the same schema:
        //
        //   Instant   ISO-8601 in UTC, as "YYYY-MM-DDThh:mm:ssZ"
        //   Date      "yyyy-MM-dd"
        //   Duration  ISO-8601 duration, such as PT1M30S
        //   Decimal   a JSON number, not a string
        //
        // Supplying these here rather than relying on library serializers is what lets the
        // generated code compile against kotlinx-serialization 1.8 and drop the
        // kotlinx-datetime dependency entirely.

        /// A calendar date with no time and no time zone.
        ///
        /// Declared here rather than mapped to `kotlinx.datetime.LocalDate` so that models
        /// generated from a schema carry no dependency the project did not already have.
        @Serializable(with = \(Name.dateSerializer)::class)
        data class \(Name.date)(val year: Int, val month: Int, val day: Int) : Comparable<\(Name.date)> {

            override fun toString(): String = "%04d-%02d-%02d".format(year, month, day)

            override fun compareTo(other: \(Name.date)): Int =
                compareValuesBy(this, other, { it.year }, { it.month }, { it.day })
        }

        object \(Name.dateSerializer) : KSerializer<\(Name.date)> {

            override val descriptor: SerialDescriptor =
                PrimitiveSerialDescriptor("\(Name.date)", PrimitiveKind.STRING)

            override fun serialize(encoder: Encoder, value: \(Name.date)) {
                encoder.encodeString(value.toString())
            }

            override fun deserialize(decoder: Decoder): \(Name.date) {
                val text = decoder.decodeString()
                val parts = text.split("-")
                require(parts.size == 3) { "Expected a date as yyyy-MM-dd, found $text." }
                return \(Name.date)(parts[0].toInt(), parts[1].toInt(), parts[2].toInt())
            }
        }

        object \(Name.instantSerializer) : KSerializer<Instant> {

            override val descriptor: SerialDescriptor =
                PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)

            override fun serialize(encoder: Encoder, value: Instant) {
                encoder.encodeString(value.toString())
            }

            override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
        }

        object \(Name.durationSerializer) : KSerializer<Duration> {

            override val descriptor: SerialDescriptor =
                PrimitiveSerialDescriptor("Duration", PrimitiveKind.STRING)

            override fun serialize(encoder: Encoder, value: Duration) {
                encoder.encodeString(value.toIsoString())
            }

            override fun deserialize(decoder: Decoder): Duration = Duration.parse(decoder.decodeString())
        }

        /// Written as a JSON number so it matches Swift's `Decimal`, which encodes as one.
        object \(Name.decimalSerializer) : KSerializer<BigDecimal> {

            override val descriptor: SerialDescriptor =
                PrimitiveSerialDescriptor("Decimal", PrimitiveKind.STRING)

            override fun serialize(encoder: Encoder, value: BigDecimal) {
                if (encoder is JsonEncoder) {
                    encoder.encodeJsonElement(JsonUnquotedLiteral(value.toPlainString()))
                } else {
                    encoder.encodeString(value.toPlainString())
                }
            }

            override fun deserialize(decoder: Decoder): BigDecimal =
                if (decoder is JsonDecoder) {
                    BigDecimal(decoder.decodeJsonElement().jsonPrimitive.content)
                } else {
                    BigDecimal(decoder.decodeString())
                }
        }
        """
    }
}
