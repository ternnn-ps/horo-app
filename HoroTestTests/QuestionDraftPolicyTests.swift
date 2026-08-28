import XCTest
@testable import HoroTest

final class QuestionDraftPolicyTests: XCTestCase {
    private let serviceID = UUID()

    func testRetryKeepsTheSameIdempotencyKeys() {
        let first = QuestionDraftPolicy.draft(reusing: nil, seerServiceID: serviceID, message: "ทักครั้งแรก")
        let retry = QuestionDraftPolicy.draft(reusing: first, seerServiceID: serviceID, message: "ทักครั้งแรก")

        XCTAssertEqual(retry.clientRequestID, first.clientRequestID)
        XCTAssertEqual(retry.clientMessageID, first.clientMessageID)
    }

    func testEditingTheMessageBeforeRetryKeepsTheSameKeys() {
        let first = QuestionDraftPolicy.draft(reusing: nil, seerServiceID: serviceID, message: "ร่างแรก")
        let edited = QuestionDraftPolicy.draft(reusing: first, seerServiceID: serviceID, message: "แก้ข้อความแล้วส่งใหม่")

        XCTAssertEqual(edited.clientRequestID, first.clientRequestID)
        XCTAssertEqual(edited.firstMessage, "แก้ข้อความแล้วส่งใหม่")
    }

    func testAskingADifferentSeerStartsANewPurchase() {
        let first = QuestionDraftPolicy.draft(reusing: nil, seerServiceID: serviceID, message: "ถามคนแรก")
        let other = QuestionDraftPolicy.draft(reusing: first, seerServiceID: UUID(), message: "ถามอีกคน")

        XCTAssertNotEqual(other.clientRequestID, first.clientRequestID)
    }

    func testAfterSuccessTheNextQuestionGetsFreshKeys() {
        let done = QuestionDraftPolicy.draft(reusing: nil, seerServiceID: serviceID, message: "คำถามที่ส่งสำเร็จแล้ว")
        // สำเร็จแล้ว view model เคลียร์ draft ทิ้ง → รอบถัดไปส่ง nil เข้ามา
        let next = QuestionDraftPolicy.draft(reusing: nil, seerServiceID: serviceID, message: "คำถามใหม่กับหมอดูคนเดิม")

        XCTAssertNotEqual(next.clientRequestID, done.clientRequestID)
    }
}
