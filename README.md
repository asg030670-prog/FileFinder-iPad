# FileFinder-iPad

Advanced file search application for iPad with support for all file types, real-time search, filters, and file preview capabilities.

Built with **SwiftUI** (iPadOS 16+) following an **MVVM** architecture. The search engine,
indexing, persistence and view models live in a platform-independent Swift package
(`FileFinderCore`) that is fully unit tested; the iPad user interface lives in `FileFinderUI`.

> 🇪🇸 **Resumen en español** — FileFinder es una app para iPad que busca ficheros de cualquier tipo
> estén donde estén: en la propia app, en *En mi iPad*, en iCloud Drive, en discos USB o servidores.
> Busca mientras escribes (por nombre, extensión o contenido), permite combinar filtros (tipo, tamaño,
> fecha, ubicación), muestra vista previa y detalles, y permite copiar, mover, renombrar, borrar y
> compartir. Para buscar en todo el iPad abre **Ubicaciones → Añadir carpeta** y elige **En mi iPad**
> (y iCloud Drive si quieres). Consulta [Instalación](#setup) para compilarla con Xcode.

---

## Features

### Search engine
- Searches **every file type** in all indexed locations, including nested folders (unlimited depth).
- **Real-time results** while typing (debounced, cancellable searches).
- Matches **file names**, **extensions** and (optionally) **file contents** of text-based files, with snippets.
- Case- and diacritic-insensitive (`cancion` finds `Canción.mp3`).
- Query syntax:

  | Query | Meaning |
  |-------|---------|
  | `budget 2024` | name contains *budget* **and** *2024* |
  | `.pdf` or `ext:pdf` | only files with that extension |
  | `report .docx` | combine words and extensions |
  | `"annual report"` | exact phrase |

- Relevance ranking (exact name > prefix > word start > substring), or sort by name, date, size or kind.

### Advanced filtering
Combine any of: **kind** (documents, spreadsheets, presentations, images, videos, audio, archives, code, folders, other),
**size range** (presets or custom MB range), **modification date** (today, 7/30/365 days or custom range),
**location**, **enclosing folder**, hidden files and folders on/off. Filters also work without search text
(e.g. “all videos larger than 1 GB modified this month”).

### File management
- Details: name, kind, size, creation/modification dates, location, folder, permissions.
- Preview: QuickLook thumbnails, full QuickLook viewer, text preview for text files.
- Quick actions: **copy**, **move**, **rename**, **delete** (with confirmation), **share**, copy path,
  search in enclosing folder. Copies never overwrite (`Report 2.pdf` is created instead).
- Organise results by grouping them by kind, location or folder.

### User interface
- Three-column `NavigationSplitView` (sidebar · results · details) that adapts to portrait, landscape,
  **Split View**, **Slide Over** and multiple windows.
- Sidebar shortcuts: Search, Recent, Favorites, Search History, Kinds, Locations, Activity Log.
- **Search history** with suggestions while typing, and **favorites/bookmarks** (swipe right on a result).

### Performance & storage
- Background **file index** (an `actor`) built at `.utility` priority; persisted to the Caches directory
  so searches are instant on the next launch.
- **LRU cache** of recent queries, automatically invalidated whenever the index changes.
- Periodic re-indexing when the app becomes active and via **`BGAppRefreshTask`** in the background.
- Memory friendly: compact `FileItem` structs, result limit (default 2 000), lazy lists, thumbnails
  generated only for visible rows and kept in a bounded `NSCache`, bounded content reads.

---

## Accessing files on iPadOS

iPadOS sandboxes every app, so **no app can silently read the whole device**. FileFinder searches:

1. Its own **Documents** folder (visible in *Files › On My iPad › FileFinder*), always included.
2. Any folder you grant access to in **Locations → Add Folder**. Choosing **On My iPad** gives access
   to all local files; you can also add **iCloud Drive**, external **USB drives**, **SMB servers** and
   folders from third‑party providers (Dropbox, Google Drive, OneDrive…).

Access to added folders is stored as **bookmarks**, so it survives app restarts. Photos in the Photos
library are not part of the file system and are not searched.

---

## Architecture

```
┌───────────────────────── FileFinderUI (SwiftUI, iOS only) ─────────────────────────┐
│ FileFinderRootView · SidebarView · SearchResultsView · FilterView · FileDetailView │
│ FavoritesView · HistoryView · LocationsView · ActivityLogView · FileThumbnailView  │
└──────────────────────────────────────┬──────────────────────────────────────────────┘
                                       │ observes (@ObservedObject / @StateObject)
┌──────────────────────────── FileFinderCore (Foundation only) ───────────────────────┐
│ ViewModels   AppEnvironment (composition root) · SearchViewModel ·                  │
│              FileDetailViewModel · FavoritesViewModel · LocationsViewModel          │
│ Services     FileScanner · IndexingService · FileIndex (actor) · SearchEngine ·     │
│              SearchCache (LRU) · ContentSearcher · FileOperationsService ·          │
│              FilePreviewService                                                     │
│ Persistence  SearchHistoryStore · FavoritesStore · LocationStore (bookmarks) ·      │
│              IndexPersistence · KeyValueStore (UserDefaults / in-memory)            │
│ Models       FileItem · FileCategory · SearchQuery · SearchFilter · SearchResult ·  │
│              SearchLocation                                                         │
│ Utilities    FFLogger/LogStore · FileFinderError · ByteSizeFormatter               │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

- **Models** are immutable, `Codable`, `Hashable` and `Sendable` value types.
- **Services** contain all file system logic and use `FileManager` exclusively.
- **View models** are `@MainActor ObservableObject`s; views never touch services directly.
- **Error handling**: every failure is mapped to `FileFinderError` (a `LocalizedError`) and shown in the UI.
- **Logging**: `FFLogger` writes to the unified logging system (`os.Logger`, subsystem
  `com.filefinder.ipad`, categories *Scanner, Index, Search, FileOperations, Persistence, UI*) and keeps
  the last 500 entries in memory for the in-app **Activity Log**. File names are logged as private data.

### Project structure

```
FileFinder-iPad/
├── Package.swift                     # Swift package: FileFinderCore, FileFinderUI, tests
├── Sources/
│   ├── FileFinderCore/
│   │   ├── Configuration/            # AppConfiguration (tunables, JSON loading)
│   │   ├── Models/
│   │   ├── Persistence/
│   │   ├── Services/
│   │   ├── Utilities/
│   │   └── ViewModels/
│   └── FileFinderUI/Views/           # SwiftUI views (compiled for iOS only)
├── Tests/FileFinderCoreTests/        # XCTest unit tests
├── App/
│   ├── project.yml                   # XcodeGen spec for the iPad app target
│   └── FileFinder/                   # @main App, Info.plist, assets, bundled config
├── Config/FileFinderConfig.example.json
└── .github/workflows/ci.yml          # Linux + macOS/iOS CI
```

---

## Setup

### Requirements
- macOS with **Xcode 15 or later** (Swift 5.9+)
- iPad or iPad simulator running **iPadOS 16 or later**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the app project (`brew install xcodegen`)

### Build and run the app
```bash
git clone https://github.com/asg030670-prog/FileFinder-iPad.git
cd FileFinder-iPad/App
xcodegen generate
open FileFinder.xcodeproj
```
In Xcode select the **FileFinder** scheme and an iPad simulator (or your iPad), then press **⌘R**.
To run on a device, select your team under *Signing & Capabilities* (or set `DEVELOPMENT_TEAM` in
`App/project.yml`) and change the bundle identifier if needed.

<details>
<summary>Without XcodeGen</summary>

Create a new *iOS App* project in Xcode (SwiftUI, iPad), delete the generated `ContentView.swift`/App
file, add the files of `App/FileFinder/`, use `App/FileFinder/Info.plist` as the Info.plist, and add
this repository as a local package (*File › Add Package Dependencies… › Add Local…*) linking the
`FileFinderCore` and `FileFinderUI` products.
</details>

### Run the tests
The core module only depends on Foundation, so tests run on macOS **and** Linux:
```bash
swift test
```
You can also open `Package.swift` in Xcode and press **⌘U**.

---

## Configuration

Defaults are compiled in (`AppConfiguration`) and can be overridden by the bundled
`App/FileFinder/FileFinderConfig.json`. Missing keys fall back to defaults. See
[`Config/FileFinderConfig.example.json`](Config/FileFinderConfig.example.json):

| Key | Default | Description |
|-----|---------|-------------|
| `searchDebounceMilliseconds` | `250` | Delay after the last keystroke before searching |
| `maximumResults` | `2000` | Maximum results per query |
| `searchCacheCapacity` | `50` | Number of cached queries (LRU) |
| `maximumHistoryEntries` | `30` | Search history size |
| `maximumContentSearchFileSize` | `10000000` | Larger text files are not searched by content (bytes) |
| `maximumContentSearchFiles` | `5000` | Maximum files read per content search |
| `contentSearchEnabledByDefault` | `false` | Search contents without enabling it in the filters |
| `indexHiddenFiles` | `false` | Index files and folders starting with `.` |
| `excludedDirectoryNames` | `.Trash`, `.git`, … | Folder names never indexed |
| `reindexIntervalMinutes` | `15` | Minimum age of the index before automatic re-indexing |
| `maximumPreviewCharacters` | `5000` | Characters shown in text previews |

---

## License

MIT — see [LICENSE](LICENSE).
