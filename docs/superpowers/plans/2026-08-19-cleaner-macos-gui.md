# Cleaner для macOS — план реализации

> **Для агентов:** реализовывать по задачам, каждая заканчивается рабочим и
> проверяемым результатом. Шаги отмечаются чекбоксами.

**Цель:** нативное macOS-приложение со списком категорий мусора, галочками и
перемещением выбранного в Корзину.

**Архитектура:** Tuist-проект из трёх таргетов. `CleanerKit` держит всю логику и
не импортирует SwiftUI; приложение не обращается к файловой системе напрямую;
тесты проверяют логику без запуска окна.

**Стек:** Swift 6.3, SwiftUI, Tuist 4.195, XCTest, macOS 26.

## Глобальные ограничения

- Безвозвратного удаления нет нигде: только `FileManager.trashItem`.
- App Sandbox выключен (`com.apple.security.app-sandbox = false`).
- Ни один тест не обращается к настоящему `~` пользователя — только временные каталоги.
- `CleanerKit` не импортирует SwiftUI; приложение не импортирует `Foundation.FileManager` для работы с путями напрямую.
- Deployment target: macOS 26.0.
- Идентификатор бандла: `dev.sobol.Cleaner`.

---

### Задача 1: Каркас Tuist

**Файлы:**
- Создать: `Tuist.swift`, `Project.swift`
- Создать: `Cleaner/Sources/CleanerApp.swift`
- Создать: `CleanerKit/Sources/CleanerKit.swift`
- Создать: `CleanerKitTests/CleanerKitTests.swift`

**Интерфейсы:**
- Производит: три таргета — `CleanerKit` (framework), `Cleaner` (app), `CleanerKitTests` (unit tests).

- [ ] **Шаг 1:** `Tuist.swift` с `Config()`.
- [ ] **Шаг 2:** `Project.swift` с тремя таргетами, bundleId `dev.sobol.Cleaner`, destination `.mac`, deployment target macOS 26.0, entitlements с выключенным сэндбоксом.
- [ ] **Шаг 3:** Заглушки исходников: `CleanerApp.swift` с пустым окном, `CleanerKit.swift` пустой, один тривиальный тест.
- [ ] **Шаг 4:** `tuist generate --no-open` — проект генерируется без ошибок.
- [ ] **Шаг 5:** `tuist build` — сборка проходит.
- [ ] **Шаг 6:** `tuist test` — тривиальный тест проходит.
- [ ] **Шаг 7:** Коммит.

---

### Задача 2: PathGuard

**Файлы:**
- Создать: `CleanerKit/Sources/PathGuard.swift`
- Создать: `CleanerKitTests/PathGuardTests.swift`

**Интерфейсы:**
- Производит:
  - `struct PathGuard { init(allowedRoots: [URL], deniedPaths: [URL]) }`
  - `enum GuardRejection: Error, Equatable { case notAbsolute, symlink, traversal, outsideAllowedRoots, isRootItself, inDenyList, doesNotExist }`
  - `func validate(_ url: URL) -> Result<URL, GuardRejection>`

- [ ] **Шаг 1:** Тесты на отказ: пустой путь, `/`, сам корень из whitelist, путь вне whitelist, путь в стоп-листе, стоп-лист внутри пути, симлинк, `..`, относительный путь, несуществующий путь.
- [ ] **Шаг 2:** Тесты на пропуск: обычный подкаталог внутри разрешённого корня; вложенный глубже.
- [ ] **Шаг 3:** Прогнать — падают (нет типа).
- [ ] **Шаг 4:** Реализовать `PathGuard`: нормализация через `standardizedFileURL`, проверка `resourceValues(forKeys: [.isSymbolicLinkKey])`, префиксное сравнение по компонентам пути (не по строкам — иначе `/a/bc` совпадёт с `/a/b`).
- [ ] **Шаг 5:** Прогнать — проходят.
- [ ] **Шаг 6:** Коммит.

---

### Задача 3: Каталог категорий

**Файлы:**
- Создать: `CleanerKit/Sources/Category.swift`
- Создать: `CleanerKitTests/CategoryTests.swift`

**Интерфейсы:**
- Производит:
  - `struct Category: Identifiable, Sendable { let id: String; let title: String; let consequence: String; let roots: [URL] }`
  - `enum Catalog { static func standard(home: URL) -> [Category]; static func allowedRoots(home: URL) -> [URL]; static func deniedPaths(home: URL) -> [URL] }`

- [ ] **Шаг 1:** Тест: `standard(home:)` возвращает три категории с ожидаемыми id (`derivedData`, `deviceSupport`, `packageCaches`), все корни лежат внутри переданного `home`.
- [ ] **Шаг 2:** Тест: каждый корень каждой категории проходит `PathGuard`, построенный из `allowedRoots`/`deniedPaths` того же `home` — кроме случая, когда корень сам является разрешённым корнем (он должен отклоняться, удаляется только содержимое).
- [ ] **Шаг 3:** Прогнать — падают.
- [ ] **Шаг 4:** Реализовать каталог: пути из спеки, `home` параметром (не `FileManager.default.homeDirectoryForCurrentUser` внутри).
- [ ] **Шаг 5:** Прогнать — проходят.
- [ ] **Шаг 6:** Коммит.

---

### Задача 4: Scanner

**Файлы:**
- Создать: `CleanerKit/Sources/Scanner.swift`
- Создать: `CleanerKitTests/ScannerTests.swift`

**Интерфейсы:**
- Потребляет: `Category`, `PathGuard`.
- Производит:
  - `struct ScanItem: Identifiable, Sendable, Equatable { let id: URL; var url: URL { id }; let sizeBytes: Int64; let modified: Date }`
  - `struct CategoryScan: Identifiable, Sendable { let id: String; let category: Category; let items: [ScanItem]; var totalBytes: Int64 }`
  - `actor Scanner { init(guard: PathGuard); func scan(_ categories: [Category]) async -> [CategoryScan] }`

- [ ] **Шаг 1:** Тест: во временном дереве два подкаталога с файлами известного размера — скан возвращает два элемента, суммарный размер совпадает.
- [ ] **Шаг 2:** Тест: несуществующий корень даёт пустой список, а не ошибку.
- [ ] **Шаг 3:** Тест: элементы, отклонённые `PathGuard` (симлинк), в результат не попадают.
- [ ] **Шаг 4:** Прогнать — падают.
- [ ] **Шаг 5:** Реализовать: обход глубины 1 через `contentsOfDirectory`, размер рекурсивно через `enumerator` с `.totalFileAllocatedSizeKey`, параллельно через `TaskGroup`.
- [ ] **Шаг 6:** Прогнать — проходят.
- [ ] **Шаг 7:** Коммит.

---

### Задача 5: Remover

**Файлы:**
- Создать: `CleanerKit/Sources/Remover.swift`
- Создать: `CleanerKitTests/RemoverTests.swift`

**Интерфейсы:**
- Потребляет: `ScanItem`, `PathGuard`.
- Производит:
  - `protocol FileTrashing: Sendable { func trash(_ url: URL) throws }`
  - `struct SystemTrash: FileTrashing` — поверх `FileManager.trashItem`
  - `struct RemovalOutcome: Sendable { let item: ScanItem; let error: String? }`
  - `struct RemovalReport: Sendable { let moved: [RemovalOutcome]; let failed: [RemovalOutcome]; var movedBytes: Int64 }`
  - `struct Remover { init(guard: PathGuard, trash: FileTrashing); func remove(_ items: [ScanItem]) async -> RemovalReport }`

- [ ] **Шаг 1:** Тест: подставной `FileTrashing` записывает вызовы; два валидных элемента → оба в `moved`, обработчик вызван дважды.
- [ ] **Шаг 2:** Тест повторной валидации: элемент был просканирован, но к моменту удаления путь стал стоп-листом → в `failed`, подставной обработчик **не вызван**.
- [ ] **Шаг 3:** Тест: ошибка обработчика на одном элементе не мешает остальным.
- [ ] **Шаг 4:** Прогнать — падают.
- [ ] **Шаг 5:** Реализовать: перед каждым удалением `guard.validate`, ошибки собираются, не бросаются.
- [ ] **Шаг 6:** Прогнать — проходят.
- [ ] **Шаг 7:** Коммит.

---

### Задача 6: Интерфейс

**Файлы:**
- Создать: `Cleaner/Sources/CleanerModel.swift`
- Изменить: `Cleaner/Sources/CleanerApp.swift`
- Создать: `Cleaner/Sources/ContentView.swift`

**Интерфейсы:**
- Потребляет: `Catalog`, `Scanner`, `Remover`, `SystemTrash`.
- Производит: `@MainActor @Observable final class CleanerModel` с `phase`, `scans`, `selection`, `report`, методами `scan()` и `removeSelected()`.

- [ ] **Шаг 1:** `CleanerModel`: фазы `idle/scanning/results/removing/done`, множество выбранных `URL`, вычисляемый размер выбранного. Ничего не выбрано по умолчанию.
- [ ] **Шаг 2:** `ContentView`: список категорий с галочками, размером и текстом последствия; футер с итогом и кнопкой; кнопка неактивна при пустом выборе.
- [ ] **Шаг 3:** Лист подтверждения со списком и итоговым размером; кнопка «Переместить в Корзину».
- [ ] **Шаг 4:** Экран отчёта: сколько перемещено, сколько не удалось, с раскрытием ошибок.
- [ ] **Шаг 5:** `tuist build` проходит.
- [ ] **Шаг 6:** Коммит.

---

### Задача 7: Проверка на реальной машине

- [ ] **Шаг 1:** `tuist test` — все тесты проходят.
- [ ] **Шаг 2:** Запустить приложение, снять скриншот со списком реальных категорий.
- [ ] **Шаг 3:** Сверить размеры с `du -sh` по тем же путям.
- [ ] **Шаг 4:** Проверить перемещение в Корзину на одном безопасном элементе и возврат кнопкой «Положить обратно».
- [ ] **Шаг 5:** Написать корневой `README.md`.
- [ ] **Шаг 6:** Коммит.
