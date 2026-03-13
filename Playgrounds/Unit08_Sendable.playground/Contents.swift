/*:
 # Unit 08 — Sendable
 ## 스레드 안전성을 타입 시스템으로 보장하기

 ---
 ### 🧠 핵심 개념 정리

 **Sendable 프로토콜**
 - 동시성 경계(concurrency boundary)를 안전하게 넘길 수 있는 타입
 - 컴파일러가 검사 → Data Race를 정적으로(컴파일 타임에) 방지

 **자동 Sendable 적합성**
 - `struct`: 모든 저장 프로퍼티가 Sendable → 자동 채택
 - `enum`: 연관값이 모두 Sendable → 자동 채택
 - `actor`: 격리 보장 → 암묵적 Sendable
 - `final class` + 불변 저장 프로퍼티 → 자동 채택 가능

 **@unchecked Sendable**
 - 컴파일러 검사를 우회 → 개발자가 직접 thread-safety 책임
 - NSLock, serial queue 등으로 내부를 직접 보호해야 함

 **@Sendable 클로저**
 - Task, TaskGroup에 전달되는 클로저는 @Sendable 강제
 - 캡처 값도 반드시 Sendable이어야 함

 ---
 */

import Foundation

// MARK: - 1. 자동 Sendable 적합성

print("=== 1. Value Type — 자동 Sendable ===")

// ✅ struct: 모든 프로퍼티가 Sendable → 자동 채택
struct UserProfile: Sendable {
    let id: String
    let name: String
    let age: Int
}

// ✅ enum: 연관값이 모두 Sendable → 자동
enum AppState: Sendable {
    case idle
    case loading
    case loaded(UserProfile)
    case failed(String)
}

// ✅ Task에 안전하게 전달 가능
let profile = UserProfile(id: "1", name: "Leeo", age: 30)
let semaphore = DispatchSemaphore(value: 0)

Task {
    // profile은 Sendable → 경계 넘기기 가능
    let processed = await processProfile(profile)
    print("처리된 프로필: \(processed)")
    semaphore.signal()
}

func processProfile(_ profile: UserProfile) async -> String {
    try? await Task.sleep(nanoseconds: 10_000_000)
    return "\(profile.name)(\(profile.id))"
}

semaphore.wait()

// MARK: - 2. class의 Sendable 문제

print("\n=== 2. class — 직접 Sendable 선언 필요 ===")

// ❌ non-Sendable class — Task 경계 넘기기 위험
class MutableState {
    var value: Int = 0  // 가변 공유 상태 → Data Race 위험
}

// ✅ @unchecked Sendable + 내부 동기화
final class ThreadSafeState: @unchecked Sendable {
    private var _value: Int = 0
    private let lock = NSLock()

    var value: Int {
        lock.withLock { _value }
    }

    func increment() {
        lock.withLock { _value += 1 }
    }

    func set(_ newValue: Int) {
        lock.withLock { _value = newValue }
    }
}

let state = ThreadSafeState()
let group = DispatchGroup()

for i in 0..<100 {
    group.enter()
    Task {
        state.increment()
        if i == 99 { group.leave() }
        else { group.leave() }
    }
}

let sem2 = DispatchSemaphore(value: 0)
group.notify(queue: .global()) {
    sem2.signal()
}
sem2.wait()
print("ThreadSafeState 최종값: \(state.value)")

// MARK: - 3. @Sendable 클로저

print("\n=== 3. @Sendable 클로저 ===")

// @Sendable 클로저: 캡처한 값도 Sendable이어야 함
struct Config: Sendable {
    let maxRetry: Int
    let timeout: Double
}

let config = Config(maxRetry: 3, timeout: 30.0)

// Task 클로저는 @Sendable — config(Sendable) 캡처 OK
let task = Task {
    print("Config 사용: maxRetry=\(config.maxRetry)")
    return config.maxRetry
}

let sem3 = DispatchSemaphore(value: 0)
Task {
    let result = await task.value
    print("Task 결과: \(result)")
    sem3.signal()
}
sem3.wait()

// MARK: - 4. Sendable 검사 강도 (Swift 6 strict concurrency)

print("\n=== 4. Sendable 경계 넘기기 패턴 ===")

// non-Sendable 타입을 경계 넘기는 올바른 방법들

// 방법 1: 값 복사 (Copy before crossing)
class ImageProcessor {
    var settings: [String: Any] = [:]
}

struct ProcessorSnapshot: Sendable {
    let settings: [String: String]  // Sendable 형태로 변환
}

let processor = ImageProcessor()
processor.settings = ["filter": "blur", "strength": "0.5"]

// Sendable 스냅샷으로 변환 후 경계 넘기기
let snapshot = ProcessorSnapshot(
    settings: processor.settings.compactMapValues { $0 as? String }
)

let sem4 = DispatchSemaphore(value: 0)
Task {
    print("스냅샷 설정: \(snapshot.settings)")
    sem4.signal()
}
sem4.wait()

// 방법 2: Actor 내부로 이동
actor ProcessorActor {
    private let settings: [String: String]

    init(settings: [String: String]) {
        self.settings = settings
    }

    func process() -> String {
        "처리됨 with \(settings)"
    }
}

let processorActor = ProcessorActor(settings: snapshot.settings)
let sem5 = DispatchSemaphore(value: 0)
Task {
    let result = await processorActor.process()
    print("Actor 처리: \(result)")
    sem5.signal()
}
sem5.wait()

// MARK: - 5. Sendable 체크리스트 확인

print("\n=== 5. 타입별 Sendable 요약 ===")

print("""
타입 종류         | Sendable 여부
------------------+----------------------------------
Int, String, Bool | ✅ 기본 타입 자동 Sendable
struct (불변)     | ✅ 모든 프로퍼티 Sendable이면 자동
enum              | ✅ 연관값이 Sendable이면 자동
actor             | ✅ 암묵적 Sendable (격리 보장)
final class (불변)| ✅ 조건 충족 시 자동 가능
가변 class        | ❌ @unchecked + 직접 동기화 필요
클로저            | @Sendable 명시 필요 (Task 내부)
""")

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] non-Sendable class를 Task 클로저에서 캡처하고 컴파일러 경고 확인 (Swift 6 모드)
 2. [ ] `@unchecked Sendable` 클래스를 Actor로 리팩토링
 3. [ ] struct의 프로퍼티에 non-Sendable 타입을 넣으면 Sendable 자동 채택이 실패함을 확인
 4. [ ] `NSLock.withLock`과 Actor 중 어떤 것이 더 ergonomic한지 비교

 ## 💬 면접 질문 연습

 Q. Sendable이 없던 시절 thread safety를 어떻게 보장했나요?
 Q. @unchecked Sendable의 위험성은 무엇인가요?
 Q. Swift 6 strict concurrency에서 기존 코드의 어떤 부분이 에러가 되나요?
 */
