//
//  LineColors.swift
//  xTransit Watch App
//
//  Created by Shubhankar Singh on 7/17/26.
//

import Foundation

struct LineColors {
    static func fill(for line: String) -> String {
        switch line.uppercased() {
        case "A", "C", "E": return "001133"
        case "B", "D", "F", "M": return "2A1409"
        case "G": return "12280B"
        case "L", "S": return "19191A"
        case "J", "Z": return "29190A"
        case "N", "Q", "R", "W": return "332800"
        case "1", "2", "3": return "330005"
        case "4", "5", "6": return "003310"
        case "7": return "2C0727"
        default: return "1A1A1A"
        }
    }

    static func badge(for line: String) -> String {
        switch line.uppercased() {
        case "A", "C", "E": return "003AAA"
        case "B", "D", "F", "M": return "F2590D"
        case "G": return "54BF33"
        case "L", "S": return "A8A9AD"
        case "J", "Z": return "A46328"
        case "N", "Q", "R", "W": return "FFCA00"
        case "1", "2", "3": return "FF0018"
        case "4", "5", "6": return "009630"
        case "7": return "C920B3"
        default: return "888888"
        }
    }

    static func textColor(for line: String) -> Bool {
        // returns true if text should be black (light badge color)
        switch line.uppercased() {
        case "N", "Q", "R", "W": return true
        default: return false
        }
    }
}
