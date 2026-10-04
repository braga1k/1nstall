import AppKit
import Foundation

public enum WorkspaceTrash {
  /// AppKit owns the authorisation/UI and returns the actual destination.
  /// Wait only on a worker; never time out while an OS operation could still complete.
  public static func move(_ url: URL) throws -> URL {
    guard !Thread.isMainThread else {
      throw OperationError("Trash operations must not block the interface.")
    }
    final class Reply: @unchecked Sendable {
      let semaphore = DispatchSemaphore(value: 0)
      var result: Result<URL, Error>?
    }
    let reply = Reply()
    DispatchQueue.main.async {
      NSWorkspace.shared.recycle([url]) { destinations, error in
        if let destination = destinations[url] {
          reply.result = .success(destination)
        } else {
          reply.result = .failure(error ?? OperationError("Moving to Trash was not confirmed."))
        }
        reply.semaphore.signal()
      }
    }
    reply.semaphore.wait()
    return try reply.result!.get()
  }
}
