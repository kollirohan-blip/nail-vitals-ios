//
//  Lenient.swift
//  NailVitals
//
//  Decodes whatever it can of one array element, so one entry this build
//  doesn't understand (a sign or state added by a newer build) can't fail
//  the whole file. Decode `[Lenient<T>]`, then keep the non-nil values.
//

import Foundation

nonisolated struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
