import Foundation
import R2LCPClient
import ReadiumLCP

/// Implementation of LCPClient that wraps R2LCPClient framework
class LCPClientImpl: ReadiumLCP.LCPClient {

    func createContext(jsonLicense: String, hashedPassphrase: String, pemCrl: String) throws -> LCPClientContext {
        return try R2LCPClient.createContext(
            jsonLicense: jsonLicense,
            hashedPassphrase: hashedPassphrase,
            pemCrl: pemCrl
        )
    }

    func decrypt(data: Data, using context: LCPClientContext) -> Data? {
        return R2LCPClient.decrypt(data: data, using: context as! DRMContext)
    }

    func findOneValidPassphrase(jsonLicense: String, hashedPassphrases: [String]) -> String? {
        return R2LCPClient.findOneValidPassphrase(
            jsonLicense: jsonLicense,
            hashedPassphrases: hashedPassphrases
        )
    }
}
