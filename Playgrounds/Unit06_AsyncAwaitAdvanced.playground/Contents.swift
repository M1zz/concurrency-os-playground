/*:
 # Unit 06 — async/await 심화
 ## Task · TaskGroup · async let · 협력적 취소

 ---
 ### 🧠 핵심 개념 정리

 **Task**
 - Swift Concurrency의 기본 비동기 실행 단위
 - `Task.init`: 현재 액터 컨텍스트·우선순위 상속
 - `Task.detached`: 완전히 독립 (액터 컨텍스트 없음)
 - 협력적 취소: `cancel()` → `Task.isCancelled` / `checkCancellation()`

 **async let — 병렬 시작, 나중에 수집**
 - 즉시 작업 시작, await 시점에 결과 수집
 - 정적 개수의 독립 작업에 적합
 - 순차 await 대비 성능: Σ(각 시간) → max(각 시간)

 **TaskGroup — 동적 병렬 작업**
 - `withTaskGroup` / `withThrowingTaskGroup`
 - 동적 개수의 작업을 `addTask`로 추가
 - `for await in group` 으로 완료 순서대로 수집

 ---
 */

import Foundation

func delay(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - 1. Task 기본 — 비동기 컨텍스트 생성

print("=== 1. Task 기본 ===")

let semaphore = DispatchSemaphore(value: 0)

Task(priority: .userInitiated) {
    print("Task 시작 | priority: \(Task.currentPriority)")
    await delay(0.05)
    print("Task 완료")
    semaphore.signal()
}

semaphore.wait()

// MARK: - 2. 순차 await vs async let 성능 비교

print("\n=== 2. 순차 await vs async let (병렬) 성능 비교 ===")

func fetchA() async -> String {
    await delay(0.1); return "A"
}
func fetchB() async -> String {
    await delay(0.1); return "B"
}
func fetchC() async -> String {
    await delay(0.1); return "C"
}

let sem2 = DispatchSemaphore(value: 0)
Task {
    let clock = ContinuousClock()

    // ❌ 순차: 총 0.3s (0.1 + 0.1 + 0.1)
    let sequential = await clock.measure {
        let a = await fetchA()
        let b = await fetchB()
        let c = await fetchC()
        print("순차 결과: \(a), \(b), \(c)")
    }
    print("순차 시간: \(sequential)")

    // ✅ 병렬: 총 ≈0.1s (max(0.1, 0.1, 0.1))
    let parallel = await clock.measure {
        async let a = fetchA()  // 즉시 시작
        async let b = fetchB()  // 즉시 시작
        async let c = fetchC()  // 즉시 시작
        let results = await (a, b, c)  // 모두 완료 대기
        print("병렬 결과: \(results.0), \(results.1), \(results.2)")
    }
    print("병렬 시간: \(parallel)")

    sem2.signal()
}
sem2.wait()

// MARK: - 3. withTaskGroup — 동적 배열 병렬 처리

print("\n=== 3. withTaskGroup — 이미지 배열 병렬 처리 ===")

func downloadImage(id: Int) async -> String {
    let delay = Double.random(in: 0.03...0.08)
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    return "Image#\(id)"
}

let sem3 = DispatchSemaphore(value: 0)
Task {
    let imageIds = Array(1...6)

    let results = await withTaskGroup(of: String.self) { group in
        for id in imageIds {
            group.addTask {
                await downloadImage(id: id)
            }
        }
        var images: [String] = []
        for await image in group {  // 완료 순서대로 수집 (순서 비보장!)
            images.append(image)
        }
        return images
    }

    print("다운로드 완료 (완료 순): \(results)")
    sem3.signal()
}
sem3.wait()

// MARK: - 4. withThrowingTaskGroup — 에러 시 자동 취소

print("\n=== 4. withThrowingTaskGroup — 에러 전파 ===")

enum FetchError: Error {
    case failed(Int)
}

func fetchOrFail(id: Int) async throws -> String {
    await delay(0.03)
    if id == 3 { throw FetchError.failed(id) }
    return "Data#\(id)"
}

let sem4 = DispatchSemaphore(value: 0)
Task {
    do {
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 1...5 {
                group.addTask { try await fetchOrFail(id: i) }
            }
            var collected: [String] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        print("결과: \(results)")
    } catch FetchError.failed(let id) {
        print("❌ id \(id) 실패 → 그룹 내 나머지 Task 자동 취소")
    }
    sem4.signal()
}
sem4.wait()

// MARK: - 5. 협력적 취소 (Cooperative Cancellation)

print("\n=== 5. 협력적 취소 ===")

func cancellableWork() async throws -> String {
    for step in 1...10 {
        // 취소 확인 방법 1: Task.isCancelled
        if Task.isCancelled {
            print("  isCancelled: step \(step)에서 종료")
            return "취소됨"
        }

        // 취소 확인 방법 2: checkCancellation() — 취소 시 throw
        // try Task.checkCancellation()

        print("  작업 step \(step)")
        await delay(0.02)
    }
    return "완료"
}

let sem5 = DispatchSemaphore(value: 0)
Task {
    let task = Task {
        try? await cancellableWork()
    }

    await delay(0.05)  // 2-3 step 실행 후 취소
    task.cancel()

    let _ = await task.value
    sem5.signal()
}
sem5.wait()

// MARK: - 6. Task.detached vs Task.init 차이

print("\n=== 6. Task.init vs Task.detached ===")

// Task.init: 현재 액터 컨텍스트와 우선순위 상속
// Task.detached: 완전히 독립, 액터 격리 없음

let sem6 = DispatchSemaphore(value: 0)
Task(priority: .high) {
    print("부모 Task priority: \(Task.currentPriority)")

    // 상속: 부모의 priority 상속됨
    Task {
        print("자식 Task(inherit) priority: \(Task.currentPriority)")
    }

    // 독립: priority 상속 안 됨
    Task.detached(priority: .background) {
        print("detached Task priority: \(Task.currentPriority)")
    }

    await delay(0.1)
    sem6.signal()
}
sem6.wait()

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] `async let` 3개 작업의 총 시간이 max(개별 시간)임을 ContinuousClock으로 측정
 2. [ ] `withThrowingTaskGroup`에서 에러 발생 시 이미 완료된 Task 수를 카운트해보기
 3. [ ] 취소 가능한 검색 Task: 새 입력마다 이전 Task를 `cancel()`하는 패턴 구현
 4. [ ] `Task.sleep`이 취소되면 `CancellationError`가 발생함을 확인

 ## 💬 면접 질문 연습

 Q. async let과 TaskGroup의 차이와 각각의 사용 시점은?
 Q. Task 취소는 왜 '협력적(cooperative)'인가요?
 Q. Task.detached를 쓰면 안 좋은 경우는?
 */
