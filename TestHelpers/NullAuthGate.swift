// NullAuthGate.swift
// Convenience factory matching the `NullAuthGate()` call site in dispatch tests.
import Foundation
@testable import Merlin

@MainActor
func NullAuthGate() -> AuthGate {
    let memory = AuthMemory(storePath: "/dev/null")
    memory.addAllowPattern(tool: "*", pattern: "*")
    return AuthGate(memory: memory, presenter: NullAuthPresenter())
}
