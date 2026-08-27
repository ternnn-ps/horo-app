import Foundation
import Realtime

/// ท่อ realtime เส้นเดียวของแอป — เปิดหลัง login ปิดตอน logout
///
/// ไม่ต้อง filter รายห้อง: RLS กรองให้แล้วว่าเห็นเฉพาะห้องที่ตัวเองเป็นคู่สนทนา
/// ส่ง apikey กับ access token ให้ SDK จัดการต่ออายุเอง (ถ้าเขียนเองต้องยัด token ใหม่
/// เข้าทุก channel ทุกครั้งที่ refresh ไม่งั้น socket เงียบตอน token หมดอายุ)
final class ChataRealtime {
    private let client: RealtimeClientV2
    private var channel: RealtimeChannelV2?
    private var listeners: [Task<Void, Never>] = []

    init(configuration: SupabaseConfiguration, auth: ChataAuth) {
        client = RealtimeClientV2(
            url: configuration.url.appendingPathComponent("realtime/v1"),
            options: RealtimeClientOptions(
                headers: ["apikey": configuration.anonKey],
                accessToken: { try? await auth.accessToken() }
            )
        )
    }

    /// เริ่มฟังข้อความใหม่และการเปลี่ยนสถานะของงาน แล้วเรียก `onChange` ให้ไปอ่านของจริงซ้ำ
    ///
    /// ตั้งใจไม่เอา payload ของ event มาต่อ state ตรง ๆ — ให้ event เป็นแค่สัญญาณว่า
    /// "มีอะไรเปลี่ยน ไปถาม server ใหม่" ความจริงอยู่ที่ฐานข้อมูลเสมอ
    func start(onChange: @escaping @Sendable () async -> Void) async {
        guard channel == nil else { return }

        let channel = client.channel("chata-inbox")
        let newMessages = channel.postgresChange(InsertAction.self, table: "question_message")
        let questionUpdates = channel.postgresChange(UpdateAction.self, table: "question")

        await channel.subscribe()
        self.channel = channel

        listeners = [
            Task { for await _ in newMessages { await onChange() } },
            Task { for await _ in questionUpdates { await onChange() } }
        ]
    }

    func stop() async {
        listeners.forEach { $0.cancel() }
        listeners = []

        if let channel {
            await client.removeChannel(channel)
        }
        channel = nil
    }
}
