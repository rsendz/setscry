//
//  CLIPTokenizer.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation

/// The byte-level BPE tokenizer CLIP was trained with.
///
/// Written out rather than pulled from a tokenizer library because it is the
/// only tokenizer Setscry needs, and a wrong tokenization degrades every search
/// result silently rather than failing loudly — worth being able to read the
/// whole thing.
struct CLIPTokenizer {
    enum Failure: LocalizedError {
        case missingFile(URL)
        case missingSpecialToken(String)

        var errorDescription: String? {
            switch self {
            case .missingFile(let url):
                "The model folder is missing \(url.lastPathComponent)."
            case .missingSpecialToken(let token):
                "The tokenizer vocabulary is missing the \(token) token."
            }
        }
    }

    /// CLIP reserves 256 byte tokens plus the two special tokens at the end of
    /// its 49,152-entry merge table.
    private static let mergeCount = 49152 - 256 - 2

    private static let startOfText = "<|startoftext|>"
    private static let endOfText = "<|endoftext|>"

    private let vocabulary: [String: Int]
    private let ranks: [Pair: Int]
    private let byteEncoder: [UInt8: Character]
    private let pattern: NSRegularExpression
    private let whitespace: NSRegularExpression

    let startToken: Int
    let endToken: Int

    private struct Pair: Hashable {
        let first: String
        let second: String
    }

    init(vocabularyURL: URL, mergesURL: URL) throws {
        guard let vocabularyData = try? Data(contentsOf: vocabularyURL) else {
            throw Failure.missingFile(vocabularyURL)
        }
        guard let mergesText = try? String(contentsOf: mergesURL, encoding: .utf8) else {
            throw Failure.missingFile(mergesURL)
        }

        vocabulary = try JSONDecoder().decode([String: Int].self, from: vocabularyData)

        guard let start = vocabulary[Self.startOfText] else {
            throw Failure.missingSpecialToken(Self.startOfText)
        }
        guard let end = vocabulary[Self.endOfText] else {
            throw Failure.missingSpecialToken(Self.endOfText)
        }
        startToken = start
        endToken = end

        var lines = mergesText.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.first?.hasPrefix("#") == true {
            lines.removeFirst()
        }

        var ranks: [Pair: Int] = [:]
        for (rank, line) in lines.prefix(Self.mergeCount).enumerated() {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            ranks[Pair(first: String(parts[0]), second: String(parts[1]))] = rank
        }
        self.ranks = ranks

        byteEncoder = Self.makeByteEncoder()

        // The token pattern CLIP was trained with: contractions, then runs of
        // letters, single digits, and runs of punctuation.
        pattern = try NSRegularExpression(
            pattern: #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#,
            options: [.caseInsensitive]
        )
        whitespace = try NSRegularExpression(pattern: #"\s+"#)
    }

    /// Encodes one string into token ids, wrapped in the start/end tokens and
    /// truncated to `contextLength`.
    ///
    /// The end token must survive truncation: the text encoder pools its output
    /// at the highest token id, which is the end token.
    func encode(_ text: String, contextLength: Int = 77) -> [Int32] {
        var ids: [Int32] = [Int32(startToken)]

        for word in split(text) {
            for piece in bytePairEncode(word) {
                guard let id = vocabulary[piece] else { continue }
                ids.append(Int32(id))
                if ids.count == contextLength - 1 { break }
            }
            if ids.count == contextLength - 1 { break }
        }

        ids.append(Int32(endToken))
        return ids
    }

    // MARK: - Splitting

    private func split(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let range = NSRange(lowered.startIndex..., in: lowered)
        let collapsed = whitespace.stringByReplacingMatches(
            in: lowered, range: range, withTemplate: " "
        ).trimmingCharacters(in: .whitespaces)

        let searchRange = NSRange(collapsed.startIndex..., in: collapsed)
        return pattern.matches(in: collapsed, range: searchRange).compactMap { match in
            Range(match.range, in: collapsed).map { String(collapsed[$0]) }
        }
    }

    // MARK: - Byte-pair encoding

    /// Maps every byte to a printable character, the way GPT-2 and CLIP do, so
    /// any input — including emoji and accented text — is representable in the
    /// vocabulary.
    private static func makeByteEncoder() -> [UInt8: Character] {
        var printable: [UInt8] = []
        printable.append(contentsOf: UInt8(33)...UInt8(126))
        printable.append(contentsOf: UInt8(161)...UInt8(172))
        printable.append(contentsOf: UInt8(174)...UInt8(255))

        var encoder: [UInt8: Character] = [:]
        for byte in printable {
            encoder[byte] = Character(UnicodeScalar(byte))
        }

        // Bytes with no printable representation are moved above the BMP gap.
        var next = 0
        for byte in UInt8.min...UInt8.max where encoder[byte] == nil {
            encoder[byte] = Character(UnicodeScalar(256 + next)!)
            next += 1
        }

        return encoder
    }

    private func bytePairEncode(_ word: String) -> [String] {
        let encoded = String(word.utf8.compactMap { byteEncoder[$0] })
        guard !encoded.isEmpty else { return [] }

        // The end-of-word marker is what lets the vocabulary distinguish a word
        // ending from the same letters mid-word.
        var pieces = encoded.map(String.init)
        pieces[pieces.count - 1] += "</w>"

        while pieces.count > 1 {
            var bestRank = Int.max
            var bestPair: Pair?

            for index in 0..<(pieces.count - 1) {
                let pair = Pair(first: pieces[index], second: pieces[index + 1])
                if let rank = ranks[pair], rank < bestRank {
                    bestRank = rank
                    bestPair = pair
                }
            }

            guard let bestPair else { break }

            var merged: [String] = []
            var index = 0
            while index < pieces.count {
                if index < pieces.count - 1,
                   pieces[index] == bestPair.first,
                   pieces[index + 1] == bestPair.second {
                    merged.append(bestPair.first + bestPair.second)
                    index += 2
                } else {
                    merged.append(pieces[index])
                    index += 1
                }
            }
            pieces = merged
        }

        return pieces
    }
}
