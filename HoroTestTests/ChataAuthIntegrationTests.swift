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
    private var configuration: SupabaseConfiguration!

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

        self.configuration = configuration
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

    /// พิสูจน์ว่าแชทเด้งเองจริงจากในแอป — ผู้ถาม subscribe แล้วให้หมอดูตอบจากอีกบัญชี
    func testRealtimeDeliversTheSeerReplyToTheCustomer() async throws {
        let customerID = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")
        XCTAssertNotNil(customerID)

        // บัญชีหมอดูต้องใช้ storage แยก ไม่งั้น login จะทับ session ของผู้ถามในโปรเซสเดียวกัน
        let seerService = SupabaseHoroDataService(configuration: configuration, authStorageKey: "chata-test-seer")
        let seerID = try await seerService.signIn(email: "seer@horo.test", password: "HoroTest123!")

        // ต้องเจาะจง service ของหมอดู fixture — ถ้าหยิบใบแรกที่เจอ อาจไปได้หมอดูเก่าที่ค้างในฐาน
        // แล้วหมอดูของเราจะตอบไม่ได้เพราะไม่ใช่คู่สนทนา (RLS ปฏิเสธ)
        let listings = try await service.fetchSeerListings(matching: nil)
        let seerListing = try XCTUnwrap(
            listings.first(where: { $0.id == seerID && $0.serviceID != nil }),
            "fixture ต้องมีหมอดู seer@horo.test ที่เปิด service"
        )
        let serviceID = try XCTUnwrap(seerListing.serviceID)

        let draft = SupabaseQuestionDraft.startDraft(seerServiceID: serviceID, firstMessage: "ทดสอบ realtime จากในแอป")
        let question = try await service.submitQuestion(draft)

        let realtime = ChataRealtime(configuration: configuration, auth: service.auth)
        let delivered = expectation(description: "ผู้ถามได้รับข้อความของหมอดูเอง")
        delivered.assertForOverFulfill = false
        await realtime.start { delivered.fulfill() }
        _ = try await seerService.sendQuestionMessage(
            questionID: question.questionID,
            senderID: seerID,
            body: "หมอดูตอบเพื่อทดสอบ realtime"
        )

        await fulfillment(of: [delivered], timeout: 20)
        await realtime.stop()
        try? await seerService.signOut()
    }

    /// ปุ่มเติมเหรียญโหมด dev — **เซิร์ฟเวอร์เป็นคนบอกว่าเปิดให้ไหม แอปไม่เดาเอง**
    /// เพราะเงื่อนไขมีสองชั้น (app_config `payment.iap_mode` + env `ALLOW_UNVERIFIED_IAP`)
    /// และแอปอ่าน app_config เองไม่ได้โดยตั้งใจ (คีย์นั้น is_public = false)
    ///
    /// เทสตัวเดียวเดินได้ทั้ง local (อนุญาต → ต้องเติมสำเร็จ) และ cloud (ไม่อนุญาต → ต้องถูกปฏิเสธ
    /// และเหรียญห้ามขยับ) — ยึดคำตอบของเซิร์ฟเวอร์เป็นตัวตั้ง ไม่ใช่เดาจากว่ารันที่ไหน
    func testDevTopUpFollowsWhatTheServerAllows() async throws {
        _ = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")

        let availability = try await service.fetchDevTopUpAvailability()

        // แพ็กต้องมาจากตาราง coin_package จริง — product id คือค่าที่ต้องส่งให้ verify-iap
        let packages = try await service.fetchCoinPackages()
        let package = try XCTUnwrap(
            packages.first(where: { $0.appleProductID != nil }),
            "fixture ต้องมีแพ็กที่ตั้ง apple_product_id ไว้"
        )
        let productID = try XCTUnwrap(package.appleProductID)
        let expectedCoin = package.coinAmount + package.bonusCoin

        let before = try await service.fetchWallet().availableCoin

        if availability.isAllowed {
            XCTAssertEqual(availability.mode, "local_test", "เปิดให้เติมแบบ dev ได้เฉพาะโหมด local_test")

            let receipt = try await service.redeemDevTopUp(appleProductID: productID)
            XCTAssertEqual(receipt.coinCredited, expectedCoin, "เซิร์ฟเวอร์ต้องเติมเท่าแพ็กที่เลือก")

            let after = try await service.fetchWallet().availableCoin
            XCTAssertEqual(after - before, expectedCoin, "ยอดในกระเป๋าต้องเพิ่มเท่าแพ็กพอดี")
        } else {
            do {
                _ = try await service.redeemDevTopUp(appleProductID: productID)
                XCTFail("เซิร์ฟเวอร์บอกว่าไม่อนุญาต แต่กลับเติมสำเร็จ — นี่คือช่องแจกเหรียญฟรี")
            } catch {
                XCTAssertFalse(
                    error.localizedDescription.isEmpty,
                    "ถูกปฏิเสธแล้วต้องมีเหตุผลให้ผู้ใช้อ่าน ไม่ใช่ error เปล่า"
                )
            }

            let after = try await service.fetchWallet().availableCoin
            XCTAssertEqual(after, before, "ถูกปฏิเสธแล้วเหรียญห้ามขยับ")
        }
    }

    // MARK: - แทนที่เทสของ MockHoroDataService ที่ถูกลบใน ticket 09
    //
    // ของเดิมพิสูจน์บนของปลอมล้วน (`MockHoroDataService` + `UserDefaults`) ซึ่งพิสูจน์อะไรไม่ได้เลย
    // เรื่องสิทธิ์และเรื่องเงิน สองตัวข้างล่างครอบพฤติกรรมเดียวกันแต่ยิงฐานจริงผ่าน RLS ของผู้ใช้

    /// แทน `testFetchSeersSearchesSkillsAndHeadline`
    func testSeerSearchMatchesByName() async throws {
        _ = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")

        let all = try await service.fetchSeerListings(matching: nil)
        let fixtureSeer = try XCTUnwrap(
            all.first(where: { $0.displayName.contains("ทดสอบ") }),
            "fixture ต้องมีหมอดูชื่อ 'หมอดูทดสอบ'"
        )

        let hit = try await service.fetchSeerListings(matching: "ทดสอบ")
        XCTAssertTrue(hit.contains(where: { $0.id == fixtureSeer.id }), "ค้นด้วยชื่อแล้วต้องเจอ")

        let miss = try await service.fetchSeerListings(matching: "ไม่มีหมอดูชื่อนี้แน่นอน\(UUID().uuidString)")
        XCTAssertTrue(miss.isEmpty, "ค้นคำที่ไม่มีต้องได้ผลลัพธ์ว่าง ไม่ใช่คืนทั้งหมด")
    }

    /// แทน `testDeleteReadingRequestRemovesRelatedThread`
    /// ของเดิมแค่ลบแถวใน `UserDefaults` — ของจริงต้องคืนเหรียญออกจาก escrow ให้ครบ
    func testCancellingAnUnansweredQuestionRefundsEveryCoin() async throws {
        let customerID = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")

        let listings = try await service.fetchSeerListings(matching: nil)
        let listing = try XCTUnwrap(
            listings.first(where: { $0.serviceID != nil }),
            "fixture ต้องมีหมอดูที่เปิด service"
        )
        let serviceID = try XCTUnwrap(listing.serviceID)

        let before = try await service.fetchWallet()
        XCTAssertEqual(before.accountID, customerID)

        let draft = SupabaseQuestionDraft.startDraft(seerServiceID: serviceID, firstMessage: "ทดสอบยกเลิกแล้วคืนเหรียญ")
        let question = try await service.submitQuestion(draft)

        let escrowed = try await service.fetchWallet()
        XCTAssertEqual(escrowed.availableCoin, before.availableCoin - question.priceCoin, "เหรียญต้องถูกกันไว้")
        XCTAssertEqual(escrowed.reservedCoin, before.reservedCoin + question.priceCoin)

        let lifecycle = try await service.cancelQuestion(id: question.questionID)
        XCTAssertEqual(lifecycle.status, "cancelled_refunded")

        let after = try await service.fetchWallet()
        XCTAssertEqual(after.availableCoin, before.availableCoin, "ยกเลิกก่อนหมอดูตอบต้องคืนเต็มจำนวน")
        XCTAssertEqual(after.reservedCoin, before.reservedCoin, "ต้องไม่มีเหรียญค้างใน escrow")
    }

    /// หมอดูต้องเห็นรายได้ของตัวเองเป็นรายก้อน ไม่ใช่มีแต่ยอดรวมในกระเป๋า
    ///
    /// เดินลูปเงินครบวงจากในแอปเองแทนที่จะพึ่งสถานะที่ค้างอยู่ในฐาน — ถ้าพึ่งของเก่า
    /// เทสจะผ่านแบบว่างเปล่าได้เมื่อ fixture รีเซ็ตแล้วยอดเป็น 0 ทั้งคู่ (0 == 0)
    func testSeerSeesEarningForEachFinishedJob() async throws {
        _ = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")

        let seerService = SupabaseHoroDataService(configuration: configuration, authStorageKey: "chata-test-earning-seer")
        let seerID = try await seerService.signIn(email: "seer@horo.test", password: "HoroTest123!")

        let listings = try await service.fetchSeerListings(matching: nil)
        let listing = try XCTUnwrap(
            listings.first(where: { $0.id == seerID && $0.serviceID != nil }),
            "fixture ต้องมีหมอดู seer@horo.test ที่เปิด service"
        )
        let serviceID = try XCTUnwrap(listing.serviceID)

        let earningsBefore = try await seerService.fetchSeerEarnings()
        let payableBefore = try await seerService.fetchWallet().payableCoin

        // ซื้อ → ตอบ → ขอปิด → ยืนยัน
        let draft = SupabaseQuestionDraft.startDraft(seerServiceID: serviceID, firstMessage: "ทดสอบรายการรายได้")
        let question = try await service.submitQuestion(draft)
        _ = try await seerService.sendQuestionMessage(
            questionID: question.questionID, senderID: seerID, body: "ตอบเพื่อให้ปิดงานได้"
        )
        _ = try await seerService.requestCloseQuestion(id: question.questionID)
        _ = try await service.respondCloseQuestion(id: question.questionID, accept: true)

        let earningsAfter = try await seerService.fetchSeerEarnings()
        let payableAfter = try await seerService.fetchWallet().payableCoin

        XCTAssertEqual(earningsAfter.count, earningsBefore.count + 1, "ปิดงานหนึ่งครั้งต้องเกิดรายได้หนึ่งรายการ")

        let earning = try XCTUnwrap(
            earningsAfter.first(where: { $0.sourceID == question.questionID.uuidString.lowercased() }),
            "ต้องมีรายการที่ชี้กลับไปหางานที่เพิ่งปิด"
        )
        XCTAssertEqual(earning.grossCoin, question.priceCoin, "ยอดที่ลูกค้าจ่ายต้องตรงกับราคางาน")
        XCTAssertEqual(earning.seerCoin, payableAfter - payableBefore, "ส่วนที่เข้าหมอดูต้องตรงกับยอดค้างจ่ายที่ขยับ")
        XCTAssertLessThanOrEqual(earning.seerCoin, earning.grossCoin)
        XCTAssertGreaterThan(earning.revenueShareBps, 0, "ต้อง snapshot อัตราส่วนแบ่งไว้")

        try? await seerService.signOut()
    }

    /// หมอดูผูกบัญชีธนาคารแล้วต้องเห็นแค่ 4 ตัวท้าย — เลขเต็มห้ามกลับมาถึงแอปเลย
    func testSeerBindsBankAccountAndOnlySeesLastFourDigits() async throws {
        let seerService = SupabaseHoroDataService(configuration: configuration, authStorageKey: "chata-test-payout-seer")
        _ = try await seerService.signIn(email: "seer@horo.test", password: "HoroTest123!")

        let savedAccount = try await seerService.savePayoutAccount(
            bankCode: "kbank", accountNumber: "1234567890", accountHolderName: "หมอดูทดสอบ"
        )
        let saved = try XCTUnwrap(savedAccount, "บันทึกแล้วต้องอ่านกลับมาได้")

        XCTAssertEqual(saved.accountNumberLast4, "7890")
        XCTAssertEqual(saved.bankCode, "kbank")
        XCTAssertEqual(saved.verifyStatus, "pending", "บัญชีที่เพิ่งผูกต้องยังไม่ผ่านการตรวจ")
        XCTAssertFalse(saved.isVerified, "ยังถอนเงินไม่ได้จนกว่าจะมีคนตรวจ")

        // แก้แล้วต้องกลับไปรอตรวจใหม่ และ 4 ตัวท้ายเปลี่ยนตาม
        let editedAccount = try await seerService.savePayoutAccount(
            bankCode: "scb", accountNumber: "9876543210", accountHolderName: "หมอดูทดสอบ"
        )
        let edited = try XCTUnwrap(editedAccount)
        XCTAssertEqual(edited.accountNumberLast4, "3210")
        XCTAssertEqual(edited.bankCode, "scb")
        XCTAssertEqual(edited.verifyStatus, "pending")

        // ธนาคารที่ไม่มีในรายการต้องถูกปฏิเสธ ไม่ใช่บันทึกเงียบ ๆ
        do {
            _ = try await seerService.savePayoutAccount(
                bankCode: "ไม่มีธนาคารนี้", accountNumber: "1111222233", accountHolderName: "หมอดูทดสอบ"
            )
            XCTFail("รหัสธนาคารที่ไม่รู้จักต้องถูกปฏิเสธ")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty, "ต้องมีเหตุผลให้ผู้ใช้อ่าน")
        }

        // ผู้ใช้ทั่วไปต้องไม่เห็นบัญชีของใครเลย
        _ = try await service.signIn(email: "customer@horo.test", password: "HoroTest123!")
        let asCustomer = try await service.fetchPayoutAccount()
        XCTAssertNil(asCustomer, "ผู้ใช้ทั่วไปต้องไม่เห็นบัญชีรับเงินของหมอดู")

        try? await seerService.signOut()
    }
}
