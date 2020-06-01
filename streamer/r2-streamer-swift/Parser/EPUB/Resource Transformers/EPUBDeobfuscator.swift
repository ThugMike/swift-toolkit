//
//  EPUBDeobfuscator.swift
//  r2-streamer-swift
//
//  Created by Mickaël Menu on 01/06/2020.
//
//  Copyright 2020 Readium Foundation. All rights reserved.
//  Use of this source code is governed by a BSD-style license which is detailed
//  in the LICENSE file present in the project repository where this source code is maintained.
//

import CryptoSwift
import Foundation
import R2Shared

/// Deobfuscates EPUB resources.
/// https://www.w3.org/publishing/epub3/epub-ocf.html#sec-resource-obfuscation
final class EPUBDeobfuscator {

    /// Supported obfuscation algorithms.
    private let algorithms: [ObfuscationAlgorithm] = [IDPFAlgorithm(), AdobeAlgorithm()]
    
    /// Publication identifier
    private let publicationId: String
    
    init(publicationId: String) {
        self.publicationId = publicationId
            // > All white space characters, as defined in section 2.3 of the XML 1.0 specification
            // > [XML], MUST be removed from this identifier — specifically, the Unicode code points
            // > U+0020, U+0009, U+000D and U+000A.
            // https://www.w3.org/publishing/epub3/epub-ocf.html#obfus-keygen
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }

    func deobfuscate(resource: Resource) -> Resource {
        // Checks if the resource is obfuscated with a known algorithm.
        guard
            let algorithmId = resource.link.properties.encryption?.algorithm,
            let algorithm = algorithms.first(withIdentifier: algorithmId) else
        {
            return resource
        }

        let key = algorithm.key(for: publicationId)
        return EPUBDeobfuscatingResource(resource: resource, algorithm: algorithm, key: key)
    }

    private final class EPUBDeobfuscatingResource: ResourceProxy {

        private let algorithm: ObfuscationAlgorithm
        private let key: [UInt8]
        
        init(resource: Resource, algorithm: ObfuscationAlgorithm, key: [UInt8]) {
            self.algorithm = algorithm
            self.key = key
            super.init(resource)
        }

        override func read(range: Range<UInt64>?) -> ResourceResult<Data> {
            resource.read(range: range).map { data in
                let range = range ?? 0..<UInt64(data.count)
                let toDeobfuscate = max(range.lowerBound, 0)..<min(range.upperBound, UInt64(algorithm.obfuscatedLength))
                
                var data = data
                for i in toDeobfuscate {
                    let i = Int(i)
                    data[i] = data[i] ^ key[i % key.count]
                }
                
                return data
            }
        }

    }
    
}

private protocol ObfuscationAlgorithm {
    /// URI identifier for this algorithm.
    var identifier: String { get }
    
    /// Number of bytes obfuscated at the beggining of the resources.
    var obfuscatedLength: Int { get }
    
    /// Generates the obfuscation key from the publication identifier.
    func key(for publicationId: String) -> [UInt8]
}

private extension Array where Element == ObfuscationAlgorithm {

    func first(withIdentifier uri: String) -> ObfuscationAlgorithm? {
        return first { $0.identifier == uri }
    }
    
}

private final class IDPFAlgorithm: ObfuscationAlgorithm {
    
    let identifier = "http://www.idpf.org/2008/embedding"
    let obfuscatedLength = 1040
    
    func key(for publicationId: String) -> [UInt8] {
        return publicationId.sha1().hexaToBytes
    }
    
}

private final class AdobeAlgorithm: ObfuscationAlgorithm {
    
    let identifier = "http://ns.adobe.com/pdf/enc#RC"
    let obfuscatedLength = 1024
    
    func key(for publicationId: String) -> [UInt8] {
        return publicationId
            .replacingOccurrences(of: "urn:uuid:", with: "")
            .replacingOccurrences(of: "-", with: "")
            .hexaToBytes
    }
    
}

private extension String {
    
    var hexaToBytes: [UInt8] {
        var position = startIndex
        return (0..<count / 2).compactMap { _ in
            defer { position = index(position, offsetBy: 2) }

            return UInt8(self[position...self.index(after: position)], radix: 16)
        }
    }
    
}
