/*:
 # Unit 10 — Combine 기초
 ## Publisher · Subscriber · Operator · Back-pressure

 ---
 ### 🧠 핵심 개념 정리

 **반응형 프로그래밍(Reactive Programming)**
 - 데이터 스트림과 변화 전파를 선언적으로 표현
 - Publisher → Operator → Subscriber 파이프라인

 **Publisher**
 - `Output`: 방출하는 값의 타입
 - `Failure`: 실패 타입 (실패 없으면 `Never`)

 **Subject (외부 주입 가능한 Publisher)**
 - `PassthroughSubject<Output, Failure>`: 초기값 없음, 새 값만 방출
 - `CurrentValueSubject<Output, Failure>`: 초기값 있음, 현재값 조회 가능

 **Back-pressure**
 - Subscriber가 처리 가능한 속도를 Publisher에게 demand로 요청
 - Combine은 pull 방식 — Subscriber가 주도

 ---
 */

import Combine
import Foundation

var cancellables = Set<AnyCancellable>()

// MARK: - 1. 기본 Publisher 종류

print("=== 1. 기본 Publisher 종류 ===")

// Just: 단일 값 방출 후 완료
Just(42)
    .sink(
        receiveCompletion: { print("Just 완료: \($0)") },
        receiveValue: { print("Just 값: \($0)") }
    )
    .store(in: &cancellables)

// [].publisher: 배열을 Publisher로
[1, 2, 3, 4, 5].publisher
    .filter { $0 % 2 == 0 }
    .map { $0 * 10 }
    .sink { print("배열 Publisher 값: \($0)") }
    .store(in: &cancellables)

// Empty: 즉시 완료, 값 없음
Empty<Int, Never>()
    .sink(
        receiveCompletion: { print("Empty 완료: \($0)") },
        receiveValue: { print("Empty 값: \($0)") }
    )
    .store(in: &cancellables)

// MARK: - 2. PassthroughSubject vs CurrentValueSubject

print("\n=== 2. Subject ===")

// PassthroughSubject: 초기값 없음
let eventBus = PassthroughSubject<String, Never>()

eventBus
    .sink { print("이벤트: \($0)") }
    .store(in: &cancellables)

// 나중에 구독한 구독자는 이전 값 못 받음
eventBus.send("로그인")
eventBus.send("홈 화면")

// CurrentValueSubject: 초기값 있음, 현재값 조회 가능
let loadingState = CurrentValueSubject<Bool, Never>(false)

print("현재 로딩 상태: \(loadingState.value)")

loadingState
    .sink { print("로딩 상태 변경: \($0)") }
    .store(in: &cancellables)

loadingState.send(true)
print("현재 로딩 상태 (변경 후): \(loadingState.value)")
loadingState.send(false)

// MARK: - 3. 핵심 Operator

print("\n=== 3. 핵심 Operator ===")

// map, filter, compactMap
let scores = [85, nil, 92, nil, 78, 100].publisher

scores
    .compactMap { $0 }           // nil 제거
    .filter { $0 >= 80 }         // 80 이상만
    .map { "점수: \($0)점" }      // 변환
    .sink { print($0) }
    .store(in: &cancellables)

// flatMap: Publisher를 반환하는 변환 (중요!)
func validateEmail(_ email: String) -> AnyPublisher<Bool, Never> {
    Just(email.contains("@") && email.contains("."))
        .eraseToAnyPublisher()
}

["valid@test.com", "invalid", "also@valid.org"].publisher
    .flatMap { validateEmail($0) }
    .sink { print("이메일 유효성: \($0)") }
    .store(in: &cancellables)

// combineLatest: 여러 Publisher 최신값 조합
print("\n--- combineLatest ---")
let username = CurrentValueSubject<String, Never>("")
let password = CurrentValueSubject<String, Never>("")

// 폼 유효성 검사 패턴
username.combineLatest(password)
    .map { user, pass in
        user.count >= 3 && pass.count >= 6
    }
    .removeDuplicates()
    .sink { isValid in
        print("폼 유효성: \(isValid ? "✅ 유효" : "❌ 무효")")
    }
    .store(in: &cancellables)

username.send("le")        // 무효
password.send("1234")      // 무효
username.send("leeo")      // 무효 (패스워드 짧음)
password.send("secure123") // ✅ 유효

// MARK: - 4. debounce + removeDuplicates (검색 UI 패턴)

print("\n=== 4. 검색 UI 패턴 — debounce + removeDuplicates ===")

let searchInput = PassthroughSubject<String, Never>()

searchInput
    .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
    .removeDuplicates()
    .filter { !$0.isEmpty }
    .sink { query in
        print("검색 실행: '\(query)'")
    }
    .store(in: &cancellables)

// 빠른 타이핑 시뮬레이션
searchInput.send("S")
searchInput.send("Sw")
searchInput.send("Swi")
searchInput.send("Swif")
searchInput.send("Swift")  // 100ms 후 이것만 검색됨
searchInput.send("Swift")  // removeDuplicates로 무시됨

Thread.sleep(forTimeInterval: 0.2)  // debounce 대기

// MARK: - 5. merge, zip 비교

print("\n=== 5. merge vs zip ===")

let streamA = PassthroughSubject<Int, Never>()
let streamB = PassthroughSubject<Int, Never>()

// merge: 어느 쪽이든 방출 시 전달
streamA.merge(with: streamB)
    .sink { print("merge: \($0)") }
    .store(in: &cancellables)

streamA.send(1)
streamB.send(10)
streamA.send(2)
streamB.send(20)

// zip: 쌍을 이루는 값이 모두 있을 때만 방출
let zipA = PassthroughSubject<String, Never>()
let zipB = PassthroughSubject<Int, Never>()

zipA.zip(zipB)
    .sink { (name, age) in print("zip: \(name) / \(age)") }
    .store(in: &cancellables)

zipA.send("Alice")
zipB.send(25)    // ("Alice", 25) 방출
zipA.send("Bob") // 대기 중
zipB.send(30)    // ("Bob", 30) 방출

// MARK: - 6. assign(to:on:) vs sink

print("\n=== 6. assign으로 프로퍼티 바인딩 ===")

class DisplayModel {
    var title: String = "" {
        didSet { print("title 변경: \(title)") }
    }
}

let model = DisplayModel()

Just("Hello Combine")
    .assign(to: \.title, on: model)
    .store(in: &cancellables)

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] `PassthroughSubject`와 `CurrentValueSubject`의 차이를 늦게 구독하는 subscriber로 확인
 2. [ ] `combineLatest`로 이메일·패스워드·약관동의 3개를 조합한 버튼 활성화 로직 구현
 3. [ ] `flatMap`으로 버튼 탭 이벤트를 네트워크 요청 Publisher로 변환하는 패턴 구현
 4. [ ] `debounce` 시간을 0으로 바꾸면 모든 입력이 전달됨을 확인

 ## 💬 면접 질문 연습

 Q. PassthroughSubject와 CurrentValueSubject의 차이는?
 Q. flatMap과 map의 차이를 Publisher 관점에서 설명하세요
 Q. Back-pressure가 무엇이고 Combine에서 어떻게 처리되나요?
 */
