# Free-Text Property Values Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a free-text value type to CircuitPro's `Property` system (`PropertyValue.text(String)` + two new `PropertyKey` cases for well-known EDA text fields and arbitrary custom labels), with full UI support, so components can carry Footprint/Datasheet/Description/custom text fields that the current numeric-only model can't represent.

**Architecture:** Two-phase: first make every consumer of `PropertyValue`/`PropertyValueType` handle a `.text` value correctly (even though nothing can produce one yet), then add the `PropertyKey` cases and menu UI that actually let a user select a text-shaped key. This keeps the build green at every step — `PropertyValueType.text` breaks two exhaustive switches the moment it exists, so those must be fixed in the same task that introduces it, before anything new can reach them via the UI.

**Tech Stack:** Swift, SwiftUI.

## Global Constraints

- `PropertyKey`'s `Codable` conformance is Swift-synthesized (keyed by case name) — adding cases is purely additive, no encode/decode code to touch there.
- `PropertyValue`'s `Codable` conformance is hand-written — every new case needs an explicit arm in `init(from:)` and `encode(to:)`.
- Don't touch `.basic`/`.rating`/`.temperature`/`.rf`/`.battery`/`.sensor` behavior — this project only adds new cases alongside them.
- This project has no XCTest target (see `CLAUDE.md`) — verification is `xcodebuild build` (compile-correctness) after each task, plus a manual launch/smoke-test at the end. There is no automated way to drive nested SwiftUI `Menu`/`Table`/`.alert` interaction in this environment, so full interactive click-through is left as a manual check, not something this plan's tasks can self-verify.
- Spec: `docs/superpowers/specs/2026-07-26-property-text-values-design.md`

---

### Task 1: `PropertyValue.text` + `PropertyValueType.text`, and fix every switch that breaks

Adding `PropertyValueType.text` makes two *existing* exhaustive switches (in `PropertyColumn.swift` and `InspectorValueColumn.swift`) non-exhaustive immediately — they must be fixed in this same task for the project to keep compiling, even though nothing can produce a `.text`-shaped key yet (that's Task 2). This task also makes the value-rendering UI (`ValueColumn`, `InspectorValueColumn`) correctly display/edit a `.text` value once one exists.

**Files:**
- Modify: `CircuitPro/Model/Property/PropertyValue.swift`
- Modify: `CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/ValueColumn.swift`
- Modify: `CircuitPro/Features/_Temp/Inspector/PropertyColumns/InspectorValueColumn.swift`
- Modify: `CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/PropertyColumn.swift`

**Interfaces:**
- Produces: `PropertyValue.text(String)` case; `PropertyValueType.text` case. Task 2 constructs `.text(...)` values via `PropertyKey.allowedValueType` returning `.text`.

- [ ] **Step 1: Add `.text` to `PropertyValue` and `PropertyValueType`**

Replace the full contents of `CircuitPro/Model/Property/PropertyValue.swift` with:

```swift
//
//  PropertyValue.swift
//  CircuitPro
//
//  Created by Giorgi Tchelidze on 7/25/25.
//

import Foundation

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

    // — Codable remains the same but modified for optionals —
    private enum CodingKeys: String, CodingKey {
        case type, value, min, max
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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "Single Value"
        case .range: return "Range"
        case .text: return "Text"
        }
    }
}
```

- [ ] **Step 2: Fix `PropertyColumn.setKey`'s now-broken switch**

In `CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/PropertyColumn.swift`, replace the `setKey` function's value-type-correction switch:

```swift
    private func setKey(_ key: PropertyKey) {
        property.key = key

        // Correct the property's value type
        switch key.allowedValueType {
        case .single:
            if case .range = property.value {
                property.value = .single(nil)
            }
            if case .text = property.value {
                property.value = .single(nil)
            }
        case .range:
            if case .single = property.value {
                property.value = .range(min: nil, max: nil)
            }
            if case .text = property.value {
                property.value = .range(min: nil, max: nil)
            }
        case .text:
            if case .text = property.value {} else {
                property.value = .text("")
            }
        }

        // Set default unit if there's exactly 1 allowed unit
        if let firstAllowed = key.allowedBaseUnits.first, key.allowedBaseUnits.count == 1 {
            property.unit.base = firstAllowed
            property.unit.prefix = nil // Reset prefix
        } else {
            property.unit.base = nil
            property.unit.prefix = nil // Reset prefix
        }
    }
```

(Only this function changes in this file for this task — the `body`/menu structure is untouched until Task 2.)

- [ ] **Step 3: Add the `.text` rendering branch to `ValueColumn.swift`**

In `CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/ValueColumn.swift`, replace `body` and add a `textBinding`:

```swift
    var body: some View {
        HStack {
            if allowedValueType == .single {
                TextField("Value", value: singleBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
            } else if allowedValueType == .range {
                HStack {
                    TextField("Min", value: minBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                    Text("-")
                        .foregroundStyle(.secondary)
                    TextField("Max", value: maxBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                TextField("Value", text: textBinding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
```

Add this computed property alongside `singleBinding`/`minBinding`/`maxBinding`:

```swift
    private var textBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .text(let val) = property.value {
                    return val
                } else {
                    return ""
                }
            },
            set: { newVal in
                property.value = .text(newVal)
            }
        )
    }
```

- [ ] **Step 4: Fix `InspectorValueColumn.swift`'s two now-broken switches and add `.text` support**

In `CircuitPro/Features/_Temp/Inspector/PropertyColumns/InspectorValueColumn.swift`:

Add a new buffered-state property next to the existing ones:

```swift
    @State private var editedTextValue: String = ""
```

Extend the `FocusableField` enum:

```swift
    private enum FocusableField: Hashable {
        case single, min, max, text
    }
```

Replace `body`:

```swift
    var body: some View {
        HStack {
            if property.key.allowedValueType == .single {
                TextField("Value", text: $editedValue)
                    .focused($focusedField, equals: .single)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            } else if property.key.allowedValueType == .range {
                HStack {
                    TextField("Min", text: $editedMinValue)
                        .focused($focusedField, equals: .min)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)

                    Text("-").foregroundStyle(.secondary)

                    TextField("Max", text: $editedMaxValue)
                        .focused($focusedField, equals: .max)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                TextField("Value", text: $editedTextValue)
                    .focused($focusedField, equals: .text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }
        }
        // When the view first appears, sync local state from the model.
        .onAppear(perform: initializeState)
        // When the user submits (e.g., presses Enter), commit the change.
        .onSubmit(commitChange)
        // When the focus changes (e.g., user taps away), commit the change.
        .onChange(of: focusedField) { oldFocus, newFocus in
            if oldFocus != nil && newFocus == nil { // Was focused, now is not
                commitChange()
            }
        }
        // If the underlying model changes from another source, update our local state.
        .onChange(of: property.value) {
            // Only update if we aren't the one actively editing.
            if focusedField == nil {
                initializeState()
            }
        }
    }
```

Replace `initializeState()`:

```swift
    /// Sets the local string state from the property model.
    private func initializeState() {
        switch property.value {
        case .single(let val):
            self.editedValue = val?.description ?? ""
        case .range(let minVal, let maxVal):
            self.editedMinValue = minVal?.description ?? ""
            self.editedMaxValue = maxVal?.description ?? ""
        case .text(let val):
            self.editedTextValue = val
        }
    }
```

Replace `commitChange()`:

```swift
    /// Parses the local string state and updates the binding to the model.
    private func commitChange() {
        var newPropertyValue: PropertyValue

        switch property.key.allowedValueType {
        case .single:
            let numericValue = Double(editedValue)
            newPropertyValue = .single(numericValue)

        case .range:
            let numericMin = Double(editedMinValue)
            let numericMax = Double(editedMaxValue)
            newPropertyValue = .range(min: numericMin, max: numericMax)

        case .text:
            newPropertyValue = .text(editedTextValue)
        }

        // Only update the model if the value has actually changed.
        guard newPropertyValue != property.value else { return }

        // This is the ONLY time we write back to the parent.
        property.value = newPropertyValue
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild -project CircuitPro.xcodeproj -scheme CircuitPro -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add CircuitPro/Model/Property/PropertyValue.swift \
        CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/ValueColumn.swift \
        CircuitPro/Features/_Temp/Inspector/PropertyColumns/InspectorValueColumn.swift \
        CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/PropertyColumn.swift
git commit -m "Add PropertyValue.text and fix downstream switches"
```

---

### Task 2: `PropertyKey.text(TextType)` + `.custom(label:)`, and the picker UI to select them

Makes the feature actually reachable: a user can now pick a well-known text field or type a custom label, and (because Task 1 already made every consumer handle `.text` correctly) the value renders and persists correctly immediately.

**Files:**
- Modify: `CircuitPro/Model/Property/PropertyKey.swift`
- Modify: `CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/PropertyColumn.swift`

**Interfaces:**
- Consumes: `PropertyValueType.text` and the `setKey` fix from Task 1.
- Produces: `PropertyKey.text(PropertyKey.TextType)` and `PropertyKey.custom(label: String)` cases, fully wired into `id`/`label`/`allowedValueType`/`allowedBaseUnits`.

- [ ] **Step 1: Add the `.text`/`.custom` cases and `TextType` to `PropertyKey.swift`**

In `CircuitPro/Model/Property/PropertyKey.swift`, change the enum declaration and its `id`/`label`:

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
```

Add the `TextType` nested enum alongside the existing `SensorType` (i.e. right after `SensorType`'s closing brace, still inside `PropertyKey`):

```swift
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
}
```

(Leave `BasicType`/`RatingType`/`TemperatureType`/`RFType`/`BatteryType`/`SensorType` exactly as they are — only add `TextType` after them, before the enum's final closing brace.)

Update the `allowedValueType` extension:

```swift
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
```

Update the `allowedBaseUnits` extension — add one new case arm, everything else unchanged:

```swift
extension PropertyKey {
    var allowedBaseUnits: [BaseUnit] {
        switch self {
        // BASIC
        case .basic(let type):
            switch type {
            case .capacitance: return [.farad]
            case .resistance:  return [.ohm]
            case .inductance:  return [.henry]
            case .voltage:     return [.volt]
            case .current:     return [.ampere]
            case .power:       return [.watt]
            case .frequency:   return [.hertz]
            case .tolerance:   return [.percent]
            }

        // RATING
        case .rating(let type):
            switch type {
            case .ratedVoltage, .breakdownVoltage: return [.volt]
            case .ratedCurrent: return [.ampere]
            case .ratedPower: return [.watt]
            }

        // TEMPERATURE
        case .temperature:
            return [.celsius]

        // RF
        case .rf(let type):
            switch type {
            case .impedance: return [.ohm]
            case .insertionLoss, .returnLoss: return [.decibel]
            case .VSWR: return [] // Unitless or special formatting
            }

        // BATTERY
        case .battery(let type):
            switch type {
            case .capacity: return [.ampereHour]
            case .energy: return [.wattHour]
            case .internalResistance: return [.ohm]
            }

        // SENSOR
        case .sensor(let type):
            switch type {
            case .sensitivity: return [] // Disabled for now
            case .offsetVoltage: return [.volt]
            case .hysteresis: return [.celsius]
            }

        // TEXT / CUSTOM
        case .text, .custom:
            return []
        }
    }
}
```

- [ ] **Step 2: Add the "Text" submenu and "Custom…" action to `PropertyColumn.swift`**

In `CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/PropertyColumn.swift`, add new `@State` properties to the struct (alongside the existing `@Binding var property`/`let allProperties`):

```swift
    @State private var showingCustomLabelPrompt = false
    @State private var customLabelInput = ""
```

Replace `body` in full:

```swift
    var body: some View {
        Menu {
            // Basic Types
            ForEach(PropertyKey.BasicType.allCases, id: \.self) { type in
                Button {
                    setKey(.basic(type))
                } label: {
                    Text(type.label)
                }
                .disabled(isDisabled(for: .basic(type)))
            }
            Divider()

            // Rating Types
            Menu("Rating") {
                ForEach(PropertyKey.RatingType.allCases, id: \.self) { type in
                    Button {
                        setKey(.rating(type))
                    } label: {
                        Text(type.label)
                    }
                    .disabled(isDisabled(for: .rating(type)))
                }
            }

            // Temperature Types
            Menu("Temperature") {
                ForEach(PropertyKey.TemperatureType.allCases, id: \.self) { type in
                    Button {
                        setKey(.temperature(type))
                    } label: {
                        Text(type.label)
                    }
                    .disabled(isDisabled(for: .temperature(type)))
                }
            }

            // RF Types
            Menu("RF") {
                ForEach(PropertyKey.RFType.allCases, id: \.self) { type in
                    Button {
                        setKey(.rf(type))
                    } label: {
                        Text(type.label)
                    }
                    .disabled(isDisabled(for: .rf(type)))
                }
            }

            // Battery Types
            Menu("Battery") {
                ForEach(PropertyKey.BatteryType.allCases, id: \.self) { type in
                    Button {
                        setKey(.battery(type))
                    } label: {
                        Text(type.label)
                    }
                    .disabled(isDisabled(for: .battery(type)))
                }
            }

            // Sensor Types
            Menu("Sensor") {
                ForEach(PropertyKey.SensorType.allCases, id: \.self) { type in
                    Button {
                        setKey(.sensor(type))
                    } label: {
                        Text(type.label)
                    }
                    .disabled(isDisabled(for: .sensor(type)))
                }
            }

            Divider()

            // Text Types
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

            Button("Custom…") {
                showingCustomLabelPrompt = true
            }
        } label: {
            Text(property.key?.label ?? "Select a Property")
        }
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
    }
```

(`isDisabled(for:)` and `setKey(_:)` below `body` are unchanged in this step — `setKey` was already fixed in Task 1.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project CircuitPro.xcodeproj -scheme CircuitPro -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add CircuitPro/Model/Property/PropertyKey.swift \
        CircuitPro/Features/ComponentDesign/Component/ComponentProperty/Columns/PropertyColumn.swift
git commit -m "Add PropertyKey.text/.custom cases and the Text/Custom picker UI"
```

---

### Task 3: Launch verification

There's no way to reliably drive nested `Menu`/`Table`/`.alert` interaction in this environment (see Global Constraints), so this task verifies what can be verified mechanically — a clean build and a crash-free launch reaching the screen this feature lives on — and leaves interactive click-through as an explicit manual follow-up.

**Files:** none (no code changes).

- [ ] **Step 1: Build**

Run: `xcodebuild -project CircuitPro.xcodeproj -scheme CircuitPro -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Launch the app and open Component Design**

Launch the built `CircuitPro.app`, then open the "Component Design" window (Window menu → Component Design, or however the harness drives it — e.g. via `osascript`: `tell application "System Events" to tell process "CircuitPro" to click menu item "Component Design" of menu "Window" of menu bar 1`).

- [ ] **Step 3: Confirm no crash**

Confirm the app process is still running a few seconds after opening the window (e.g. `pgrep -f "CircuitPro.app/Contents/MacOS/CircuitPro"`), and that the window list includes the Component Design window (e.g. via `osascript -e 'tell application "System Events" to tell process "CircuitPro" to return name of every window'`).

- [ ] **Step 4: Quit**

Terminate the launched app process (e.g. `pkill -TERM -f "CircuitPro.app/Contents/MacOS/CircuitPro"`).

- [ ] **Step 5: Report the manual follow-up**

Note in the final report that a human should manually: open the Details stage's property table, add a row, open the Key menu, confirm the new "Text" submenu (Footprint/Datasheet/Description/Manufacturer/Manufacturer Part Number) and "Custom…" action both appear, pick one, confirm a plain text field appears in the Value column (not Min/Max), type a value, tab away, and confirm it persists (e.g. by reselecting the row).
