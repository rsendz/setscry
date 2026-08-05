//
//  UnionFind.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation

/// Disjoint-set union over integer indices, used to turn pairwise
/// near-duplicate matches into groups.
struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }

        // Path compression keeps repeated lookups near-constant.
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }

        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }

        if rank[rootA] < rank[rootB] {
            parent[rootA] = rootB
        } else if rank[rootA] > rank[rootB] {
            parent[rootB] = rootA
        } else {
            parent[rootB] = rootA
            rank[rootA] += 1
        }
    }

    /// Groups of indices sharing a root, in ascending index order.
    mutating func groups() -> [[Int]] {
        var buckets: [Int: [Int]] = [:]
        for index in parent.indices {
            buckets[find(index), default: []].append(index)
        }
        return Array(buckets.values)
    }
}
