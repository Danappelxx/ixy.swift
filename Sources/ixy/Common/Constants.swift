//
//  Constants.swift
//  app
//
//  Created by Thomas Günzel on 25.09.2018.
//

import Foundation

/// the constants which can be used to tweak some aspects or adjust it to different linux distros
struct Constants {
	internal static let pcieBasePath: String = "/sys/bus/pci/devices/"
	internal static let pagemapPath: String = "/proc/self/pagemap"

	struct Hugepage {
		internal static let path: String = "/mnt/huge/"
		internal static let pageBits: Int = 21
		internal static let pageSize: Int = (1 << 21)
	}

	struct IxgbeDevice {
		internal static let vendorID: UInt16 = 0x8086
		internal static let maxPacketSize: UInt = 2048
	}

	struct VirtIODevice {
		internal static let vendorID: UInt16 = 0x1af4
		internal static let maxPacketSize: UInt = 2048
		internal static let queueAlignment: Int = 4096
	}

	struct Queue {
		internal static let ringEntryCount: UInt = 512
		internal static let ringEntrySize: UInt = UInt(MemoryLayout<UInt64>.size * 2)
		internal static let ringSizeBytes: UInt = { return Queue.ringEntryCount * Queue.ringEntrySize} ()
	}
}
