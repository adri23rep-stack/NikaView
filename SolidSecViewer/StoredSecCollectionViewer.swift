import SwiftUI
import UIKit
import Combine
import AVKit

private actor ThumbnailDecryptGate {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.permits = max(1, limit)
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            let continuation = waiters.removeFirst()
            continuation.resume()
        }
    }
}

struct StoredSecCollectionItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sourceEntry: PrivateVaultEntry

    var displayExtension: String {
        URL(fileURLWithPath: name).pathExtension.lowercased()
    }

    var isImage: Bool {
        [
            "jpg", "jpeg", "png", "webp", "bmp", "gif",
            "heic", "heif", "tif", "tiff"
        ].contains(displayExtension)
    }

    var isVideo: Bool {
        [
            "mp4", "mov", "m4v", "mkv", "webm", "avi",
            "3gp", "ts", "m2ts", "mpg", "mpeg"
        ].contains(displayExtension)
    }
}

enum StoredSecRekeyError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}

@MainActor
final class StoredSecCollectionSession: ObservableObject {
    @Published private(set) var items: [StoredSecCollectionItem] = []
    @Published private(set) var isUnlocked = false
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private weak var privateVault: PrivateVaultSession?
    private var key = Data()
    private var salt = Data()
    private var iv = Data()
    private var operationGeneration: UInt64 = 0
    private let thumbnailCache = NSCache<NSUUID, UIImage>()
    private let thumbnailGate = ThumbnailDecryptGate(limit: 3)
    private let videoThumbnailGate = ThumbnailDecryptGate(limit: 1)
    private var activeVideoPlaybacks: [UUID: StoredSecVideoPlayback] = [:]

    init() {
        thumbnailCache.countLimit = 160
        thumbnailCache.totalCostLimit = 96 * 1024 * 1024
    }

    func unlock(
        folder: PrivateVaultEntry,
        privateVault: PrivateVaultSession,
        password: String
    ) async {
        isBusy = true
        errorMessage = nil
        operationGeneration &+= 1
        let operation = operationGeneration

        do {
            let children = privateVault.children(of: folder.id)
                .filter { $0.kind == .file }

            var foundKey: Data?
            var foundSalt: Data?
            var foundIV: Data?
            var derivedKeysByHeader: [Data: Data] = [:]

            for entry in children where
                entry.originalSize == Int64(SecCollectionCrypto.headerSize)
            {
                let raw = try await privateVault.decryptFileDataAsync(
                    entry,
                    maxPlaintextBytes: 1024 * 1024
                )

                guard operation == operationGeneration else {
                    throw PrivateVaultError.locked
                }

                guard raw.count == SecCollectionCrypto.headerSize else {
                    continue
                }

                let candidateSalt = Data(raw[0..<16])
                let candidateIV = Data(raw[16..<32])
                let cryptHeader = Data(raw[0..<32])
                let candidateKey: Data

                if let cached = derivedKeysByHeader[cryptHeader] {
                    candidateKey = cached
                } else {
                    let derived = try SecCollectionCrypto.deriveKey(
                        password: password,
                        salt: candidateSalt
                    )
                    derivedKeysByHeader[cryptHeader] = derived
                    candidateKey = derived
                }

                guard
                    let encryptedName = SecCollectionCrypto.decodeBase64URL(entry.name),
                    let plainNameData = try? SecCollectionCrypto.aesCTR(
                        encryptedName,
                        key: candidateKey,
                        iv: candidateIV
                    ),
                    let plainName = String(
                        data: plainNameData,
                        encoding: .utf8
                    ),
                    plainName == ".key"
                else {
                    continue
                }

                foundKey = candidateKey
                foundSalt = candidateSalt
                foundIV = candidateIV
                break
            }

            guard
                let foundKey,
                let foundSalt,
                let foundIV
            else {
                throw SecCollectionCryptoError.badPasswordOrUnsupported
            }

            let decodedItems = try await Task.detached(priority: .userInitiated) {
                try Self.decodeItems(
                    children: children,
                    key: foundKey,
                    iv: foundIV
                )
            }.value

            guard operation == operationGeneration else {
                throw PrivateVaultError.locked
            }

            self.privateVault = privateVault
            self.key = foundKey
            self.salt = foundSalt
            self.iv = foundIV
            self.items = decodedItems
            self.isUnlocked = true
        } catch {
            if operation == operationGeneration {
                self.errorMessage = error.localizedDescription
                self.items = []
                self.isUnlocked = false
                zeroize()
            }
        }

        if operation == operationGeneration {
            isBusy = false
        }
    }

    /// Crea una copia de la colección re-cifrada con una contraseña nueva. La
    /// original no se toca: solo se borra si el usuario lo decide después. Si
    /// algo falla o se cancela, la copia incompleta se elimina.
    func makeRekeyedCopy(
        of folder: PrivateVaultEntry,
        newPassword: String,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> PrivateVaultEntry {
        guard isUnlocked, let privateVault else {
            throw SecCollectionCryptoError.badPasswordOrUnsupported
        }

        let operation = operationGeneration
        let oldKey = key
        let oldSalt = salt
        let oldIV = iv
        let children = privateVault.children(of: folder.id)
            .filter { $0.kind == .file }

        // 1. Localizar el archivo .key y conservar el resto de su cabecera.
        var keyEntryID: UUID?
        var headerTail = Data(count: SecCollectionCrypto.headerSize - 32)

        for entry in children where entry.originalSize == Int64(SecCollectionCrypto.headerSize) {
            guard
                let encryptedName = SecCollectionCrypto.decodeBase64URL(entry.name),
                let nameData = try? SecCollectionCrypto.aesCTR(
                    encryptedName,
                    key: oldKey,
                    iv: oldIV
                ),
                String(data: nameData, encoding: .utf8) == ".key"
            else {
                continue
            }

            let raw = try await privateVault.decryptFileDataAsync(
                entry,
                maxPlaintextBytes: 1024 * 1024
            )

            guard
                raw.count == SecCollectionCrypto.headerSize,
                raw.prefix(32) == oldSalt + oldIV
            else {
                continue
            }

            keyEntryID = entry.id
            headerTail = Data(raw.suffix(SecCollectionCrypto.headerSize - 32))
            break
        }

        guard let keyEntryID else {
            throw SecCollectionCryptoError.badHeader
        }

        // 2. Sal, IV y clave nuevos.
        let newSalt = try PrivateVaultCrypto.randomData(count: SecCollectionCrypto.saltSize)
        let newIV = try PrivateVaultCrypto.randomData(count: SecCollectionCrypto.ivSize)
        let newKey = try await Task.detached(priority: .userInitiated) {
            try SecCollectionCrypto.deriveKey(password: newPassword, salt: newSalt)
        }.value
        let newHeader = newSalt + newIV + headerTail

        // 3. Carpeta nueva junto a la original.
        let parent = folder.parentID
        let before = Set(privateVault.children(of: parent).map(\.id))

        privateVault.errorMessage = nil
        privateVault.createFolder(
            name: Self.rekeyedFolderName(for: folder.name),
            parentID: parent
        )

        if let message = privateVault.errorMessage {
            throw StoredSecRekeyError.message(message)
        }

        guard let newFolder = privateVault.children(of: parent).first(where: {
            !before.contains($0.id) && $0.kind == .folder
        }) else {
            throw StoredSecRekeyError.message(
                "No se pudo crear la carpeta nueva en la bóveda."
            )
        }

        let namesByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.sourceEntry.id, $0.name) }
        )

        do {
            for (index, entry) in children.enumerated() {
                try Task.checkCancellation()

                guard isUnlocked, operation == operationGeneration else {
                    throw PrivateVaultError.locked
                }

                let plainName: String

                if entry.id == keyEntryID {
                    plainName = ".key"
                } else if let known = namesByID[entry.id] {
                    plainName = known
                } else {
                    throw StoredSecRekeyError.message(
                        "Hay un archivo cuyo nombre no se puede leer; no se creó la copia."
                    )
                }

                let encryptedName = try SecCollectionCrypto.aesCTR(
                    Data(plainName.utf8),
                    key: newKey,
                    iv: newIV
                )
                let newName = SecCollectionCrypto.encodeBase64URL(encryptedName)

                let workDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "NikaidoRekey-" + UUID().uuidString,
                        isDirectory: true
                    )
                try FileManager.default.createDirectory(
                    at: workDirectory,
                    withIntermediateDirectories: true
                )
                defer { try? FileManager.default.removeItem(at: workDirectory) }

                let output = workDirectory.appendingPathComponent(newName)

                if entry.id == keyEntryID {
                    try newHeader.write(
                        to: output,
                        options: [.atomic, .completeFileProtection]
                    )
                } else {
                    let temporary = try await privateVault.makeTemporaryDecryptedCopy(
                        of: entry
                    )
                    defer { privateVault.releaseTemporaryPlaintext(temporary) }

                    try await Task.detached(priority: .userInitiated) {
                        try Self.rekeyFile(
                            input: temporary,
                            output: output,
                            oldSalt: oldSalt,
                            oldIV: oldIV,
                            oldKey: oldKey,
                            newKey: newKey,
                            newIV: newIV,
                            newHeader: newHeader
                        )
                    }.value
                }

                privateVault.errorMessage = nil
                await privateVault.importFiles(
                    urls: [output],
                    parentID: newFolder.id
                )

                if let message = privateVault.errorMessage {
                    throw StoredSecRekeyError.message(message)
                }

                progress(index + 1, children.count)
            }
        } catch {
            privateVault.delete(newFolder)
            throw error
        }

        return newFolder
    }

    private static func rekeyedFolderName(for name: String) -> String {
        let base = name.lowercased().hasSuffix(".sec")
            ? String(name.dropLast(4))
            : name

        return base + " (nueva contraseña).sec"
    }

    /// Re-cifra un archivo .sec por bloques (sin cargarlo completo en memoria).
    nonisolated private static func rekeyFile(
        input: URL,
        output: URL,
        oldSalt: Data,
        oldIV: Data,
        oldKey: Data,
        newKey: Data,
        newIV: Data,
        newHeader: Data
    ) throws {
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }

        guard
            let header = try reader.read(upToCount: SecCollectionCrypto.headerSize),
            header.count == SecCollectionCrypto.headerSize,
            header.prefix(32) == oldSalt + oldIV
        else {
            throw SecCollectionCryptoError.badHeader
        }

        guard FileManager.default.createFile(
            atPath: output.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw StoredSecRekeyError.message("No se pudo crear un archivo temporal.")
        }

        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }

        try writer.write(contentsOf: newHeader)

        var offset: Int64 = 0

        while true {
            guard
                let chunk = try reader.read(upToCount: 1_048_576),
                !chunk.isEmpty
            else {
                break
            }

            let plain = try SecCollectionCrypto.aesCTR(
                chunk,
                key: oldKey,
                iv: oldIV,
                streamOffset: offset
            )
            let cipher = try SecCollectionCrypto.aesCTR(
                plain,
                key: newKey,
                iv: newIV,
                streamOffset: offset
            )

            try writer.write(contentsOf: cipher)
            offset += Int64(chunk.count)
        }
    }

    func decrypt(
        _ item: StoredSecCollectionItem,
        maxPlaintextBytes: Int = 512 * 1024 * 1024
    ) async throws -> Data {
        guard
            isUnlocked,
            let privateVault
        else {
            throw SecCollectionCryptoError.badPasswordOrUnsupported
        }

        let operation = operationGeneration
        let raw = try await privateVault.decryptFileDataAsync(
            item.sourceEntry,
            maxPlaintextBytes: maxPlaintextBytes
        )

        guard
            isUnlocked,
            operation == operationGeneration
        else {
            throw PrivateVaultError.locked
        }

        let keyCopy = key
        let saltCopy = salt
        let ivCopy = iv

        let plaintext = try await Task.detached(priority: .userInitiated) {
            try Self.decryptInnerSecFile(
                raw: raw,
                key: keyCopy,
                salt: saltCopy,
                iv: ivCopy
            )
        }.value

        guard
            isUnlocked,
            operation == operationGeneration
        else {
            throw PrivateVaultError.locked
        }

        return plaintext
    }

    func thumbnail(for item: StoredSecCollectionItem) async -> UIImage? {
        let cacheKey = item.id as NSUUID

        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        if item.isImage {
            await thumbnailGate.acquire()

            if Task.isCancelled {
                await thumbnailGate.release()
                return nil
            }

            let result: UIImage?
            do {
                // Keep scroll bursts bounded: a thumbnail should not decrypt a
                // hundreds-of-megabytes source merely because it became visible.
                let data = try await decrypt(
                    item,
                    maxPlaintextBytes: 64 * 1024 * 1024
                )

                if Task.isCancelled {
                    result = nil
                } else if let image = ImageDownsampler.thumbnail(from: data) {
                    cacheThumbnail(image, forKey: cacheKey)
                    result = image
                } else {
                    result = nil
                }
            } catch {
                result = nil
            }

            await thumbnailGate.release()
            return result
        }

        guard item.isVideo, let privateVault else {
            return nil
        }

        // Video poster frames are derived sensitive data. If one already exists,
        // it is loaded from Nikaido Vault's AES-GCM encrypted thumbnail cache.
        if
            let cachedData = await privateVault.cachedThumbnailData(
                for: item.sourceEntry
            ),
            let cachedImage = UIImage(data: cachedData)
        {
            cacheThumbnail(cachedImage, forKey: cacheKey)
            return cachedImage
        }

        // Only one legacy video is prepared at a time. Old v0.6-v0.8.1 blobs
        // may require one full authenticated pass to establish safe random
        // access. Scrolling away cancels that pass instead of indexing blindly.
        await videoThumbnailGate.acquire()

        if Task.isCancelled {
            await videoThumbnailGate.release()
            return nil
        }

        // A previous waiter may have generated the thumbnail while this task
        // was queued.
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            await videoThumbnailGate.release()
            return cached
        }

        let operation = operationGeneration
        let keyCopy = key
        let saltCopy = salt
        let ivCopy = iv
        let result: UIImage?

        do {
            let descriptor = try await privateVault.prepareRandomAccess(
                for: item.sourceEntry
            )

            guard
                isUnlocked,
                operation == operationGeneration,
                !Task.isCancelled
            else {
                throw PrivateVaultError.locked
            }

            let jpeg = try await StoredSecVideoThumbnailGenerator.generateJPEG(
                descriptor: descriptor,
                secKey: keyCopy,
                secSalt: saltCopy,
                secIV: ivCopy,
                filename: item.name
            )

            guard
                isUnlocked,
                operation == operationGeneration,
                !Task.isCancelled
            else {
                throw PrivateVaultError.locked
            }

            if let image = UIImage(data: jpeg) {
                cacheThumbnail(image, forKey: cacheKey)

                await privateVault.storeCachedThumbnailData(
                    jpeg,
                    for: item.sourceEntry
                )

                result = image
            } else {
                result = nil
            }
        } catch {
            result = nil
        }

        await videoThumbnailGate.release()
        return result
    }

    private func cacheThumbnail(
        _ image: UIImage,
        forKey cacheKey: NSUUID
    ) {
        let cost = Int(
            image.size.width
            * image.size.height
            * image.scale
            * image.scale
            * 4
        )

        thumbnailCache.setObject(
            image,
            forKey: cacheKey,
            cost: max(cost, 1)
        )
    }


    func makeVideoPlayback(
        for item: StoredSecCollectionItem
    ) async throws -> StoredSecVideoPlayback {
        guard item.isVideo else {
            throw StoredSecVideoError.notVideo
        }

        guard
            isUnlocked,
            let privateVault
        else {
            throw PrivateVaultError.locked
        }

        let operation = operationGeneration

        // For an existing v0.6.x video this may perform one full authenticated
        // verification pass. It updates only encrypted index metadata and never
        // rewrites the multi-GB blob.
        let descriptor = try await privateVault.prepareRandomAccess(
            for: item.sourceEntry
        )

        guard
            isUnlocked,
            operation == operationGeneration
        else {
            throw PrivateVaultError.locked
        }

        // Un solo video a la vez: al abrir otro se detienen los anteriores.
        for previous in activeVideoPlaybacks.values {
            previous.invalidate()
        }
        activeVideoPlaybacks.removeAll(keepingCapacity: true)

        let playback = try StoredSecVideoPlayback(
            descriptor: descriptor,
            secKey: key,
            secSalt: salt,
            secIV: iv,
            filename: item.name
        )

        activeVideoPlaybacks[playback.id] = playback
        return playback
    }

    func stopVideoPlayback(_ playback: StoredSecVideoPlayback?) {
        guard let playback else { return }

        playback.invalidate()
        activeVideoPlaybacks.removeValue(forKey: playback.id)
    }

    func lock() {
        operationGeneration &+= 1

        for playback in activeVideoPlaybacks.values {
            playback.invalidate()
        }
        activeVideoPlaybacks.removeAll(keepingCapacity: false)

        items = []
        isUnlocked = false
        errorMessage = nil
        privateVault = nil
        thumbnailCache.removeAllObjects()
        zeroize()
    }

    nonisolated private static func decodeItems(
        children: [PrivateVaultEntry],
        key: Data,
        iv: Data
    ) throws -> [StoredSecCollectionItem] {
        var decodedItems: [StoredSecCollectionItem] = []
        decodedItems.reserveCapacity(children.count)

        for entry in children {
            guard
                let encryptedName = SecCollectionCrypto.decodeBase64URL(entry.name),
                let plainNameData = try? SecCollectionCrypto.aesCTR(
                    encryptedName,
                    key: key,
                    iv: iv
                ),
                let plainName = String(
                    data: plainNameData,
                    encoding: .utf8
                ),
                plainName != ".key"
            else {
                continue
            }

            decodedItems.append(
                StoredSecCollectionItem(
                    id: entry.id,
                    name: plainName,
                    sourceEntry: entry
                )
            )
        }

        decodedItems.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return decodedItems
    }

    nonisolated private static func decryptInnerSecFile(
        raw: Data,
        key: Data,
        salt: Data,
        iv: Data
    ) throws -> Data {
        guard raw.count >= SecCollectionCrypto.headerSize else {
            throw SecCollectionCryptoError.badHeader
        }

        let expected = salt + iv
        guard raw.prefix(32) == expected else {
            throw SecCollectionCryptoError.badHeader
        }

        let ciphertext = raw.dropFirst(SecCollectionCrypto.headerSize)
        return try SecCollectionCrypto.aesCTR(
            Data(ciphertext),
            key: key,
            iv: iv
        )
    }

    private func zeroize() {
        for buffer in [key, salt, iv] {
            _ = buffer
        }

        if !key.isEmpty {
            key.resetBytes(in: 0..<key.count)
        }

        if !salt.isEmpty {
            salt.resetBytes(in: 0..<salt.count)
        }

        if !iv.isEmpty {
            iv.resetBytes(in: 0..<iv.count)
        }

        key.removeAll(keepingCapacity: false)
        salt.removeAll(keepingCapacity: false)
        iv.removeAll(keepingCapacity: false)
    }
}

struct StoredSecFolderViewer: View {
    @ObservedObject var privateVault: PrivateVaultSession

    let folder: PrivateVaultEntry

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = StoredSecCollectionSession()

    @State private var password = ""
    @State private var selectedItem: StoredSecCollectionItem?
    @State private var search = ""
    @State private var showHidden = false
    @State private var showPasswordPanel = false
    @State private var faceIDEnabled = false
    @State private var isFaceIDBusy = false
    @State private var showFaceIDOffer = false
    @State private var pendingFaceIDPassword: String?
    @State private var faceIDNotice: String?
    @State private var showRekey = false

    @Environment(\.nikaidoAccent) private var nikaidoAccent

    private var visibleItems: [StoredSecCollectionItem] {
        session.items.filter { item in
            (showHidden || !item.name.hasPrefix(".")) &&
            (search.isEmpty || item.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.isUnlocked {
                    gallery
                } else {
                    unlock
                }
            }
            .navigationTitle(folder.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if session.isUnlocked {
                        Menu {
                            Button {
                                showRekey = true
                            } label: {
                                Label(
                                    "Cambiar contraseña .sec",
                                    systemImage: "key.horizontal"
                                )
                            }

                            if faceIDEnabled {
                                Button(role: .destructive) {
                                    NikaidoSecFaceID.disable(folder.id)
                                    faceIDEnabled = false
                                } label: {
                                    Label(
                                        "Olvidar Face ID de esta colección",
                                        systemImage: "faceid"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        session.lock()
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            StoredSecCollectionMediaViewer(
                session: session,
                item: item
            )
        }
        .sheet(isPresented: $showRekey) {
            StoredSecRekeyView(
                session: session,
                privateVault: privateVault,
                folder: folder
            ) { deletedOriginal in
                if deletedOriginal {
                    selectedItem = nil
                    session.lock()
                    dismiss()
                }
            }
        }
        .alert(
            "¿Usar Face ID para esta colección?",
            isPresented: $showFaceIDOffer
        ) {
            Button("Guardar y usar Face ID") {
                enableFaceID()
            }

            Button("Ahora no", role: .cancel) {
                pendingFaceIDPassword = nil
            }
        } message: {
            Text("La contraseña .sec se guarda cifrada y oculta en el Llavero de este iPhone, protegida por Face ID. La próxima vez podrás elegir Face ID o contraseña.")
        }
        .alert(
            "Colección .sec",
            isPresented: Binding(
                get: { faceIDNotice != nil },
                set: { if !$0 { faceIDNotice = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {
                faceIDNotice = nil
            }
        } message: {
            Text(faceIDNotice ?? "")
        }
        .onAppear {
            faceIDEnabled = NikaidoSecFaceID.isEnabled(folder.id)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification
        )) { _ in
            selectedItem = nil
            session.lock()
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .nikaidoVaultDidLock
        )) { _ in
            selectedItem = nil
            session.lock()
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIScreen.capturedDidChangeNotification
        )) { notification in
            let captured =
                (notification.object as? UIScreen)?.isCaptured
                ?? PrivacyShield.isScreenCaptureActive()

            if captured {
                selectedItem = nil
                session.lock()
                dismiss()
            }
        }
        .onDisappear {
            session.lock()
        }
    }

    private var passwordPanelVisible: Bool {
        !faceIDEnabled || showPasswordPanel
    }

    private func secOptionCard(
        symbol: String,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isEnabled ? nikaidoAccent : Color.secondary)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle().fill(
                            (isEnabled ? nikaidoAccent : Color.secondary).opacity(0.18)
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var unlock: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "lock.square.stack.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(
                        RoundedRectangle(cornerRadius: 27, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [nikaidoAccent, nikaidoAccent.nikaidoDarkened(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: nikaidoAccent.opacity(0.35), radius: 12, y: 7)
                    .padding(.top, 16)

                Text("Colección .sec cifrada")
                    .font(.title2.bold())

                Text(
                    "Elige cómo abrirla. Los archivos siguen guardados "
                    + "cifrados dentro de Nikaido Vault y solo se descifra "
                    + "en RAM el que necesitas."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

                VStack(spacing: 10) {
                    secOptionCard(
                        symbol: "faceid",
                        title: "Face ID",
                        subtitle: faceIDEnabled
                            ? "Abre con tu rostro"
                            : "Se activa después de abrirla una vez con la contraseña",
                        isEnabled: faceIDEnabled && !isFaceIDBusy && !session.isBusy
                    ) {
                        unlockWithFaceID()
                    }

                    secOptionCard(
                        symbol: "key.fill",
                        title: "Contraseña .sec",
                        subtitle: "Escribe la contraseña de esta colección",
                        isEnabled: !session.isBusy
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPasswordPanel.toggle()
                        }
                    }
                }

                if passwordPanelVisible {
                    VStack(spacing: 12) {
                        SecureField("Contraseña de formato .sec", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .nikaidoField()

                        Button("Abrir galería") {
                            submitPassword()
                        }
                        .buttonStyle(NikaidoPrimaryButtonStyle())
                        .padding(.horizontal, -28)
                        .disabled(password.isEmpty || session.isBusy)
                    }
                }

                if session.isBusy || isFaceIDBusy {
                    ProgressView("Descifrando nombres…")
                }

                if let error = session.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [
                    nikaidoAccent.opacity(0.20),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    private func submitPassword() {
        Task {
            let typed = password

            await session.unlock(
                folder: folder,
                privateVault: privateVault,
                password: typed
            )

            if session.isUnlocked {
                password = ""
                showPasswordPanel = false

                if !faceIDEnabled && NikaidoUnlockPreference.biometricsAvailable {
                    pendingFaceIDPassword = typed
                    showFaceIDOffer = true
                }
            }
        }
    }

    private func unlockWithFaceID() {
        guard faceIDEnabled, !isFaceIDBusy, !session.isBusy else { return }

        isFaceIDBusy = true

        Task { @MainActor in
            let result = await NikaidoUnlockPreference.loadPassword(
                reason: "Abrir \(folder.name)",
                account: NikaidoSecFaceID.account(for: folder.id)
            )

            switch result {
            case .success(let storedPassword):
                await session.unlock(
                    folder: folder,
                    privateVault: privateVault,
                    password: storedPassword
                )

                if !session.isUnlocked {
                    NikaidoSecFaceID.disable(folder.id)
                    faceIDEnabled = false
                    showPasswordPanel = true
                    session.errorMessage = nil
                    faceIDNotice = "La contraseña guardada ya no abre esta colección. Escríbela otra vez."
                }
            case .cancelled:
                break
            case .fallback:
                showPasswordPanel = true
            case .invalidated:
                NikaidoSecFaceID.disable(folder.id)
                faceIDEnabled = false
                showPasswordPanel = true
                faceIDNotice = "Face ID cambió o ya no está disponible. Escribe la contraseña."
            case .failed(let message):
                showPasswordPanel = true
                faceIDNotice = message
            }

            isFaceIDBusy = false
        }
    }

    private func enableFaceID() {
        guard let typed = pendingFaceIDPassword else { return }
        pendingFaceIDPassword = nil

        Task { @MainActor in
            let result = await NikaidoUnlockPreference.enableBiometric(
                password: typed,
                account: NikaidoSecFaceID.account(for: folder.id)
            )

            if case .enabled = result {
                NikaidoSecFaceID.enable(folder.id)
                faceIDEnabled = true
            } else {
                faceIDNotice = result.message
            }
        }
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Buscar", text: $search)
                    .textFieldStyle(.roundedBorder)

                Toggle("Ocultos", isOn: $showHidden)
                    .labelsHidden()
                    .accessibilityLabel("Mostrar archivos ocultos")
            }
            .padding(8)

            Text("\(visibleItems.count) de \(session.items.count) elementos")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)

            if visibleItems.contains(where: { $0.isVideo }) {
                Text(
                    "Las miniaturas de video se guardan cifradas. "
                    + "Un video antiguo puede tardar una sola vez en preparar su poster."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            } else {
                Spacer()
                    .frame(height: 4)
            }

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 115), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(visibleItems) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            VStack(spacing: 6) {
                                StoredSecCollectionThumbnail(
                                    session: session,
                                    item: item
                                )

                                Text(item.name)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}

struct StoredSecCollectionThumbnail: View {
    @ObservedObject var session: StoredSecCollectionSession
    let item: StoredSecCollectionItem

    @State private var image: UIImage?
    @State private var isLoading = false

    /// Contenido dibujado sobre un contenedor de tamaño fijo para que la imagen
    /// escalada nunca desborde su celda ni se encime con las vecinas.
    private var thumbnailContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(
                    systemName: item.isVideo
                    ? "film.fill"
                    : item.isImage
                        ? "photo.fill"
                        : "doc.fill"
                )
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            }

            if isLoading && image == nil {
                ProgressView()
                    .tint(.white)
                    .padding(8)
                    .background(.black.opacity(0.40))
                    .clipShape(Circle())
            }

            if item.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: image == nil ? 30 : 36))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .opacity(isLoading && image == nil ? 0.45 : 0.95)
            }
        }
    }

    var body: some View {
        Color.clear
        .aspectRatio(1.15, contentMode: .fit)
        .overlay {
            thumbnailContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: item.id) {
            guard item.isImage || item.isVideo else { return }

            isLoading = true
            image = await session.thumbnail(for: item)
            isLoading = false
        }
    }
}

struct StoredSecCollectionMediaViewer: View {
    @ObservedObject var session: StoredSecCollectionSession
    let item: StoredSecCollectionItem

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var playback: StoredSecVideoPlayback?
    @State private var errorText: String?
    @State private var isPreparingVideo = false
    @State private var viewerIsActive = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                if let image {
                    ZoomableImage(image: image)
                } else if let playback {
                    VideoPlayer(player: playback.player)
                        .ignoresSafeArea()
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.yellow)

                        Text(errorText)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if item.isVideo && isPreparingVideo {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)

                        Text("Preparando video cifrado…")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(
                            "La primera reproducción de un video importado con "
                            + "v0.6.x verifica su blob completo una sola vez. "
                            + "No crea otra copia ni mueve tus archivos."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }

            Button {
                viewerIsActive = false
                session.stopVideoPlayback(playback)
                playback = nil
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .padding()
        }
        .task(id: item.id) {
            viewerIsActive = true
            session.stopVideoPlayback(playback)
            playback = nil

            do {
                if item.isImage {
                    let data = try await session.decrypt(item)

                    guard let decoded = UIImage(data: data) else {
                        errorText = "iOS no pudo decodificar esta imagen."
                        return
                    }

                    image = decoded
                    return
                }

                if item.isVideo {
                    isPreparingVideo = true
                    defer { isPreparingVideo = false }

                    let prepared = try await session.makeVideoPlayback(
                        for: item
                    )

                    // Si el visor se cerró (o se cambió de video) mientras se
                    // preparaba, no se reproduce: se libera de inmediato para
                    // que ningún audio se quede sonando en segundo plano.
                    guard viewerIsActive, !Task.isCancelled else {
                        session.stopVideoPlayback(prepared)
                        return
                    }

                    playback = prepared
                    prepared.play()
                    return
                }

                errorText = "Este tipo de archivo aún no tiene visor."
            } catch {
                errorText = error.localizedDescription
            }
        }
        .onDisappear {
            viewerIsActive = false
            session.stopVideoPlayback(playback)
            playback = nil
        }
    }
}


// MARK: - Cambiar la contraseña de una colección .sec

struct StoredSecRekeyView: View {
    @ObservedObject var session: StoredSecCollectionSession
    @ObservedObject var privateVault: PrivateVaultSession

    let folder: PrivateVaultEntry
    let onFinished: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nikaidoAccent) private var nikaidoAccent

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isRunning = false
    @State private var done = 0
    @State private var total = 0
    @State private var errorText: String?
    @State private var createdFolder: PrivateVaultEntry?
    @State private var task: Task<Void, Never>?
    @State private var confirmDelete = false

    private var canStart: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword && !isRunning
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let createdFolder {
                        finishedContent(createdFolder)
                    } else {
                        formContent
                    }
                }
                .padding(20)
            }
            .navigationTitle("Cambiar contraseña .sec")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdFolder == nil ? "Cancelar" : "Cerrar") {
                        task?.cancel()
                        onFinished(false)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "¿Borrar la colección anterior?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Borrar la anterior", role: .destructive) {
                    deleteOriginal()
                }

                Button("Conservar ambas", role: .cancel) {}
            } message: {
                Text("La copia nueva ya abre con la contraseña nueva. La anterior se borra de la bóveda.")
            }
        }
        .interactiveDismissDisabled(isRunning)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Se crea una copia de la colección cifrada con la contraseña nueva. La original no se toca hasta que tú decidas borrarla.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Contraseña nueva", text: $newPassword)
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .nikaidoField()

            SecureField("Repite la contraseña nueva", text: $confirmPassword)
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .nikaidoField()

            if !confirmPassword.isEmpty && newPassword != confirmPassword {
                Text("Las contraseñas no coinciden.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(
                        value: Double(done),
                        total: Double(max(total, 1))
                    )

                    Text("Re-cifrando archivo \(done) de \(total)…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Detener y descartar la copia", role: .destructive) {
                        task?.cancel()
                    }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("Crear copia con la contraseña nueva") {
                start()
            }
            .buttonStyle(NikaidoPrimaryButtonStyle())
            .padding(.horizontal, -28)
            .disabled(!canStart)

            Text("Mantén la app abierta mientras se re-cifra. Si la bloqueas o sales, la copia incompleta se descarta.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func finishedContent(_ created: PrivateVaultEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .fill(nikaidoAccent)
                )

            Text("Copia creada")
                .font(.title2.bold())

            Text("“\(created.name)” abre con la contraseña nueva. Comprueba que se abre bien y luego decide qué hacer con la anterior.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if NikaidoSecFaceID.isEnabled(folder.id) {
                Text("Para usar Face ID en la copia nueva, ábrela una vez con su contraseña y acepta guardarla.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Borrar la colección anterior", role: .destructive) {
                confirmDelete = true
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .buttonStyle(.bordered)

            Button("Conservar ambas") {
                onFinished(false)
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
    }

    private func start() {
        guard canStart else { return }

        isRunning = true
        errorText = nil
        done = 0
        total = 0

        let password = newPassword

        task = Task { @MainActor in
            do {
                let created = try await session.makeRekeyedCopy(
                    of: folder,
                    newPassword: password
                ) { finished, count in
                    done = finished
                    total = count
                }

                createdFolder = created
                newPassword = ""
                confirmPassword = ""
            } catch is CancellationError {
                errorText = "Se detuvo y se descartó la copia."
            } catch {
                errorText = ExplorerErrorText.message(for: error)
            }

            isRunning = false
        }
    }

    private func deleteOriginal() {
        session.lock()
        NikaidoSecFaceID.disable(folder.id)
        privateVault.delete(folder)
        onFinished(true)
        dismiss()
    }
}
