import SwiftUI
import SwiftData

struct CSVImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let csvData: Data
    let filename: String?

    private let maxPreviewRows = 25
    private let maxPreviewColumns = 12

    @State private var parseResult: ParseResult = .empty
    @State private var isImporting = false

    @State private var alertTitle = "Message"
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if parseResult.rows.isEmpty {
                    ContentUnavailableView("No preview available", systemImage: "doc.text")
                } else {
                    previewBody
                }
            }
            .navigationTitle("CSV Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isImporting ? "Importing…" : "Import") {
                        importNow()
                    }
                    .disabled(isImporting)
                }
            }
            .onAppear {
                parseResult = CSVParser.parse(data: csvData, maxRows: maxPreviewRows, maxColumns: maxPreviewColumns)
                if let w = parseResult.warning {
                    alertTitle = "Preview warning"
                    alertMessage = w
                    showAlert = true
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage ?? "Unknown error")
            }
        }
    }

    private var previewBody: some View {
        List {
            Section("File") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(filename ?? "CSV")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Rows shown")
                    Spacer()
                    Text("\(max(0, parseResult.rows.count - (parseResult.hasHeader ? 1 : 0)))")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Columns shown")
                    Spacer()
                    Text("\(parseResult.columnCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Header row")
                    Spacer()
                    Text(parseResult.hasHeader ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
            }

            if parseResult.hasHeader, let header = parseResult.rows.first {
                Section("Headers") {
                    ForEach(Array(header.prefix(parseResult.columnCount)).indices, id: \.self) { idx in
                        Text(header[idx].isEmpty ? "(blank)" : header[idx])
                    }
                }
            }

            Section("Preview") {
                let startIndex = parseResult.hasHeader ? 1 : 0
                let displayRows = Array(parseResult.rows.dropFirst(startIndex))

                ForEach(displayRows.indices, id: \.self) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Row \(r + 1)")
                            .font(.subheadline)
                            .bold()

                        let row = displayRows[r]
                        ForEach(0..<parseResult.columnCount, id: \.self) { c in
                            let value = c < row.count ? row[c] : ""
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                Text(trimmed)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func importNow() {
        isImporting = true
        defer { isImporting = false }

        do {
            let r = try GameCatalogCSVImporter.importCSV(context: context, csvData: csvData)
            alertTitle = "Import complete"
            alertMessage = "Imported/updated \(r.insertedOrUpdated). Skipped \(r.skipped). Removed \(r.removed)."
            showAlert = true
        } catch {
            alertTitle = "Import failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

// MARK: - Lightweight CSV Parser (preview only)

private enum CSVParser {
    static func parse(data: Data, maxRows: Int, maxColumns: Int) -> ParseResult {
        guard let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return .init(rows: [], columnCount: 0, hasHeader: false, warning: "Could not decode file as UTF-8/Latin1.")
        }

        let normalized = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)

        var rows: [[String]] = []
        rows.reserveCapacity(min(lines.count, maxRows + 1))

        for line in lines.prefix(maxRows + 1) {
            rows.append(parseLine(String(line)))
        }

        let columnCount = min(maxColumns, rows.map { $0.count }.max() ?? 0)
        let hasHeader = inferHeader(rows.first)

        var warning: String? = nil
        if columnCount == 0 {
            warning = "No columns detected. Check delimiter/format."
        } else if lines.count > maxRows + 1 {
            warning = "Preview is limited to the first \(maxRows) data rows."
        }

        return .init(rows: rows, columnCount: columnCount, hasHeader: hasHeader, warning: warning)
    }

    private static func parseLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]

            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                } else {
                    inQuotes.toggle()
                    i = line.index(after: i)
                    continue
                }
            }

            if ch == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                i = line.index(after: i)
                continue
            }

            current.append(ch)
            i = line.index(after: i)
        }

        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    private static func inferHeader(_ firstRow: [String]?) -> Bool {
        guard let row = firstRow, !row.isEmpty else { return false }
        let sample = row.prefix(10)
        let nonEmpty = sample.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return false }

        let nonNumericCount = nonEmpty.filter { Double($0) == nil }.count
        return Double(nonNumericCount) / Double(nonEmpty.count) >= 0.7
    }
}

private struct ParseResult {
    let rows: [[String]]
    let columnCount: Int
    let hasHeader: Bool
    let warning: String?

    static let empty = ParseResult(rows: [], columnCount: 0, hasHeader: false, warning: nil)
}
