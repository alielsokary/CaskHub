//
//  AskpassCallerVerifier.swift
//  CaskHub
//
//  Created by Ali Elsokary on 06/11/2026.
//

import Darwin
import Foundation

nonisolated enum AskpassCallerVerifier {
    private static let maximumDepth = 32

    static func isLaunchedByCaskHub(
        startingAt pid: pid_t = getppid(),
        ownPID: pid_t = getpid(),
        ownPath: String? = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
        parent: (pid_t) -> pid_t? = AskpassCallerVerifier.parent(of:),
        executablePath: (pid_t) -> String? = AskpassCallerVerifier.executablePath(of:)
    ) -> Bool {
        guard let ownPath else { return false }
        var current = pid
        for _ in 0..<maximumDepth {
            guard current > 1 else { return false }
            if current != ownPID, executablePath(current) == ownPath { return true }
            guard let next = parent(current), next != current else { return false }
            current = next
        }
        return false
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
    }
}
