# Free-Text Property Values — Design

## Motivation

Prerequisite for the KiCad symbol library import project
(`docs/superpowers/specs/2026-07-26-kicad-symbol-import-design.md`), which
needs to preserve every KiCad symbol property (Value, Footprint, Datasheet,
Description, and arbitrary custom fields) rather than silently dropping
whatever doesn't fit. CircuitPro's `Property` system
(`PropertyKey`/`PropertyValue`/`Unit`) is built entirely for measurable EE
quantities — a closed enum of quantity kinds, a numeric single-or-range
value, and a structured SI-prefix/base-unit pair. There is currently no way
to attach a plain text value (a footprint path, a URL, a free-form
description) to a component at all. This project adds that, as a
general-purpose capability usable by hand (via the existing property
editing UI) — the KiCad importer is one future consumer of it, not
something this project special-cases for.

## Scope

**In scope:**
- A new `PropertyValue.text(String)` case, alongside the existing
  `.single`/`.range`.
- A new `PropertyValueType.text` case.
- Two new `PropertyKey` cases:
  - `.text(TextType)` — a small fixed set of well-known EDA text fields
    (Footprint, Datasheet, Description, Manufacturer, Manufacturer Part
    Number), presented the same way `.basic`/`.rating`/etc. already are.
  - `.custom(label: String)` — an arbitrary, user-or-importer-supplied
    label, for anything not in the well-known set.
- UI support for both: selecting a well-known text key from a new "Text"
  submenu in the existing key picker; a "Custom…" action that prompts for
  a label; a plain text field for editing the value (replacing the
  numeric field for these keys); the existing unit column already
  degrades to an empty "–" state for unitless keys, so it needs no
  changes.

**Out of scope:**
- Changing how `.basic`/`.rating`/`.temperature`/`.rf`/`.battery`/`.sensor`
  properties work — untouched.
- The KiCad importer itself (separate spec, depends on this one).
- Any migration of existing saved data — this is purely additive; no
  existing property can currently be a text value, so there's nothing to
  migrate.

## Data model changes

### `PropertyValue` (`Model/Property/PropertyValue.swift`)

`Codable` here is hand-written (not synthesized), so every part needs an
explicit new arm:

```swift
enum PropertyValue: Codable, Equatable, Hashable {
    case single(Double?)
    case range(min: Double?, max: Double?)
    case text(String)

    var type: PropertyValueType {
        switch self {
        case .single: return .single
        case .range: return .range
        case .text: return .text
        }
    }

    var description: String {
        switch self {
        case .single(let value):
            if let value { return "\(value)" } else { return "" }
        case let .range(min, max):
            return "\(min ?? 0) to \(max ?? 0)"
        case .text(let value):
            return value
        }
    }

    private enum ValueType: String, Codable {
        case single, range, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .single:
            let value = try container.decodeIfPresent(Double.self, forKey: .value)
            self = .single(value)
        case .range:
            let min = try container.decodeIfPresent(Double.self, forKey: .min)
            let max = try container.decodeIfPresent(Double.self, forKey: .max)
            self = .range(min: min, max: max)
        case .text:
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .single(let value):
            try container.encode(ValueType.single, forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
        case let .range(min, max):
            try container.encode(ValueType.range, forKey: .type)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)
        case .text(let value):
            try container.encode(ValueType.text, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

enum PropertyValueType: String, CaseIterable, Identifiable, Codable {
    case single
    case range
    case text

    var label: String {
        switch self {
        case .single: return "Single Value"
        case .range: return "Range"
        case .text: return "Text"
        }
    }
}
```

(`CodingKeys` — `type, value, min, max` — is unchanged; `.text` reuses the
`value` key, decoded as `String` instead of `Double`.)

### `PropertyKey` (`Model/Property/PropertyKey.swift`)

`Codable` here is Swift-synthesized (keyed by case name), so adding cases
is purely additive — no hand-written encode/decode to touch.

```swift
enum PropertyKey: Hashable, Codable, Identifiable {
    case basic(BasicType)
    case rating(RatingType)
    case temperature(TemperatureType)
    case rf(RFType)
    case battery(BatteryType)
    case sensor(SensorType)
    case text(TextType)
    case custom(label: String)

    var id: String {
        switch self {
        case .basic(let type): return "basic.\(type.rawValue)"
        case .rating(let type): return "rating.\(type.rawValue)"
        case .temperature(let type): return "temp.\(type.rawValue)"
        case .rf(let type): return "rf.\(type.rawValue)"
        case .battery(let type): return "bat.\(type.rawValue)"
        case .sensor(let type): return "sensor.\(type.rawValue)"
        case .text(let type): return "text.\(type.rawValue)"
        case .custom(let label): return "custom.\(label)"
        }
    }

    var label: String {
        switch self {
        case .basic(let type): return type.label
        case .rating(let type): return type.label
        case .temperature(let type): return type.label
        case .rf(let type): return type.label
        case .battery(let type): return type.label
        case .sensor(let type): return type.label
        case .text(let type): return type.label
        case .custom(let label): return label
        }
    }

    enum TextType: String, CaseIterable, Codable {
        case footprint, datasheet, description, manufacturer, manufacturerPartNumber

        var label: String {
            switch self {
            case .footprint: return "Footprint"
            case .datasheet: return "Datasheet"
            case .description: return "Description"
            case .manufacturer: return "Manufacturer"
            case .manufacturerPartNumber: return "Manufacturer Part Number"
            }
        }
    }

    // ... existing BasicType/RatingType/TemperatureType/RFType/BatteryType/SensorType unchanged
}

extension PropertyKey {
    var allowedValueType: PropertyValueType {
        switch self {
        case .temperature:
            return .range
        case .text, .custom:
            return .text
        default:
            return .single
        }
    }
}

extension PropertyKey {
    var allowedBaseUnits: [BaseUnit] {
        switch self {
        // ... existing cases unchanged
        case .text, .custom:
            return []
        }
    }
}
```

## UI changes

### `PropertyColumn.swift`

Add a "Text" submenu next to the existing Rating/Temperature/RF/Battery/
Sensor submenus, plus a "Custom…" action:

```swift
Menu("Text") {
    ForEach(PropertyKey.TextType.allCases, id: \.self) { type in
        Button {
            setKey(.text(type))
        } label: {
            Text(type.label)
        }
        .disabled(isDisabled(for: .text(type)))
    }
}

Divider()

Button("Custom…") {
    showingCustomLabelPrompt = true
}
```

with new local state and an alert:

```swift
@State private var showingCustomLabelPrompt = false
@State private var customLabelInput = ""
```

```swift
.alert("New Custom Property", isPresented: $showingCustomLabelPrompt) {
    TextField("Label", text: $customLabelInput)
    Button("Add") {
        let label = customLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        setKey(.custom(label: label))
        customLabelInput = ""
    }
    Button("Cancel", role: .cancel) {
        customLabelInput = ""
    }
}
```

`setKey`'s value-type-correction switch gains a `.text` arm:

```swift
switch key.allowedValueType {
case .single:
    if case .range = property.value { property.value = .single(nil) }
    if case .text = property.value { property.value = .single(nil) }
case .range:
    if case .single = property.value { property.value = .range(min: nil, max: nil) }
    if case .text = property.value { property.value = .range(min: nil, max: nil) }
case .text:
    if case .text = property.value {} else { property.value = .text("") }
}
```

(The existing unit-defaulting logic below this switch is unchanged — it
already clears the unit to `nil`/`nil` whenever `allowedBaseUnits` isn't
exactly one item, which is already true for `.text`/`.custom`.)

### `ValueColumn.swift` and `InspectorValueColumn.swift`

Add a third branch for `.text`, alongside the existing single/range
branches — a plain `TextField` bound to the string, no numeric parsing:

```swift
// ValueColumn.swift
if allowedValueType == .single {
    // ...unchanged
} else if allowedValueType == .range {
    // ...unchanged
} else {
    TextField("Value", text: textBinding)
        .textFieldStyle(.roundedBorder)
}
```

with a new binding:

```swift
private var textBinding: Binding<String> {
    Binding<String>(
        get: {
            if case .text(let val) = property.value { return val } else { return "" }
        },
        set: { newVal in
            property.value = .text(newVal)
        }
    )
}
```

`InspectorValueColumn` follows its existing buffered-local-state pattern
(`editedValue`/`onSubmit`/focus-triggered commit) — add `editedTextValue:
String`, a `.text` branch in `initializeState()` and `commitChange()`
mirroring the existing single-value branch exactly, just without the
`Double(...)` parse.

### No changes needed

`UnitColumn.swift` / `InspectorUnitColumn.swift` — `allowedBaseUnits` being
empty already renders the existing "–" unitless state (the same path
`.rf(.VSWR)` already exercises). `WarnOnEditColumn.swift` and
`ComponentPropertiesView.swift` are generic over key/value type and need no
changes. `ProjectManager.generateString(for:component:)` already calls
`prop.value.description` generically and will pick up `.text` for free.

## Compatibility

`PropertyKey`'s synthesized `Codable` makes the two new cases purely
additive — existing saved projects/libraries keep decoding unchanged.
`PropertyValue`'s hand-written `Codable` is extended explicitly as shown
above; no existing encoded value can be `.text`, so there's nothing to
migrate, only new cases to decode going forward.

## Follow-on work (not this project)

- KiCad symbol library import, which will map KiCad's Footprint/Datasheet/
  Description/Value/custom fields onto these new `PropertyKey` cases.
