/*:
 # Unit 01 — Thread vs Process
 ## 동시성과 병렬 프로그래밍을 위한 운영체제

 ---
 ### 🧠 핵심 개념 정리

 **Process (프로세스)**
 - OS가 프로그램을 실행하는 독립 단위
 - 고유한 메모리 공간: Code / Data / Heap / Stack 영역 보유
 - iOS에서 앱 하나 = 프로세스 하나 (App Sandbox)
 - 프로세스 간 통신은 IPC(Inter-Process Communication) 필요

 **Thread (스레드)**
 - 프로세스 내에서 실행되는 경량 실행 단위
 - Code·Data·Heap 공유, Stack만 개별 소유
 - 생성 비용: Thread << Process
 - iOS: 메인 스레드(UI) + 백그라운드 스레드 구조

 **Context Switching**
 - OS 스케줄러가 실행 단위를 교체하는 과정
 - Thread 전환 비용 << Process 전환 비용 (메모리 공간 교체 불필요)

 **Race Condition**
 - 두 스레드가 공유 자원에 동시 접근 시 결과가 실행 순서에 따라 달라지는 버그
 - 비결정적(non-deterministic) — 재현이 어려워 디버깅이 까다로움

 ---
 */

import Foundation

// MARK: - 1. 현재 스레드 정보 확인

print("=== 현재 실행 환경 ===")
print("현재 스레드: \(Thread.current)")
print("메인 스레드 여부: \(Thread.isMainThread)")
print("프로세스 ID: \(ProcessInfo.processInfo.processIdentifier)")
print("프로세스 이름: \(ProcessInfo.processInfo.processName)")
print("CPU 코어 수: \(ProcessInfo.processInfo.processorCount)")
print("활성 CPU 수: \(ProcessInfo.processInfo.activeProcessorCount)")

// MARK: - 2. Thread 직접 생성 (iOS에서는 거의 사용 안 함 — 학습 목적)

print("\n=== Thread 직접 생성 ===")

let thread1 = Thread {
    print("Thread1 | isMain: \(Thread.isMainThread) | \(Thread.current)")
}
thread1.name = "com.leeo.thread1"
thread1.qualityOfService = .userInitiated
thread1.start()

// MARK: - 3. Race Condition 시연

print("\n=== Race Condition 시연 ===")

/// ❌ 안전하지 않은 카운터 (Race Condition 발생 가능)
class UnsafeCounter {
    var count = 0

    func increment() {
        // 이 3단계 사이에 다른 스레드가 끼어들 수 있음
        // 1. count 읽기
        // 2. +1 계산
        // 3. count 쓰기
        count += 1
    }
}

let unsafeCounter = UnsafeCounter()
let group = DispatchGroup()

// 1000번 동시 증가 시도
for _ in 0..<1000 {
    DispatchQueue.global().async(group: group) {
        unsafeCounter.increment()
    }
}

group.wait()
// 결과가 1000이 아닐 수 있음! Race Condition 때문
print("❌ UnsafeCounter 결과: \(unsafeCounter.count) (기대값: 1000)")

// MARK: - 4. Thread-safe 카운터 (Serial Queue 활용)

/// ✅ Serial Queue로 보호된 Thread-safe 카운터
class SafeCounter {
    private var count = 0
    private let queue = DispatchQueue(label: "com.leeo.safeCounter")

    func increment() {
        queue.sync {
            count += 1  // 직렬 큐가 한 번에 하나만 실행 보장
        }
    }

    var value: Int {
        queue.sync { count }
    }
}

let safeCounter = SafeCounter()
let group2 = DispatchGroup()

for _ in 0..<1000 {
    DispatchQueue.global().async(group: group2) {
        safeCounter.increment()
    }
}

group2.wait()
print("✅ SafeCounter 결과: \(safeCounter.value) (기대값: 1000)")

// MARK: - 5. Stack vs Heap 메모리 영역 체감

print("\n=== Value Type(Stack) vs Reference Type(Heap) ===")

struct PointValue {  // Stack에 저장
    var x: Int
    var y: Int
}

class PointRef {    // Heap에 저장
    var x: Int
    var y: Int
    init(x: Int, y: Int) { self.x = x; self.y = y }
}

var p1 = PointValue(x: 0, y: 0)
var p2 = p1         // 복사 (Stack → Stack, 독립)
p2.x = 99
print("Value Type 복사 후 p1.x: \(p1.x), p2.x: \(p2.x)")  // 0, 99 — 독립

let r1 = PointRef(x: 0, y: 0)
let r2 = r1         // 참조 복사 (같은 Heap 객체를 가리킴)
r2.x = 99
print("Reference Type 복사 후 r1.x: \(r1.x), r2.x: \(r2.x)")  // 99, 99 — 공유!

// MARK: - 6. 메인 스레드 vs 백그라운드 스레드

print("\n=== 메인 스레드 vs 백그라운드 스레드 ===")

let semaphore = DispatchSemaphore(value: 0)

DispatchQueue.global(qos: .userInitiated).async {
    print("백그라운드 | isMain: \(Thread.isMainThread)")

    DispatchQueue.main.async {
        print("메인 복귀 | isMain: \(Thread.isMainThread)")
        semaphore.signal()
    }
}

semaphore.wait()

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] `UnsafeCounter` 결과가 1000이 아닌 경우를 여러 번 실행하여 확인
 2. [ ] `SafeCounter`의 queue를 `concurrent`로 바꾸면 어떻게 되는지 실험
 3. [ ] Value Type과 Reference Type이 스레드 안전성에 미치는 차이를 설명

 ## 💬 면접 질문 연습

 Q. iOS에서 Thread와 Process의 차이는?
 Q. 메인 스레드가 UI 전용인 이유는?
 Q. Race Condition이란 무엇이고 어떻게 예방하는가?
 */
