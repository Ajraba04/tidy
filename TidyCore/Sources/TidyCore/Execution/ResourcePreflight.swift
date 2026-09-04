import Foundation
import Darwin
enum ResourceCaptureError: Error { case unavailable, unsupported }
enum ResourcePreflight {
    /// Read-only no-follow capture. This is not an anchored deletion capability.
    static func captureFile(at path: String) throws -> FileResourceIdentity {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw ResourceCaptureError.unavailable }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..") else {
            throw ResourceCaptureError.unavailable
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ResourceCaptureError.unavailable }
        defer { close(fd) }
        var parents: [FileNodeIdentity] = []
        for component in components.dropLast() {
            var parent = stat()
            guard fstat(fd, &parent) == 0 else { throw ResourceCaptureError.unavailable }
            parents.append(FileNodeIdentity(device: UInt64(UInt32(bitPattern: parent.st_dev)),
                                            inode: UInt64(parent.st_ino), generation: UInt64(parent.st_gen)))
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ResourceCaptureError.unavailable }
            close(fd); fd = next
        }
        var parent = stat()
        guard fstat(fd, &parent) == 0 else { throw ResourceCaptureError.unavailable }
        parents.append(FileNodeIdentity(device: UInt64(UInt32(bitPattern: parent.st_dev)),
                                        inode: UInt64(parent.st_ino), generation: UInt64(parent.st_gen)))
        let leaf = components.last!
        var metadata = stat()
        guard fstatat(fd, leaf, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
              [S_IFREG, S_IFDIR].contains(metadata.st_mode & S_IFMT) else {
            throw ResourceCaptureError.unavailable
        }
        let leafFD = openat(fd, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard leafFD >= 0 else { throw ResourceCaptureError.unavailable }
        defer { close(leafFD) }
        var opened = stat()
        var volume = statfs()
        guard fstat(leafFD, &opened) == 0, opened.st_dev == metadata.st_dev,
              opened.st_ino == metadata.st_ino, fstatfs(leafFD, &volume) == 0,
              volume.f_flags & UInt32(MNT_LOCAL) != 0 else { throw ResourceCaptureError.unavailable }
        let canonical = "/" + components.joined(separator: "/")
        // Darwin's ATTR_VOL_UUID is uuid_t. Read it from the retained no-follow
        // descriptor, never by reopening a potentially replaced path namespace.
        struct VolumeAttributes {
            var length: UInt32 = 0
            var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        }
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_UUID)
        var volumeAttributes = VolumeAttributes()
        guard fgetattrlist(leafFD, &attributes, &volumeAttributes,
                          MemoryLayout<VolumeAttributes>.size, 0) == 0,
              volumeAttributes.length == MemoryLayout<VolumeAttributes>.size,
              withUnsafeBytes(of: volumeAttributes.uuid, { $0.contains { $0 != 0 } }) else {
            throw ResourceCaptureError.unsupported
        }
        let volumeID = UUID(uuid: volumeAttributes.uuid)
        var final = stat()
        guard fstatat(fd, leaf, &final, AT_SYMLINK_NOFOLLOW) == 0,
              final.st_dev == opened.st_dev, final.st_ino == opened.st_ino,
              final.st_mode == opened.st_mode, final.st_size == opened.st_size,
              final.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec else {
            throw ResourceCaptureError.unavailable
        }
        return FileResourceIdentity(volumeID: volumeID, device: UInt64(UInt32(bitPattern: opened.st_dev)),
            inode: UInt64(opened.st_ino), generation: UInt64(opened.st_gen), canonicalPath: canonical,
            mode: UInt32(opened.st_mode), size: opened.st_size,
            modifiedSeconds: Int64(opened.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(opened.st_mtimespec.tv_nsec), parentChain: parents, manifest: nil)
    }
    static func unchanged(_ identity: FileResourceIdentity) -> Bool {
        guard let current = try? captureFile(at: identity.canonicalPath) else { return false }
        return current == identity
    }
}
