//
//  LoginPasswordVerifier.swift
//  CaskHub
//
//  Created by Ali Elsokary on 06/11/2026.
//

import Foundation
import OpenDirectory

nonisolated enum LoginPasswordVerifier {
    static func accepts(_ password: String) -> Bool {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return true }
        return (try? record.verifyPassword(password)) != nil
    }
}
