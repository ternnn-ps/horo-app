import XCTest
@testable import HoroTest

/// เทสที่ยิง Supabase จริงจากในตัวแอป (ไม่ใช่จาก curl) — พิสูจน์สิ่งที่ unit test พิสูจน์ไม่ได้:
/// ATS ยอมให้ต่อ, SDK auth ทำงาน, REST อ่านได้ด้วยสิทธิ์ของผู้ใช้จริง
///
/// ข้ามตัวเองเมื่อไม่มี local stack — ส่งค่าเข้ามาทาง env ตอนรัน:
///   TEST_RUNNER_SUPABASE_URL / TEST_RUNNER_SUPABASE_PUBLISHABLE_KEY
/// ต้องรัน ./scripts/seed-dev-fixture.sh ก่อน
final class ChataAuthIntegrationTests: XCTestCase {
    private var service: SupabaseHoroDataService!

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let urlString = environment["SUPABASE_URL"],
              let anonKey = environment["SUPABASE_PUBLISHABLE_KEY"],
              let configuration = SupabaseConfiguration(
                  urlString: urlString,
                  anonKey: anonKey,
                  testPassword: environment["SUPABASE_TEST_PASSWORD"] ?? "HoroTest123!"
              )
        else {
            throw XCTSkip("ไม่มีค่า Supabase ใน env — ข้ามชุด integration")
        }

        service = SupabaseHoroDataService(configuration: configuration)
    }

    override func tearDown() async throws {
        // setUp อาจ throw XCTSkip ไปแล้ว ตอนนั้น service ยังเป็น nil — ห้ามแตะแบบไม่เช็ค
        try? await service?.signOut()
    }

    func testCustomerCanSignInAndReadOwnWallet() async throws {
        let userID = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")
        XCTAssertNotNil(service.signedInUserID)
        XCTAssertEqual(service.signedInUserID, userID)

        let wallet = try await service.fetchWallet()
        XCTAssertEqual(wallet.accountID, userID)
        XCTAssertGreaterThan(wallet.availableCoin, 0, "fixture ต้องเติมเหรียญตั้งต้นให้แล้ว")
    }

    func testSeerCatalogIsVisibleToACustomer() async throws {
        _ = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")

        let listings = try await service.fetchSeerListings(matching: nil)
        XCTAssertFalse(listings.isEmpty, "fixture สร้างหมอดูที่อนุมัติแล้วไว้อย่างน้อยหนึ่งคน")
        XCTAssertNotNil(listings.first(where: { $0.serviceID != nil }), "ต้องมีหมอดูที่เปิด service")
    }

    func testSignOutRevokesAccessToProtectedData() async throws {
        _ = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")
        try await service.signOut()

        XCTAssertNil(service.signedInUserID)
        do {
            _ = try await service.fetchWallet()
            XCTFail("logout แล้วต้องอ่านกระเป๋าไม่ได้")
        } catch {
            // คาดหวัง unauthenticated — ไม่มี token ให้ใช้แล้ว
        }
    }
}
