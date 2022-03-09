import CVirtio
import System

public enum VirtioError: Error {
	case unsupportedFeatures
}

public struct RingAvailable {
	// use &+ on vring_avail.idx
	var ptr: UnsafeMutablePointer<vring_avail>
	var size: UInt16

	subscript(index: Int) -> UnsafeMutablePointer<UInt16> {
		return UnsafeMutablePointer(bitPattern: index_avail_ring(ptr, numericCast(index)))!
	}
}

public struct RingUsed {
	// use &+ on vring_used.idx
	var ptr: UnsafeMutablePointer<vring_used>
	var size: UInt16

	subscript(index: Int) -> UnsafeMutablePointer<vring_used_elem> {
		return UnsafeMutablePointer(bitPattern: index_used_ring(ptr, numericCast(index)))!
	}
}

internal enum VirtioQueueType {
	case receive
	case transmit
	case control

	var index: Int {
		switch self {
		case .receive: return 0
		case .transmit: return 1
		case .control: return 2
		}
	}
}

public struct VirtioQueue {
	public let size: UInt16
	public var descriptors: UnsafeMutablePointer<vring_desc>
	public var available: RingAvailable
	public var used: RingUsed
	// use &+ and &- to get "wrapping" (i.e. overflow) behavior
	public var lastUsedIndex: UInt16

	public init(size: UInt16, ptr: UnsafeMutablePointer<vring_desc>) {
		// TODO: capacity??
		let avail = UnsafeMutableRawPointer(ptr.advanced(by: Int(size)))
			.bindMemory(to: vring_avail.self, capacity: 1)
		// TODO: this line is really tricky to translate into swift (calling c helper)
		// c: vr->used = (void*)RTE_ALIGN_CEIL((uintptr_t)(&vr->avail->ring[num]), align);
		// rust: let used = align((*avail).ring.as_mut_ptr().wrapping_add(size_usize) as _) as *mut VirtqUsed;
		let used = UnsafeMutableRawPointer(
			bitPattern: index_avail_ring(avail, UInt32(size))
				.alignedCeil(to: UInt(Constants.VirtIODevice.queueAlignment))
		)!.bindMemory(to: vring_used.self, capacity: 1)

		self.size = size
		self.descriptors = ptr
		self.available = RingAvailable(ptr: avail, size: size)
		self.used = RingUsed(ptr: used, size: size)
		self.lastUsedIndex = 0
	}

	static func memorySize(queueSize: Int) -> Int {
		// from 2.6.2
		var size = Int(queueSize) * MemoryLayout<vring_desc>.size
		size += MemoryLayout<vring_avail>.size + (queueSize * MemoryLayout<UInt16>.size)
		// queue alignment => 4096
		size = size.alignedCeil(to: Constants.VirtIODevice.queueAlignment)
		size += MemoryLayout<vring_used>.size + (queueSize * MemoryLayout<vring_used_elem>.size)
		return size
	}
}

public struct VirtioDevice {
	public let address: PCIAddress
	public let receiveQueueCount: UInt = 1
	public let transmitQueueCount: UInt = 1

	public internal(set) var receiveQueue: VirtioQueue
	public internal(set) var transmitQueue: VirtioQueue
	public internal(set) var controlQueue: VirtioQueue

	let receiveHugepage: Hugepage
	let receiveMempool: DMAMempool
	let controlHugepage: Hugepage
	let controlMempool: DMAMempool

	public init(address: PCIAddress) throws {

		try Self.checkConfig(address: address)

		self.address = address

		try address.removeDriver()
		try address.enableDMA()

		// 3.1: device initialization
		let bar0 = try address.openResource("resource0")
		Log.debug("configuring bar0", component: .device)

		// 1) Reset the device
		bar0.writeU8(VIRTIO_CONFIG_STATUS_RESET, at: VIRTIO_PCI_STATUS)
		while bar0.readU8(at: VIRTIO_PCI_STATUS) != VIRTIO_CONFIG_STATUS_RESET {
			Log.debug("waiting for VIRTIO_CONFIG_STATUS_RESET in VIRTIO_PCI_STATUS", component: .driver)
			usleep(10000)
		}

		// 2) Set ACKNOWLEDGE status bit; OS noticed the device
		bar0.writeU8(VIRTIO_CONFIG_STATUS_ACK, at: VIRTIO_PCI_STATUS)

		// 3) Set DRIVER status bit; OS can drive the device
		bar0.writeU8(VIRTIO_CONFIG_STATUS_DRIVER, at: VIRTIO_PCI_STATUS)

		// 4) Negotiate features
		let hostFeatures = bar0.readU32(at: VIRTIO_PCI_HOST_FEATURES)
		Log.debug("device features: \(String(hostFeatures, radix: 2))", component: .driver)
		let requiredFeatures: UInt32 = (1 << VIRTIO_NET_F_CSUM) // we may offload checksumming to the device
			| (1 << VIRTIO_NET_F_GUEST_CSUM) // we can handle packets with invalid checksums
			| (1 << VIRTIO_NET_F_CTRL_VQ) // enable the control queue
			| (1 << VIRTIO_NET_F_CTRL_RX) // required to enable promiscuous mode
			| (1 << VIRTIO_NET_F_MAC) // required to read MAC address
			| (1 << VIRTIO_F_ANY_LAYOUT) // we don't make assumptions about message framing
		if (hostFeatures & requiredFeatures) != requiredFeatures {
			Log.debug("required features: \(String(requiredFeatures, radix: 2))", component: .driver)
			throw VirtioError.unsupportedFeatures
		}
		Log.debug("guest features before negotiation: \(String(bar0.readU32(at: VIRTIO_PCI_GUEST_FEATURES), radix: 2))", component: .driver)
		bar0.writeU32(requiredFeatures, at: VIRTIO_PCI_GUEST_FEATURES)
		Log.debug("guest features after negotiation: \(String(bar0.readU32(at: VIRTIO_PCI_GUEST_FEATURES), radix: 2))", component: .driver)

		// 5) Skipped due to legacy interface
		// 6) Skipped due to legacy interface

		// 7) Perform network device specific initialization
		self.receiveQueue = try Self.makeQueue(bar0: bar0, type: .receive)
		self.transmitQueue = try Self.makeQueue(bar0: bar0, type: .transmit)
		self.controlQueue = try Self.makeQueue(bar0: bar0, type: .control)

		// 2.6.13: allocate buffers to send to the device
		// we allocate more bufs than what would fit in the rx queue, because we don't want to
		// stall rx if users hold buffers for longer
		// TODO: non-contiguous
		(self.receiveHugepage, self.receiveMempool) = try Self.makePacketBuffer(
			packetSize: 2048,
			packetCount: Int(self.receiveQueue.size) * 4
		)
		(self.controlHugepage, self.controlMempool) = try Self.makePacketBuffer(
			packetSize: 2048,
			packetCount: Int(self.controlQueue.size)
		)

		mfence();

		// 8) Signal OK
		bar0.writeU8(VIRTIO_CONFIG_STATUS_DRIVER_OK, at: VIRTIO_PCI_STATUS)
		Log.info("initialization complete", component: .device)

		// recheck status
		assert(bar0.readU8(at: VIRTIO_PCI_STATUS) != VIRTIO_CONFIG_STATUS_FAILED, "device signalled unrecoverable config error")

		self.setPromiscuous(true)
	}

	private func setPromiscuous(_ on: Bool) {
		// TODO: !!
	}

	private static func makePacketBuffer(packetSize: Int, packetCount: Int) throws -> (Hugepage, DMAMempool) {
		// TODO: non-contiguous
		let hugepage = try Hugepage(size: packetSize * packetCount, requireContiguous: true)
		let mempool = try DMAMempool(
			memory: hugepage.address,
			entrySize: UInt(packetSize),
			entryCount: UInt(packetCount)
		)
		return (hugepage, mempool)
	}

	private static func makeQueue(bar0: File, type: VirtioQueueType) throws -> VirtioQueue {
		// 4.1.5.1.3: create virtqueue itself
		bar0.writeU16(type.index, at: VIRTIO_PCI_QUEUE_SEL)
		let maxQueueSize = bar0.readU16(at: VIRTIO_PCI_QUEUE_NUM)
		Log.debug("max queue size of queue \(type) (#\(type.index)): \(maxQueueSize)", component: .queue)
		guard maxQueueSize > 0 else {
			Log.error("queue #\(type.index) (\(type)) doesn't exist", component: .queue)
			throw DriverError.initializationError
		}

		let queueMemorySize = VirtioQueue.memorySize(queueSize: Int(maxQueueSize))
		Log.debug("allocating \(queueMemorySize) for \(type) queue", component: .queue)
		var memory = try Hugepage(size: queueMemorySize, requireContiguous: true)
		Log.debug("allocated \(queueMemorySize) bytes at \(String(describing: memory.dmaAddress?.virtual))", component: .queue)
		guard memory.dmaAddress != nil else {
			throw DriverError.initializationError
		}

		bar0.writeU32(UInt(bitPattern: memory.dmaAddress!.physical) >> VIRTIO_PCI_QUEUE_ADDR_SHIFT, at: VIRTIO_PCI_QUEUE_PFN)

		let virtQueue = VirtioQueue(
			size: maxQueueSize,
			ptr: memory.dmaAddress!.virtual.bindMemory(to: vring_desc.self, capacity: Int(maxQueueSize))
		)

		Log.debug("virtq desc: \(virtQueue.descriptors)", component: .queue)
		Log.debug("virtq avail: \(virtQueue.available.ptr)", component: .queue)
		Log.debug("virtq used: \(virtQueue.used.ptr)", component: .queue)
		for i in 0..<Int(virtQueue.size) {
			virtQueue.descriptors.advanced(by: i).initialize(to: vring_desc())
			virtQueue.available[i].initialize(to: 0)
			virtQueue.used[i].initialize(to: vring_used_elem())
		}
		virtQueue.available.ptr.pointee.idx = 0
		virtQueue.used.ptr.pointee.idx = 0

		// optimization hint to not get interrupted when the device consumes a buffer
		virtQueue.available.ptr.pointee.flags = UInt16(VRING_AVAIL_F_NO_INTERRUPT)
		virtQueue.used.ptr.pointee.flags = 0

		return virtQueue
	}

	private static func checkConfig(address: PCIAddress) throws {
		// try to open device config
		let config = try DeviceConfig(address: address)

		Log.debug("Device Config: \(config)", component: .device)

		// check vendor
		let vendor = config.vendorID
		guard vendor == Constants.VirtIODevice.vendorID else {
			Log.error("Vendor \(vendor) not supported", component: .device)
			throw DeviceError.wrongDeviceType
		}
	}

	public func open() throws {

	}
}
