import Auth
import Foundation

/// session ของแอปอยู่ที่นี่ที่เดียว — SDK เก็บลง Keychain และต่ออายุ token ให้เอง
/// วันที่เพิ่ม Google / OTP แตะแค่ไฟล์นี้ ฝั่ง DB ไม่ต้องแก้เลยเพราะ auth.uid() เป็น uuid เดียวกัน
final class ChataAuth {
    private let client: AuthClient

    init(configuration: SupabaseConfiguration) {
        client = AuthClient(
            url: configuration.url.appendingPathComponent("auth/v1"),
            headers: ["apikey": configuration.anonKey],
            localStorage: AuthClient.Configuration.defaultLocalStorage
        )
    }

    var currentUserID: UUID? { client.currentUser?.id }

    var isSignedIn: Bool { client.currentSession != nil }

    /// สถานะ login เปลี่ยน (รวมตอน session หมดอายุแล้วต่ออายุไม่ได้) — ใช้พาผู้ใช้กลับหน้า login
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.authStateChanges {
                    continuation.yield((event, session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @discardableResult
    func signUp(email: String, password: String) async throws -> UUID {
        let response = try await client.signUp(email: email, password: password)
        guard let session = response.session else {
            throw HoroDataError.notConfigured(
                "สมัครแล้วแต่ยังไม่ได้ session — ตรวจว่าปิด email confirmation ในโปรเจกต์แล้วหรือยัง"
            )
        }
        return session.user.id
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> UUID {
        try await client.signIn(email: email, password: password).user.id
    }

    func signOut() async throws {
        try await client.signOut()
    }

    /// token ที่ยังไม่หมดอายุเสมอ — SDK ต่ออายุให้เองเมื่อใกล้หมด
    /// (ก่อนหน้านี้เก็บ token ไว้เฉย ๆ ไม่เคย refresh แอปเลย 401 ทั้งหมดหลังใช้ครบชั่วโมง)
    func accessToken() async throws -> String {
        do {
            return try await client.session.accessToken
        } catch {
            throw HoroDataError.unauthenticated
        }
    }
}
