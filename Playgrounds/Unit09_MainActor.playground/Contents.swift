/*:
 # Unit 09 — @MainActor
 ## UI 업데이트를 안전하게 하는 방법

 ---
 ### 🧠 핵심 개념 정리

 **@MainActor란?**
 - 메인 스레드(= 메인 실행 직렬 컨텍스트)에 격리됨을 선언
 - UIKit/SwiftUI의 Non-thread-safe 설계 원칙을 컴파일러가 강제
 - `DispatchQueue.main.async {}`의 컴파일러 강제 버전

 **적용 범위**
 - `@MainActor func`: 해당 함수 전체를 메인 스레드에서 실행
 - `@MainActor var`: 프로퍼티 접근을 메인 스레드로 제한
 - `@MainActor class`: 전체 타입을 메인 스레드에 격리
 - `MainActor.run {}`: 임의 컨텍스트에서 메인 스레드 블록 실행

 **DispatchQueue.main vs @MainActor**
 - DispatchQueue.main.async: 런타임에 비동기 전환 (컴파일러 체크 없음)
 - @MainActor: 컴파일러가 잘못된 접근을 에러로 강제

 ---
 */

import Foundation

// Playground에서는 UIKit 없이 @MainActor 동작 시뮬레이션

func delay(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - 1. @MainActor 기본 동작

print("=== 1. @MainActor 기본 ===")

@MainActor
func updateUI(text: String) {
    // 이 함수는 항상 메인 스레드에서 실행됨
    print("UI 업데이트: \(text) | isMain: \(Thread.isMainThread)")
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    // 백그라운드에서 데이터 처리
    await delay(0.05)
    let result = "처리된 데이터"

    // @MainActor 함수 호출 → 컴파일러가 자동으로 메인 스레드 전환
    await updateUI(text: result)
    semaphore.signal()
}
semaphore.wait()

// MARK: - 2. @MainActor ViewModel 패턴

print("\n=== 2. @MainActor ViewModel ===")

// 실제 앱에서는 ObservableObject와 함께 사용
@MainActor
class ProfileViewModel {
    // @Published 대신 단순 프로퍼티 (Playground 환경)
    var userName: String = "" {
        didSet { print("  userName 업데이트: \(userName) | isMain: \(Thread.isMainThread)") }
    }
    var isLoading: Bool = false {
        didSet { print("  isLoading: \(isLoading)") }
    }
    var errorMessage: String? {
        didSet {
            if let msg = errorMessage { print("  에러: \(msg)") }
        }
    }

    func loadProfile(id: String) async {
        isLoading = true  // 메인 스레드, 안전
        defer { isLoading = false }

        do {
            // fetchProfile은 백그라운드에서 실행될 수 있음
            let name = try await fetchProfileFromNetwork(id: id)
            // @MainActor 메서드이므로 await 이후에도 메인 스레드 보장
            userName = name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchProfileFromNetwork(id: String) async throws -> String {
        // 실제로는 여기서 URLSession 호출
        await delay(0.1)
        if id == "error" { throw NSError(domain: "test", code: -1) }
        return "User_\(id)"
    }
}

let viewModel = ProfileViewModel()
let sem2 = DispatchSemaphore(value: 0)

Task { @MainActor in
    await viewModel.loadProfile(id: "leeo")
    await viewModel.loadProfile(id: "error")
    sem2.signal()
}
sem2.wait()

// MARK: - 3. MainActor.run — 임의 컨텍스트에서 메인 전환

print("\n=== 3. MainActor.run ===")

let sem3 = DispatchSemaphore(value: 0)
Task.detached {  // 액터 컨텍스트 없음
    print("detached Task | isMain: \(Thread.isMainThread)")

    // MainActor.run으로 명시적 메인 전환
    await MainActor.run {
        print("MainActor.run 블록 | isMain: \(Thread.isMainThread)")
    }

    // MainActor.run에서 값 반환도 가능
    let result = await MainActor.run { () -> String in
        return "메인에서 계산"
    }
    print("반환값: \(result)")
    sem3.signal()
}
sem3.wait()

// MARK: - 4. nonisolated — @MainActor 클래스에서 일부 메서드만 제외

print("\n=== 4. nonisolated on @MainActor class ===")

@MainActor
class DataManager {
    var cache: [String: String] = [:]

    func updateCache(key: String, value: String) {
        // 메인 스레드에서만 실행
        cache[key] = value
        print("캐시 업데이트: \(key) | isMain: \(Thread.isMainThread)")
    }

    // nonisolated: 상태 접근 없으므로 메인 격리 불필요
    nonisolated func formatKey(_ raw: String) -> String {
        return raw.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    // nonisolated async: 백그라운드에서 무거운 작업 처리 가능
    nonisolated func heavyCalculation(_ input: Int) async -> Int {
        await delay(0.05)
        return input * input
    }
}

let dataManager = DataManager()
let sem4 = DispatchSemaphore(value: 0)
Task {
    // nonisolated 메서드 — await 없이(동기) or Task 없이 호출 가능
    let key = dataManager.formatKey("User Name")
    print("포맷된 키: \(key)")

    // nonisolated async — 백그라운드 실행
    let result = await dataManager.heavyCalculation(7)
    print("계산 결과: \(result)")

    // @MainActor 메서드 — 메인 전환 필요
    await dataManager.updateCache(key: key, value: "leeo")
    sem4.signal()
}
sem4.wait()

// MARK: - 5. DispatchQueue.main.async vs @MainActor 비교

print("\n=== 5. 두 방식 비교 ===")

func oldStyle_updateUI(text: String) {
    DispatchQueue.global().async {
        // 무거운 작업
        let processed = text.uppercased()
        DispatchQueue.main.async {
            // ⚠️ 컴파일러가 이 패턴의 올바름을 검증 못 함
            print("oldStyle: \(processed) | isMain: \(Thread.isMainThread)")
        }
    }
}

@MainActor
func newStyle_updateUI(text: String) async {
    // ✅ 컴파일러가 항상 메인 스레드임을 보장
    let processed = text.uppercased()  // 실제론 await로 백그라운드 이동 권장
    print("newStyle: \(processed) | isMain: \(Thread.isMainThread)")
}

oldStyle_updateUI(text: "hello")

let sem5 = DispatchSemaphore(value: 0)
Task {
    await newStyle_updateUI(text: "hello")
    sem5.signal()
}
sem5.wait()

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] `@MainActor` 없이 백그라운드에서 UI 업데이트 시도 후 런타임 경고 확인
 2. [ ] `@MainActor ViewModel`의 모든 프로퍼티가 메인 스레드에서 업데이트되는지 `Thread.isMainThread`로 검증
 3. [ ] `nonisolated func`에 `@MainActor` 프로퍼티 접근을 추가하면 컴파일 에러가 남을 확인
 4. [ ] `MainActor.run`과 `DispatchQueue.main.async`를 섞어 쓸 때 실행 순서 실험

 ## 💬 면접 질문 연습

 Q. @MainActor와 DispatchQueue.main.async의 차이는?
 Q. @MainActor class에서 일부 메서드만 백그라운드에서 실행하려면?
 Q. await 이후에도 @MainActor 함수는 메인 스레드를 보장하나요?
 */
