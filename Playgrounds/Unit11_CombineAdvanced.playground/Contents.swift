/*:
 # Unit 11 — Combine 심화
 ## 에러 처리 · 스케줄러 · 메모리 관리

 ---
 ### 🧠 핵심 개념 정리

 **에러 처리 연산자**
 - `catch`: 에러 시 대체 Publisher로 복구
 - `retry(N)`: 업스트림 N회 재구독 (재시도)
 - `replaceError(with:)`: 에러를 기본값으로 대체, Failure → Never
 - `mapError`: Failure 타입 변환

 **Scheduler (스케줄러)**
 - `subscribe(on:)`: 업스트림 구독(생산) 스케줄러 지정
 - `receive(on:)`: 다운스트림 수신(처리) 스케줄러 지정
 - UI 업데이트: `.receive(on: RunLoop.main)`

 **메모리 관리**
 - `AnyCancellable`: 구독 토큰, 해제 시 자동 구독 취소
 - `store(in: &cancellables)`: 소유 객체 생명주기와 구독 동기화
 - `assign(to: &$published)`: retain cycle 없는 바인딩

 ---
 */

import Combine
import Foundation

// MARK: - 1. 에러 처리 — catch, replaceError, retry

print("=== 1. 에러 처리 ===")

enum APIError: Error, LocalizedError {
    case unauthorized
    case serverError(Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "인증 오류"
        case .serverError(let code): return "서버 오류 \(code)"
        case .timeout: return "타임아웃"
        }
    }
}

var attemptCount = 0

// 처음 2번은 실패, 3번째 성공하는 Publisher
func unstablePublisher() -> AnyPublisher<String, APIError> {
    attemptCount += 1
    print("  시도 \(attemptCount)회")
    if attemptCount < 3 {
        return Fail(error: APIError.serverError(503)).eraseToAnyPublisher()
    }
    return Just("성공 응답").setFailureType(to: APIError.self).eraseToAnyPublisher()
}

var cancellables = Set<AnyCancellable>()

// retry: 실패 시 재시도
unstablePublisher()
    .retry(3)
    .sink(
        receiveCompletion: { print("완료: \($0)") },
        receiveValue: { print("값: \($0)") }
    )
    .store(in: &cancellables)

// catch: 에러 시 대체 Publisher
print("\n--- catch ---")
Fail<String, APIError>(error: .timeout)
    .catch { error -> AnyPublisher<String, Never> in
        print("에러 복구: \(error.localizedDescription!)")
        return Just("기본값").eraseToAnyPublisher()
    }
    .sink { print("catch 결과: \($0)") }
    .store(in: &cancellables)

// replaceError: 에러를 기본값으로 (Failure → Never)
print("\n--- replaceError ---")
Fail<Int, APIError>(error: .unauthorized)
    .replaceError(with: -1)  // Failure 타입이 Never로 변경됨
    .sink { print("replaceError 결과: \($0)") }
    .store(in: &cancellables)

// mapError: 에러 타입 변환
print("\n--- mapError ---")
struct AppError: Error {
    let message: String
}

Fail<String, APIError>(error: .serverError(500))
    .mapError { apiError -> AppError in
        AppError(message: apiError.localizedDescription ?? "알 수 없는 오류")
    }
    .sink(
        receiveCompletion: {
            if case .failure(let e) = $0 { print("AppError: \(e.message)") }
        },
        receiveValue: { _ in }
    )
    .store(in: &cancellables)

// MARK: - 2. Scheduler — subscribe(on:) vs receive(on:)

print("\n=== 2. Scheduler ===")

// subscribe(on:): 업스트림이 실행되는 스케줄러 (생산 측)
// receive(on:): 다운스트림에서 값을 수신하는 스케줄러 (소비 측)

Just("데이터")
    .subscribe(on: DispatchQueue.global(qos: .background))  // 생산을 백그라운드에서
    .map { value -> String in
        print("map 스레드: \(Thread.isMainThread ? "Main" : "BG")")
        return value.uppercased()
    }
    .receive(on: DispatchQueue.main)  // 수신은 메인 스레드에서
    .sink { value in
        print("sink 스레드: \(Thread.isMainThread ? "Main" : "BG") | 값: \(value)")
    }
    .store(in: &cancellables)

Thread.sleep(forTimeInterval: 0.1)

// MARK: - 3. 메모리 관리 — AnyCancellable

print("\n=== 3. AnyCancellable 메모리 관리 ===")

// ❌ 저장 안 하면 즉시 취소됨
print("--- AnyCancellable 저장 안 하는 경우 ---")
let subject = PassthroughSubject<Int, Never>()

// 저장하지 않음 → 즉시 해제 → 구독 취소
let _ = subject.sink { print("받음: \($0)") }

subject.send(1)   // 출력 안 됨! 구독이 이미 취소됨
subject.send(2)   // 출력 안 됨!
print("값을 보냈지만 구독이 취소되어 수신 안 됨")

// ✅ 저장하는 경우
print("\n--- AnyCancellable 올바른 저장 ---")
let subject2 = PassthroughSubject<Int, Never>()

subject2
    .sink { print("받음: \($0)") }
    .store(in: &cancellables)  // Set에 저장

subject2.send(10)   // 출력됨
subject2.send(20)   // 출력됨

// MARK: - 4. retain cycle 주의 — [weak self]

print("\n=== 4. retain cycle — [weak self] 패턴 ===")

class ViewModel {
    var title = "초기값"
    var bag = Set<AnyCancellable>()

    init() {
        // ❌ retain cycle 위험: self → bag → sink closure → self
        // PassthroughSubject<String, Never>()
        //     .sink { self.title = $0 }  // strong capture
        //     .store(in: &bag)

        // ✅ [weak self]로 순환 참조 방지
        PassthroughSubject<String, Never>()
            .sink { [weak self] newTitle in
                self?.title = newTitle
                print("title 업데이트: \(newTitle)")
            }
            .store(in: &bag)
    }

    deinit { print("ViewModel 해제됨") }
}

do {
    let vm = ViewModel()
    print("ViewModel 생성: \(vm.title)")
}
// scope 벗어나면 ViewModel 해제됨 (retain cycle 없으면)
Thread.sleep(forTimeInterval: 0.05)

// MARK: - 5. assign(to: &$published) — 가장 안전한 바인딩

print("\n=== 5. assign(to: &$published) ===")

// Playground에서는 ObservableObject 없이 CurrentValueSubject로 시뮬레이션
// 실제 앱에서:
//
// @MainActor
// class ViewModel: ObservableObject {
//     @Published var items: [String] = []
//
//     func setup() {
//         // ✅ AnyCancellable 저장 불필요 + retain cycle 없음
//         fetchItems()
//             .assign(to: &$items)
//     }
// }

let destination = CurrentValueSubject<[Int], Never>([])

[1, 2, 3].publisher
    .collect()
    .assign(to: \.value, on: destination)
    .store(in: &cancellables)

print("assign 결과: \(destination.value)")

// MARK: - 6. 실전 패턴 — 네트워크 요청 전체 파이프라인

print("\n=== 6. 실전 파이프라인 ===")

struct Post: Decodable {
    let id: Int
    let title: String
}

func fetchPosts() -> AnyPublisher<[Post], Error> {
    guard let url = URL(string: "https://jsonplaceholder.typicode.com/posts?_limit=3") else {
        return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
    }

    return URLSession.shared.dataTaskPublisher(for: url)
        .map(\.data)
        .decode(type: [Post].self, decoder: JSONDecoder())
        .eraseToAnyPublisher()
}

let sem = DispatchSemaphore(value: 0)
fetchPosts()
    .retry(1)
    .replaceError(with: [])
    .receive(on: DispatchQueue.main)
    .sink { posts in
        print("포스트 수: \(posts.count)")
        posts.prefix(2).forEach { print("  - \($0.id): \($0.title)") }
        sem.signal()
    }
    .store(in: &cancellables)

sem.wait()

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] `retry(3)` 파이프라인에서 4번 모두 실패하면 어떻게 되는지 확인
 2. [ ] `subscribe(on:)` 없이 `receive(on:)`만 사용하면 map은 어느 스레드에서 실행되는지 확인
 3. [ ] `AnyCancellable`을 저장하지 않으면 구독이 즉시 취소됨을 직접 확인
 4. [ ] Instruments의 Leaks로 [weak self] 없는 버전의 retain cycle 탐지 실험

 ## 💬 면접 질문 연습

 Q. `subscribe(on:)`과 `receive(on:)`의 차이를 업스트림/다운스트림 관점에서 설명하세요
 Q. `AnyCancellable`을 저장하지 않으면 어떻게 되나요?
 Q. `assign(to: &$published)`가 `assign(to:on:)`보다 안전한 이유는?
 */
