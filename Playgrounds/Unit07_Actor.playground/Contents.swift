/*:
 # Unit 07 — Actor
 ## Data Race를 컴파일러가 막는 방법

 ---
 ### 🧠 핵심 개념 정리

 **Data Race**
 - 두 스레드가 동시에 같은 메모리 접근 + 하나 이상이 쓰기 → UB(미정의 동작)
 - 비결정적, 재현 어려움 — Xcode Thread Sanitizer(TSan)로 탐지

 **Actor**
 - 내부 상태 접근을 하나의 직렬 실행 흐름으로 컴파일러가 강제
 - 외부에서 접근 시 반드시 `await` 필요
 - class처럼 참조 타입, 암묵적으로 Sendable

 **Actor Reentrancy (재진입)**
 - await 일시 중단 중 다른 메서드가 같은 actor에서 실행 가능
 - 중간 상태 불변성이 깨질 수 있는 미묘한 버그

 **nonisolated**
 - 저장 프로퍼티 접근 없는 메서드에만 사용 가능
 - actor 외부에서 동기 접근 허용

 ---
 */

import Foundation

func delay(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - 1. Data Race 시연 (TSan으로 확인 가능)

print("=== 1. Data Race 시연 ===")

// ❌ Thread-safe하지 않은 카운터
class UnsafeBankAccount {
    var balance: Double = 1000.0

    func deposit(_ amount: Double) {
        balance += amount
    }

    func withdraw(_ amount: Double) {
        balance -= amount
    }
}

// MARK: - 2. Actor로 Data Race 해결

print("\n=== 2. Actor — BankAccount ===")

actor BankAccount {
    private(set) var balance: Double
    private var transactionLog: [String] = []

    init(balance: Double) {
        self.balance = balance
    }

    func deposit(_ amount: Double) {
        balance += amount
        transactionLog.append("입금 \(amount)")
        print("  입금 \(amount) → 잔액: \(balance)")
    }

    func withdraw(_ amount: Double) throws {
        guard balance >= amount else {
            throw BankError.insufficientFunds(balance)
        }
        balance -= amount
        transactionLog.append("출금 \(amount)")
        print("  출금 \(amount) → 잔액: \(balance)")
    }

    func transfer(to other: BankAccount, amount: Double) async throws {
        guard balance >= amount else {
            throw BankError.insufficientFunds(balance)
        }
        balance -= amount
        // ⚠️ 여기서 await — Reentrancy 발생 가능 지점
        await other.deposit(amount)
    }

    // nonisolated: 저장 프로퍼티 접근 없음 → 동기 접근 허용
    nonisolated var description: String {
        "BankAccount(actor)"
    }

    var log: [String] { transactionLog }
}

enum BankError: Error {
    case insufficientFunds(Double)
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    let account = BankAccount(balance: 1000)

    // 외부에서 접근은 반드시 await
    await account.deposit(500)

    do {
        try await account.withdraw(200)
        try await account.withdraw(2000)  // 잔액 부족
    } catch BankError.insufficientFunds(let bal) {
        print("❌ 잔액 부족: 현재 \(bal)")
    }

    print("최종 잔액: \(await account.balance)")
    print("거래 로그: \(await account.log)")
    print("nonisolated: \(account.description)")  // await 불필요!

    semaphore.signal()
}
semaphore.wait()

// MARK: - 3. Actor vs Serial Queue 동시 접근 안전성

print("\n=== 3. Actor 동시 접근 안전성 테스트 ===")

actor SafeCounter {
    var count = 0
    func increment() { count += 1 }
}

let counter = SafeCounter()
let group = DispatchGroup()

for _ in 0..<1000 {
    group.enter()
    Task {
        await counter.increment()
        group.leave()
    }
}

let sem2 = DispatchSemaphore(value: 0)
group.notify(queue: .global()) {
    Task {
        let final = await counter.count
        print("Actor 카운터: \(final) (기대: 1000)")
        sem2.signal()
    }
}
sem2.wait()

// MARK: - 4. Actor Reentrancy — 주의가 필요한 패턴

print("\n=== 4. Actor Reentrancy (재진입) ===")

actor ImageCache {
    private var cache: [String: String] = [:]
    private var inFlight: Set<String> = []

    // ❌ Reentrancy 버그 있는 버전
    func loadImageBuggy(key: String) async -> String {
        if let cached = cache[key] {
            return cached
        }
        // ⚠️ await 지점 — 다른 loadImage 호출이 여기서 끼어들 수 있음
        // 그 결과 두 번 fetch가 발생할 수 있음
        let fetched = await fetchFromNetwork(key: key)
        cache[key] = fetched
        return fetched
    }

    // ✅ Reentrancy 안전 버전 — inFlight로 중복 방지
    func loadImageSafe(key: String) async -> String {
        if let cached = cache[key] { return cached }

        if inFlight.contains(key) {
            // 이미 요청 중 — 완료까지 폴링 대기 (단순화된 예시)
            while inFlight.contains(key) {
                await delay(0.01)
            }
            return cache[key] ?? ""
        }

        inFlight.insert(key)
        let fetched = await fetchFromNetwork(key: key)
        cache[key] = fetched
        inFlight.remove(key)
        return fetched
    }

    private func fetchFromNetwork(key: String) async -> String {
        await delay(0.05)
        return "Image[\(key)]"
    }
}

let imageCache = ImageCache()
let sem3 = DispatchSemaphore(value: 0)
Task {
    async let img1 = imageCache.loadImageSafe(key: "avatar")
    async let img2 = imageCache.loadImageSafe(key: "avatar")  // 동시 요청
    let results = await (img1, img2)
    print("이미지 1: \(results.0)")
    print("이미지 2: \(results.1)")
    sem3.signal()
}
sem3.wait()

// MARK: - 5. Global Actor 개념 이해

print("\n=== 5. Global Actor ===")

// Global Actor: 앱 전체에서 단일 인스턴스로 존재하는 Actor
// @MainActor가 대표 예시 — 메인 스레드가 그 인스턴스

@globalActor
struct DatabaseActor {
    actor ActorType {}
    static let shared = ActorType()
}

@DatabaseActor
class UserRepository {
    private var users: [Int: String] = [:]

    func save(id: Int, name: String) {
        users[id] = name
        print("DB 저장: \(id) → \(name)")
    }

    func fetch(id: Int) -> String? {
        users[id]
    }
}

let repo = UserRepository()
let sem4 = DispatchSemaphore(value: 0)
Task {
    await repo.save(id: 1, name: "Leeo")
    let name = await repo.fetch(id: 1)
    print("DB 조회: \(name ?? "없음")")
    sem4.signal()
}
sem4.wait()

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] Thread Sanitizer 활성화 후 `UnsafeBankAccount`로 동시 입출금 Data Race 확인
 2. [ ] `BankAccount.transfer` 메서드에서 Reentrancy 버그를 재현하고 수정
 3. [ ] `nonisolated`에 저장 프로퍼티 접근을 추가하면 컴파일 에러가 나는지 확인
 4. [ ] `SafeCounter`와 Serial Queue 기반 카운터의 성능을 비교

 ## 💬 면접 질문 연습

 Q. Actor와 Serial DispatchQueue의 가장 큰 차이는?
 Q. Actor Reentrancy란 무엇이고 어떻게 방어하나요?
 Q. nonisolated는 언제 사용하나요?
 */
