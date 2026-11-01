// Checks the string catalogs, from the repo root:
//   swift scripts/check-localizations.swift [<DerivedData>]
// Every text in Millisalary/Localizable.xcstrings and MillisalaryCore's
// must be translated into every language below (each plural form Ukrainian
// has, when the text varies by plural), with the same placeholders as the
// English key. Given a build's DerivedData, it also reads the texts the
// compiler extracted from the code (the targets' .stringsdata, written with
// SWIFT_EMIT_LOC_STRINGS) and fails on any the catalogs don't have. Add
// them with
//   xcrun xcstringstool sync <catalog> --stringsdata <the target's .stringsdata>
// (what Xcode does on its own when it builds), then translate them.
// Reads only; exits 1 when something is missing.
import Foundation

let languages = ["uk"]
/// Ukrainian's plural forms (CLDR): 1, 21; 2–4, 22–24; 5–20, 25–30; fractions
let pluralForms = ["uk": ["one", "few", "many", "other"]]

/// Each catalog, and the build folder of the target whose texts it holds
let catalogs = [
    (path: "Millisalary/Localizable.xcstrings", target: "Millisalary.build"),
    (path: "Packages/MillisalaryCore/Sources/MillisalaryCore/Localizable.xcstrings", target: "MillisalaryCore.build"),
]

var problems: [String] = []

func json(at path: String) -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: path),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        print("Can't read \(path) as JSON")
        exit(1)
    }
    return object
}

/// The conversions of a format string's placeholders, sorted, so that
/// positional ones (%1$@, %2$lld) may be reordered: "%@ of %lld" is
/// ["@", "lld"]. "%%" is a percent sign, not a placeholder
func placeholders(_ format: String) -> [String] {
    let pattern = #/%(?:\d+\$)?[-+ 0#']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSaAp%])/#
    return format.matches(of: pattern).compactMap { match in
        match.output.2 == "%" ? nil : String(match.output.1 ?? "") + String(match.output.2)
    }.sorted()
}

/// Every stringUnit under a localization, with where it is: the plain one,
/// or one per plural form (or device) under "variations"
func stringUnits(_ node: [String: Any], at path: String) -> [(path: String, unit: [String: Any])] {
    var units: [(String, [String: Any])] = []
    if let unit = node["stringUnit"] as? [String: Any] { units.append((path, unit)) }
    for (kind, value) in (node["variations"] as? [String: [String: Any]]) ?? [:] {
        for (name, variant) in value {
            guard let variant = variant as? [String: Any] else { continue }
            units += stringUnits(variant, at: "\(path) \(kind) \(name)")
        }
    }
    return units
}

let derivedData = CommandLine.arguments.dropFirst().first

for catalog in catalogs {
    let strings = (json(at: catalog.path)["strings"] as? [String: [String: Any]]) ?? [:]

    for (key, entry) in strings.sorted(by: { $0.key < $1.key }) where entry["shouldTranslate"] as? Bool != false {
        let localizations = (entry["localizations"] as? [String: [String: Any]]) ?? [:]
        for language in languages {
            let name = "\(catalog.path): \"\(key)\" (\(language))"
            guard let localization = localizations[language] else {
                problems.append("\(name): not translated")
                continue
            }
            let units = stringUnits(localization, at: "")
            if units.isEmpty { problems.append("\(name): no translation") }

            if let plural = (localization["variations"] as? [String: [String: Any]])?["plural"] {
                let missing = (pluralForms[language] ?? ["other"]).filter { plural[$0] == nil }
                if !missing.isEmpty { problems.append("\(name): no plural form \(missing.joined(separator: ", "))") }
            }

            for (path, unit) in units {
                let value = unit["value"] as? String ?? ""
                if unit["state"] as? String != "translated" || value.isEmpty {
                    problems.append("\(name)\(path): not translated (\(unit["state"] as? String ?? "no state"))")
                    continue
                }
                // A plural form may leave its number out ("one": "a day");
                // a plain translation has exactly the key's placeholders
                let expected = placeholders(key), found = placeholders(value)
                let fits = path.isEmpty
                    ? found == expected
                    : found.allSatisfy { conversion in found.filter { $0 == conversion }.count <= expected.filter { $0 == conversion }.count }
                if !fits {
                    problems.append("\(name)\(path): placeholders \(found) don't match the key's \(expected)")
                }
            }
        }
    }

    // The texts the code uses that the catalog doesn't have, from every
    // configuration and architecture built there (Debug-only texts too)
    guard let derivedData else { continue }
    let targetFolder = "\(derivedData)/Build/Intermediates.noindex/\(catalog.target)"
    let stringsdata = (FileManager.default.enumerator(atPath: targetFolder)?.compactMap { $0 as? String } ?? [])
        .filter { $0.hasSuffix(".stringsdata") }
    if stringsdata.isEmpty {
        problems.append("\(catalog.path): no extracted texts in \(targetFolder)")
        continue
    }
    var used: [String: String] = [:]
    for file in stringsdata {
        let data = json(at: "\(targetFolder)/\(file)")
        let source = (data["source"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? file
        for (table, entries) in (data["tables"] as? [String: [[String: Any]]]) ?? [:] {
            for entry in entries {
                guard let key = entry["key"] as? String else { continue }
                if table != "Localizable" {
                    problems.append("\(source): \"\(key)\" is in table \(table), which isn't checked")
                }
                let line = (entry["location"] as? [String: Any])?["startingLine"] as? Int
                used[key] = used[key] ?? "\(source)\(line.map { ":\($0)" } ?? "")"
            }
        }
    }
    for (key, location) in used.sorted(by: { $0.key < $1.key }) where strings[key] == nil {
        problems.append("\(catalog.path): \"\(key)\" (\(location)) is used in the code but not in the catalog")
    }
}

if problems.isEmpty {
    print("The string catalogs are translated into \(languages.joined(separator: ", "))\(derivedData == nil ? "" : " and have every text the code uses").")
} else {
    problems.forEach { print($0) }
    print("\(problems.count) problem(s) in the string catalogs.")
    exit(1)
}
