/*:
 # Unit 05 — async/await 기초
 ## Swift Concurrency 입문 · 구조적 동시성 · Continuation

 ---
 ### 🧠 핵심 개념 정리

 **왜 async/await인가?**
 - 콜백 중첩 → 콜백 지옥(Callback Hell) 해결
 - 에러 처리·취소 전파가 언어 차원에서 통합
 - 코루틴(Coroutine) 기반: 스레드 블로킹 없이 '일시 중단'

 **핵심 키워드**
 - `async`: 이 함수는 일시 중단될 수 있다 (suspend point 존재)
 - `await`: 여기서 일시 중단, 결과 기다림 (스레드는 해제됨)
 - `throws + async`: `try await`로 호출, `do-catch`로 처리

 **Continuation**
 - 기존 콜백 API를 async 함수로 변환하는 브릿지
 - `resume`은 반드시 정확히 1회만 호출

 ---
 */

import Foundation

// MARK: - 1. 기본 async 함수 정의와 호출

print("=== 1. 기본 async/await ===")

/// 비동기 지연 시뮬레이션 (스레드 블로킹 아님)
func delay(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

func fetchUsername(id: Int) async -> String {
    await delay(0.05)
    return "User#\(id)"
}

func fetchUserAge(id: Int) async -> Int {
    await delay(0.05)
    return 20 + id
}

// async 함수를 동기 컨텍스트에서 실행하려면 Task { } 필요
let semaphore = DispatchSemaphore(value: 0)

Task {
    let name = await fetchUsername(id: 42)
    let age = await fetchUserAge(id: 42)
    print("이름: \(name), 나이: \(age)")  // 순차 실행 (총 시간 ≈ 0.1s)
    semaphore.signal()
}

semaphore.wait()

// MARK: - 2. async throws — 에러 처리

print("\n=== 2. async throws + try await ===")

enum NetworkError: Error {
    case invalidURL
    case serverError(Int)
    case noData
}

func fetchData(from urlString: String) async throws -> String {
    await delay(0.05)

    guard urlString.hasPrefix("https") else {
        throw NetworkError.invalidURL
    }

    if urlString.contains("fail") {
        throw NetworkError.serverError(500)
    }

    return "응답 데이터 from \(urlString)"
}

let sem2 = DispatchSemaphore(value: 0)
Task {
    // 성공 케이스
    do {
        let data = try await fetchData(from: "https://api.example.com")
        print("✅ 성공: \(data)")
    } catch {
        print("❌ 에러: \(error)")
    }

    // 실패 케이스
    do {
        let _ = try await fetchData(from: "https://api.fail.com")
    } catch NetworkError.serverError(let code) {
        print("❌ 서버 에러 \(code)")
    } catch {
        print("❌ 기타 에러: \(error)")
    }

    sem2.signal()
}
sem2.wait()

// MARK: - 3. Continuation — 콜백 API를 async로 변환

print("\n=== 3. withCheckedContinuation — 콜백 브릿지 ===")

// 레거시 콜백 API (변경 불가능한 상황 가정)
func legacyFetchUser(id: Int, completion: @escaping (String?, Error?) -> Void) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
        if id > 0 {
            completion("LegacyUser#\(id)", nil)
        } else {
            completion(nil, NetworkError.invalidURL)
        }
    }
}

// Continuation으로 async 래핑
func fetchUserAsync(id: Int) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        legacyFetchUser(id: id) { user, error in
            if let error = error {
                continuation.resume(throwing: error)  // 에러 전달
            } else if let user = user {
                continuation.resume(returning: user)  // 값 전달
            }
            // ⚠️ resume을 두 번 호출하면 크래시! 반드시 1회만
        }
    }
}

let sem3 = DispatchSemaphore(value: 0)
Task {
    do {
        let user = try await fetchUserAsync(id: 5)
        print("✅ Continuation 결과: \(user)")

        let _ = try await fetchUserAsync(id: -1)
    } catch {
        print("❌ Continuation 에러: \(error)")
    }
    sem3.signal()
}
sem3.wait()

// MARK: - 4. 순차 await — 콜백 지옥과 비교

print("\n=== 4. 콜백 지옥 vs async/await 가독성 비교 ===")

// ❌ 콜백 방식 — 중첩이 깊어짐
func callbackHell() {
    legacyFetchUser(id: 1) { user1, _ in
        guard let user1 = user1 else { return }
        legacyFetchUser(id: 2) { user2, _ in
            guard let user2 = user2 else { return }
            legacyFetchUser(id: 3) { user3, _ in
                guard let user3 = user3 else { return }
                print("콜백: \(user1), \(user2), \(user3)")
                // 에러 처리, 취소 처리 → 모두 수동
            }
        }
    }
}

// ✅ async/await 방식 — 직선 코드
func asyncChain() async throws {
    let user1 = try await fetchUserAsync(id: 1)
    let user2 = try await fetchUserAsync(id: 2)
    let user3 = try await fetchUserAsync(id: 3)
    print("async: \(user1), \(user2), \(user3)")
    // 에러는 throws로 자동 전파
}

let sem4 = DispatchSemaphore(value: 0)
Task {
    try? await asyncChain()
    sem4.signal()
}
sem4.wait()

// MARK: - 5. async 프로퍼티

print("\n=== 5. async 프로퍼티 ===")

struct UserProfile {
    let id: Int

    var displayName: String {
        get async {
            await delay(0.01)
            return "Profile#\(id)"
        }
    }
}

let sem5 = DispatchSemaphore(value: 0)
Task {
    let profile = UserProfile(id: 99)
    let name = await profile.displayName
    print("async 프로퍼티: \(name)")
    sem5.signal()
}
sem5.wait()

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] `legacyFetchUser`를 `withCheckedContinuation` (throwing 버전)으로 래핑
 2. [ ] `fetchData`를 3번 순차 호출하고 총 시간을 ContinuousClock으로 측정
 3. [ ] `withCheckedContinuation`에서 `resume`을 2번 호출하면 어떻게 되는지 실험

 ## 💬 면접 질문 연습

 Q. await는 스레드를 블로킹하나요? 동작 원리를 설명하세요.
 Q. async throws 함수에서 에러가 발생하면 어떻게 전파되나요?
 Q. Continuation의 resume을 0번 호출하면 어떻게 되나요?
 */
