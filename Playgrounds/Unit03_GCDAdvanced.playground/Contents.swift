/*:
 # Unit 03 — GCD 심화
 ## DispatchGroup · DispatchSemaphore · Barrier · Reader-Writer Lock

 ---
 ### 🧠 핵심 개념 정리

 **DispatchGroup**
 - 여러 비동기 작업을 하나의 단위로 묶어 전체 완료 감지
 - `enter()` / `leave()` 쌍으로 수동 카운터 제어
 - `notify(queue:)`: Non-blocking 완료 콜백
 - `wait(timeout:)`: 현재 스레드 블로킹 대기

 **DispatchSemaphore**
 - OS 세마포어 추상화, 동시 접근 스레드 수를 카운터로 제한
 - `wait()`: 카운터 감소, 0이면 블로킹
 - `signal()`: 카운터 증가, 대기 스레드 해제

 **Barrier**
 - Concurrent 큐에서 쓰기 작업을 단독 실행으로 직렬화
 - Reader-Writer Lock 패턴 구현에 활용

 ---
 */

import Foundation

// MARK: - 1. DispatchGroup 기본 사용

print("=== 1. DispatchGroup — 여러 작업 완료 대기 ===")

func fetchUserData(id: Int, completion: @escaping (String) -> Void) {
    DispatchQueue.global().async {
        Thread.sleep(forTimeInterval: Double.random(in: 0.05...0.15))
        completion("User#\(id)")
    }
}

func fetchFeedData(completion: @escaping ([String]) -> Void) {
    DispatchQueue.global().async {
        Thread.sleep(forTimeInterval: Double.random(in: 0.05...0.15))
        completion(["Post1", "Post2", "Post3"])
    }
}

let group = DispatchGroup()
var user: String?
var feed: [String]?
let lock = NSLock()

group.enter()
fetchUserData(id: 42) { result in
    lock.lock(); user = result; lock.unlock()
    print("유저 데이터 도착: \(result)")
    group.leave()
}

group.enter()
fetchFeedData { result in
    lock.lock(); feed = result; lock.unlock()
    print("피드 데이터 도착: \(result)")
    group.leave()
}

// notify: Non-blocking 완료 콜백
group.notify(queue: .main) {
    print("✅ 모든 데이터 로드 완료 | user: \(user!) | feed 수: \(feed!.count)")
}

Thread.sleep(forTimeInterval: 0.3)  // Playground에서 비동기 완료 대기

// MARK: - 2. DispatchGroup + wait (타임아웃 패턴)

print("\n=== 2. DispatchGroup wait + timeout ===")

let timeoutGroup = DispatchGroup()

timeoutGroup.enter()
DispatchQueue.global().async {
    Thread.sleep(forTimeInterval: 0.05)
    print("빠른 작업 완료")
    timeoutGroup.leave()
}

timeoutGroup.enter()
DispatchQueue.global().async {
    Thread.sleep(forTimeInterval: 2.0)  // 느린 작업
    print("느린 작업 완료 (타임아웃 후)")
    timeoutGroup.leave()
}

let result = timeoutGroup.wait(timeout: .now() + 0.2)
switch result {
case .success: print("✅ 모두 완료")
case .timedOut: print("⏰ 타임아웃 — 일부 작업 미완료")
}

// MARK: - 3. DispatchSemaphore — 동시 접근 제한

print("\n=== 3. DispatchSemaphore — 최대 3개 동시 실행 ===")

let semaphore = DispatchSemaphore(value: 3)  // 최대 3개 동시
let semGroup = DispatchGroup()
var runningCount = 0
let countLock = NSLock()
var maxConcurrent = 0

for i in 1...8 {
    DispatchQueue.global().async(group: semGroup) {
        semaphore.wait()  // 슬롯 점유 (3개 초과 시 대기)

        countLock.lock()
        runningCount += 1
        maxConcurrent = max(maxConcurrent, runningCount)
        let current = runningCount
        countLock.unlock()

        print("작업 \(i) 시작 (동시 실행 중: \(current))")
        Thread.sleep(forTimeInterval: 0.05)

        countLock.lock()
        runningCount -= 1
        countLock.unlock()

        semaphore.signal()  // 슬롯 반납
    }
}

semGroup.wait()
print("최대 동시 실행 수: \(maxConcurrent) (제한: 3)")

// MARK: - 4. Semaphore로 비동기 → 동기 변환 (테스트 유틸 패턴)

print("\n=== 4. Semaphore(value:0) — 비동기를 동기처럼 ===")

func asyncOperation(completion: @escaping (Int) -> Void) {
    DispatchQueue.global().async {
        Thread.sleep(forTimeInterval: 0.05)
        completion(42)
    }
}

// Semaphore(value: 0): 초기값 0 → 이벤트 시그널링 패턴
let syncSemaphore = DispatchSemaphore(value: 0)
var asyncResult: Int?

asyncOperation { value in
    asyncResult = value
    syncSemaphore.signal()
}

syncSemaphore.wait()
print("비동기 결과를 동기로 받음: \(asyncResult!)")

// MARK: - 5. Barrier — Reader-Writer Lock 패턴

print("\n=== 5. Barrier — Thread-safe Cache ===")

/// ✅ Barrier로 구현한 Thread-safe 캐시
class ThreadSafeCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private let queue = DispatchQueue(
        label: "com.leeo.cache",
        attributes: .concurrent
    )

    /// 읽기: 동시 허용 (성능 최대화)
    func read(key: Key) -> Value? {
        queue.sync {
            storage[key]
        }
    }

    /// 쓰기: 단독 실행 (안전성 보장)
    func write(key: Key, value: Value) {
        queue.async(flags: .barrier) {
            self.storage[key] = value
        }
    }

    var count: Int {
        queue.sync { storage.count }
    }
}

let cache = ThreadSafeCache<String, Int>()
let barrierGroup = DispatchGroup()

// 동시 쓰기
for i in 0..<10 {
    DispatchQueue.global().async(group: barrierGroup) {
        cache.write(key: "key\(i)", value: i * 10)
    }
}

// 동시 읽기
for i in 0..<10 {
    DispatchQueue.global().async(group: barrierGroup) {
        let _ = cache.read(key: "key\(i)")
    }
}

barrierGroup.wait()
print("ThreadSafeCache 최종 항목 수: \(cache.count)")

// MARK: - 6. Spinlock vs Mutex 개념 비교

print("\n=== 6. NSLock(Mutex) vs OSSpinLock 개념 ===")

// NSLock: 커널 수준 뮤텍스 — 대기 시 스레드를 슬립, CPU 효율적
// OSSpinLock: 스핀락 — 대기 시 CPU 반복 폴링, 짧은 임계구역에 유리 (iOS에서 deprecated)

let mutex = NSLock()
var sharedValue = 0

DispatchQueue.concurrentPerform(iterations: 100) { _ in
    mutex.lock()
    sharedValue += 1
    mutex.unlock()
}

print("NSLock으로 보호된 최종값: \(sharedValue) (기대: 100)")

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] `DispatchGroup`으로 3개 API를 동시에 호출하고 모두 완료 시 TableView 리로드 시뮬레이션
 2. [ ] Semaphore(value: 3)을 value: 1로 바꿔서 직렬 실행과 비교
 3. [ ] Barrier 없이 Concurrent Queue에서 쓰기를 하면 어떤 문제가 생기는지 실험
 4. [ ] ThreadSafeCache를 일반 Dictionary로 교체하고 Thread Sanitizer로 Race Condition 확인

 ## 💬 면접 질문 연습

 Q. DispatchGroup.notify와 wait의 차이는?
 Q. Semaphore와 Mutex의 차이를 설명하세요
 Q. Barrier 플래그가 없으면 Concurrent Queue에서 쓰기가 왜 위험한가요?
 */
