// TODO: Migrate to "System"
import Foundation
import System

extension PCIAddress {
	func openResource(_ resource: String) throws -> File {
		let path = self.path + "/" + resource
		return try File(path: path, flags: O_RDWR)
//		return try FileDescriptor.open(path, .readWrite)
	}

	func mmapResource() throws -> MemoryMap {
		let path = self.path + "/resource0"
		let file = try File(path: path, flags: O_RDWR)
		let mmap = try MemoryMap(file: file, size: nil, access: .readwrite, flags: .shared)

		Log.debug("mmap'ed resource0: \(path)", component: .driver)

		return mmap
	}

	func removeDriver() throws {
		let path = self.path + "/driver/unbind"
		guard let file = try? File(path: path, flags: O_WRONLY) else {
			Log.warn("Could not unbind: \(path)", component: .driver)
			return
		}

		file.writeString(self.description)
		Log.info("Did unbind driver", component: .driver)
	}

	func enableDMA() throws {
		let path = self.path + "/config"
		guard let file = try? File(path: path, flags: O_RDWR) else {
			throw DriverError.unbindError
		}

		file[4] |= (1 << 2) as UInt16;
	}
}
