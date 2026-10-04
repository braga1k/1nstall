import Foundation
import OneInstallCore

@main enum AdminMain {
  static func main() {
    do {
      guard CommandLine.arguments.count == 2, CommandLine.arguments[1].utf8.count < 180_000,
        let data = Data(base64Encoded: CommandLine.arguments[1])
      else {
        throw OperationError("Invalid administrative request.")
      }
      let request = try JSONDecoder().decode(AdministrativeRequest.self, from: data)
      let result = try AdministrativeRemoval.execute(request)
      print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
    } catch {
      FileHandle.standardError.write(
        Data(("Administrative worker: " + error.localizedDescription + "\n").utf8))
      exit(1)
    }
  }
}
