/*:
 # Unit 02 — GCD 기초
 ## DispatchQueue · sync vs async · main vs global · QoS

 ---
 ### 🧠 핵심 개념 정리

 **GCD (Grand Central Dispatch)**
 - Apple의 스레드 풀 기반 동시성 프레임워크
 - 개발자: 큐에 작업 제출만 / OS: 스레드 생성·관리 담당
 - POSIX Thread(pThread)를 추상화한 고수준 API

 **DispatchQueue 종류**
 - `DispatchQueue.main`: 메인 스레드 전용 직렬 큐
 - `DispatchQueue.global(qos:)`: 시스템 전역 동시 큐
 - `DispatchQueue(label:)`: 커스텀 직렬 큐
 - `DispatchQueue(label:, attributes: .concurrent)`: 커스텀 동시 큐

 **sync vs async**
 - `async`: 작업 제출 후 즉시 반환 → Non-blocking
 - `sync`: 작업 완료까지 현재 스레드 블로킹 → Blocking

 **QoS (Quality of Service)**
 - userInteractive > userInitiated > default > utility > background
 ---
 */

import Foundation

// MARK: - 1. async vs sync 기본 동작 비교

print("=== 1. async (Non-blocking) ===")

let queue = DispatchQueue(label: "com.leeo.demo")

print("시작")
queue.async {
    Thread.sleep(forTimeInterval: 0.1)
    print("async 작업 완료")  // 나중에 출력됨
}
print("async 호출 후 즉시 다음 라인")  // 먼저 출력됨

Thread.sleep(forTimeInterval: 0.2)  // async 완료 대기

print("\n=== 2. sync (Blocking) ===")

print("시작")
queue.sync {
    Thread.sleep(forTimeInterval: 0.1)
    print("sync 작업 완료")  // 먼저 출력됨
}
print("sync 호출 후 — 작업 완료 후에만 도달")  // 나중에 출력됨

// MARK: - 2. Serial vs Concurrent Queue 실행 순서 비교

print("\n=== 3. Serial Queue: 순서 보장 ===")

let serialQueue = DispatchQueue(label: "com.leeo.serial")
let sem1 = DispatchSemaphore(value: 0)
var serialOrder: [Int] = []

for i in 1...5 {
    serialQueue.async {
        Thread.sleep(forTimeInterval: Double.random(in: 0.01...0.05))
        serialOrder.append(i)
        if i == 5 { sem1.signal() }
    }
}
sem1.wait()
print("Serial 완료 순서: \(serialOrder)")  // 항상 [1,2,3,4,5]

print("\n=== 4. Concurrent Queue: 완료 순서 비보장 ===")

let concurrentQueue = DispatchQueue(label: "com.leeo.concurrent", attributes: .concurrent)
let sem2 = DispatchSemaphore(value: 0)
var concurrentOrder: [Int] = []
let lock = NSLock()
var completedCount = 0

for i in 1...5 {
    concurrentQueue.async {
        Thread.sleep(forTimeInterval: Double.random(in: 0.01...0.05))
        lock.lock()
        concurrentOrder.append(i)
        completedCount += 1
        let done = completedCount == 5
        lock.unlock()
        if done { sem2.signal() }
    }
}
sem2.wait()
print("Concurrent 완료 순서: \(concurrentOrder)")  // 매번 다름

// MARK: - 3. QoS 레벨 비교

print("\n=== 5. QoS 우선순위 비교 ===")

let qosGroup = DispatchGroup()
var qosResults: [String] = []
let qosLock = NSLock()

let qosList: [(DispatchQoS.QoSClass, String)] = [
    (.background, "background"),
    (.utility, "utility"),
    (.default, "default"),
    (.userInitiated, "userInitiated"),
    (.userInteractive, "userInteractive"),
]

for (qos, name) in qosList {
    DispatchQueue.global(qos: qos).async(group: qosGroup) {
        qosLock.lock()
        qosResults.append(name)
        qosLock.unlock()
    }
}

qosGroup.wait()
print("실행 완료 순서 (높은 QoS가 먼저): \(qosResults)")

// MARK: - 4. 데드락 패턴 이해 (⚠️ 주석 처리 — 실행 시 앱 크래시)

print("\n=== 6. 데드락 패턴 (주석 해제 금지!) ===")

/*
 // ❌ 데드락 패턴 1: main.sync를 메인 스레드에서 호출
 DispatchQueue.main.sync {
     print("이 코드는 절대 실행 안 됨 — Deadlock!")
 }

 // ❌ 데드락 패턴 2: Serial Queue 안에서 같은 큐로 sync
 let serial = DispatchQueue(label: "com.leeo.deadlock")
 serial.async {
     serial.sync {  // 자기 자신을 기다림 → Deadlock!
         print("절대 실행 안 됨")
     }
 }
 */

print("데드락 패턴: 위 주석 코드 참고 (절대 실행 금지)")

// MARK: - 5. 올바른 패턴: 백그라운드 작업 후 메인 업데이트

print("\n=== 7. 백그라운드 → 메인 스레드 올바른 패턴 ===")

func simulateNetworkFetch(completion: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        // 백그라운드에서 무거운 작업
        Thread.sleep(forTimeInterval: 0.1)
        let result = "서버 응답 데이터"

        // 메인 스레드에서 UI 업데이트
        DispatchQueue.main.async {
            print("isMain: \(Thread.isMainThread) → UI 업데이트: \(result)")
            completion(result)
        }
    }
}

let sem3 = DispatchSemaphore(value: 0)
simulateNetworkFetch { result in
    print("최종 결과: \(result)")
    sem3.signal()
}
sem3.wait()

// MARK: - 6. 커스텀 DispatchQueue 직접 만들기

print("\n=== 8. 커스텀 큐 생성 ===")

// 직렬 큐 (공유 자원 보호)
let imageProcessingQueue = DispatchQueue(
    label: "com.leeo.imageProcessing",
    qos: .userInitiated
)

// 동시 큐 (읽기 최적화 — Unit03 Barrier와 함께 사용)
let cacheReadQueue = DispatchQueue(
    label: "com.leeo.cacheRead",
    qos: .utility,
    attributes: .concurrent
)

print("직렬 큐 레이블: \(imageProcessingQueue.label)")
print("동시 큐 레이블: \(cacheReadQueue.label)")

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] async와 sync의 출력 순서 차이를 직접 확인
 2. [ ] Serial Queue를 concurrent로 바꾸면 순서가 어떻게 달라지는지 실험
 3. [ ] QoS를 모두 같은 레벨로 맞추면 완료 순서가 어떻게 되는지 확인
 4. [ ] 데드락 주석 코드를 Playground 아래 새 파일에서 테스트 (메인 스레드 아님)

 ## 💬 면접 질문 연습

 Q. sync와 async의 차이를 설명하고 각각 언제 쓰나요?
 Q. Serial Queue가 Thread-safe를 보장하는 원리는?
 Q. QoS가 높다고 항상 먼저 실행되나요?
 */
