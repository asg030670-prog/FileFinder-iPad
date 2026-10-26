#if os(iOS)
import SwiftUI
import FileFinderCore

/// Sheet for combining filters: kind, size, modification date, location and options.
/// Changes are applied live, so results update while the sheet is open.
struct FilterView: View {
    @ObservedObject var viewModel: SearchViewModel
    let locations: [SearchLocation]

    @Environment(\.dismiss) var dismiss
    @State var minimumMegabytes = ""
    @State var maximumMegabytes = ""
    @State var isCustomSize = false
    @State var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State var customTo = Date()

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                sizeSection
                dateSection
                locationSection
                optionsSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        viewModel.resetFilters()
                        isCustomSize = false
                        minimumMegabytes = ""
                        maximumMegabytes = ""
                    }
                    .disabled(!viewModel.filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadCustomValues)
        }
    }

    // MARK: - Kind

    private var kindSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(FileCategory.allCases) { category in
                    let isSelected = viewModel.filter.categories.contains(category)
                    Button {
                        viewModel.toggleCategory(category)
                    } label: {
                        Label(category.displayName, systemImage: category.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? Color.accentColor : Color.secondary)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .offset(x: 4, y: -4)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Kind")
        } footer: {
            Text("No selection shows every kind.")
        }
    }

    // MARK: - Size

    private var sizeSection: some View {
        Section("Size") {
            Picker("Size", selection: sizePresetBinding) {
                ForEach(SizeRange.presets.indices, id: \.self) { index in
                    Text(SizeRange.presets[index].name).tag(index)
                }
                Text("Custom").tag(-1)
            }
            if sizePresetBinding.wrappedValue == -1 {
                HStack {
                    TextField("Min MB", text: $minimumMegabytes)
                        .keyboardType(.decimalPad)
                        .onChange(of: minimumMegabytes) { _ in applyCustomSize() }
                    Text("–")
                    TextField("Max MB", text: $maximumMegabytes)
                        .keyboardType(.decimalPad)
                        .onChange(of: maximumMegabytes) { _ in applyCustomSize() }
                }
            }
        }
    }

    /// Index into `SizeRange.presets`, or -1 for a custom range.
    private var sizePresetBinding: Binding<Int> {
        Binding(
            get: {
                guard !isCustomSize else { return -1 }
                return SizeRange.presets.firstIndex { $0.range == viewModel.filter.sizeRange } ?? -1
            },
            set: { index in
                isCustomSize = index < 0
                if index >= 0 {
                    viewModel.filter.sizeRange = SizeRange.presets[index].range
                } else {
                    // Start the custom range at 1 MB so it differs from every preset.
                    minimumMegabytes = "1"
                    maximumMegabytes = ""
                    applyCustomSize()
                }
            }
        )
    }

    private func applyCustomSize() {
        func bytes(_ text: String) -> Int64? {
            let normalized = text.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
            return Int64(exactly: (value * 1_000_000).rounded())
        }
        viewModel.filter.sizeRange = SizeRange(minimumBytes: bytes(minimumMegabytes), maximumBytes: bytes(maximumMegabytes))
    }

    // MARK: - Date

    private var dateSection: some View {
        Section("Date Modified") {
            Picker("Modified", selection: datePresetBinding) {
                ForEach(DateFilter.presets.indices, id: \.self) { index in
                    Text(DateFilter.presets[index].name).tag(index)
                }
                Text("Custom Range").tag(-1)
            }
            if datePresetBinding.wrappedValue == -1 {
                DatePicker("From", selection: $customFrom, displayedComponents: .date)
                    .onChange(of: customFrom) { _ in applyCustomDates() }
                DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: .date)
                    .onChange(of: customTo) { _ in applyCustomDates() }
            }
        }
    }

    private var datePresetBinding: Binding<Int> {
        Binding(
            get: { DateFilter.presets.firstIndex { $0.filter == viewModel.filter.dateFilter } ?? -1 },
            set: { index in
                if index >= 0 {
                    viewModel.filter.dateFilter = DateFilter.presets[index].filter
                } else {
                    applyCustomDates()
                }
            }
        )
    }

    private func applyCustomDates() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: customFrom)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: customTo)) ?? customTo
        viewModel.filter.dateFilter = .custom(from: start, to: endOfDay)
    }

    // MARK: - Location

    private var locationSection: some View {
        Section {
            ForEach(locations) { location in
                Toggle(isOn: locationBinding(location)) {
                    Label(location.name, systemImage: location.systemImage)
                }
            }
            if let folder = viewModel.filter.folderPath {
                HStack {
                    Label((folder as NSString).lastPathComponent, systemImage: "folder")
                    Spacer()
                    Button("Remove") { viewModel.filter.folderPath = nil }
                }
            }
        } header: {
            Text("Location")
        } footer: {
            Text("No selection searches every location.")
        }
    }

    private func locationBinding(_ location: SearchLocation) -> Binding<Bool> {
        Binding(
            get: { viewModel.filter.locationIDs.contains(location.id) },
            set: { isOn in
                if isOn {
                    viewModel.filter.locationIDs.insert(location.id)
                } else {
                    viewModel.filter.locationIDs.remove(location.id)
                }
            }
        )
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section {
            Toggle("Search file contents", isOn: $viewModel.searchContents)
            Toggle("Include folders", isOn: $viewModel.filter.includeFolders)
            Toggle("Include hidden files", isOn: $viewModel.filter.includeHiddenFiles)
        } header: {
            Text("Options")
        } footer: {
            Text("Content search looks inside text-based files (txt, md, csv, json, code…). Hidden files are only found when they were indexed.")
        }
    }

    private func loadCustomValues() {
        let range = viewModel.filter.sizeRange
        if let minimum = range.minimumBytes { minimumMegabytes = String(Double(minimum) / 1_000_000) }
        if let maximum = range.maximumBytes { maximumMegabytes = String(Double(maximum) / 1_000_000) }
        isCustomSize = !SizeRange.presets.contains { $0.range == range }
        if case .custom(let from, let to) = viewModel.filter.dateFilter {
            if let from { customFrom = from }
            if let to { customTo = to }
        }
    }
}
#endif
