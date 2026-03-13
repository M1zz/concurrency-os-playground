/*:
 # Unit 04 — Operation / OperationQueue
 ## 취소 · 의존성 · 우선순위 — GCD를 넘어서

 ---
 ### 🧠 핵심 개념 정리

 **Operation 상태 머신**
 ```
 pending → ready → executing → finished
                 ↘ cancelled
 ```

 **GCD vs Operation 선택 기준**
 - GCD: 단순 일회성 비동기 작업
 - Operation: 취소·의존성·재사용이 필요한 복잡한 파이프라인

 **핵심 API**
 - `cancel()`: 취소 신호 (협력적 취소 — isCancelled 확인 필요)
 - `addDependency(_:)`: 실행 순서 의존성 (DAG 구성)
 - `maxConcurrentOperationCount`: 동시 실행 상한

 ---
 */

import Foundation

// MARK: - 1. BlockOperation 기본

print("=== 1. BlockOperation 기본 ===")

let op1 = BlockOperation {
    print("op1 실행 | isMain: \(Thread.isMainThread)")
}

let op2 = BlockOperation {
    print("op2 실행")
}

// BlockOperation에 여러 블록 추가 가능 (동시 실행됨)
let multiOp = BlockOperation()
multiOp.addExecutionBlock { print("multiOp 블록 A") }
multiOp.addExecutionBlock { print("multiOp 블록 B") }
multiOp.addExecutionBlock { print("multiOp 블록 C") }

let queue = OperationQueue()
queue.addOperations([op1, op2, multiOp], waitUntilFinished: true)

// MARK: - 2. 커스텀 Operation 서브클래스

print("\n=== 2. 커스텀 Operation — 이미지 처리 시뮬레이션 ===")

class DownloadOperation: Operation {
    let url: String
    var downloadedData: String?

    init(url: String) {
        self.url = url
        super.init()
        self.name = "Download:\(url)"
    }

    override func main() {
        guard !isCancelled else {
            print("❌ \(name!) 취소됨")
            return
        }
        print("⬇️  다운로드 시작: \(url)")
        Thread.sleep(forTimeInterval: 0.1)

        guard !isCancelled else { return }
        downloadedData = "DATA[\(url)]"
        print("✅ 다운로드 완료: \(url)")
    }
}

class ResizeOperation: Operation {
    var inputData: String?
    var outputData: String?

    override var name: String? {
        get { "Resize" }
        set { }
    }

    override func main() {
        guard !isCancelled, let input = inputData else { return }
        print("🔧 리사이즈 중: \(input)")
        Thread.sleep(forTimeInterval: 0.05)
        outputData = "\(input)_resized"
        print("✅ 리사이즈 완료: \(outputData!)")
    }
}

class FilterOperation: Operation {
    var inputData: String?
    var outputData: String?

    override func main() {
        guard !isCancelled, let input = inputData else { return }
        print("🎨 필터 적용 중: \(input)")
        Thread.sleep(forTimeInterval: 0.05)
        outputData = "\(input)_filtered"
        print("✅ 필터 완료: \(outputData!)")
    }
}

// MARK: - 3. 의존성 체인 (Pipeline)

print("\n=== 3. 의존성 체인 — 다운로드 → 리사이즈 → 필터 ===")

let downloadOp = DownloadOperation(url: "https://example.com/image.jpg")
let resizeOp = ResizeOperation()
let filterOp = FilterOperation()

// 의존성 설정: 다운로드 → 리사이즈 → 필터
resizeOp.addDependency(downloadOp)
filterOp.addDependency(resizeOp)

// 완료 핸들러로 데이터 전달
downloadOp.completionBlock = {
    resizeOp.inputData = downloadOp.downloadedData
}
resizeOp.completionBlock = {
    filterOp.inputData = resizeOp.outputData
}

let pipeline = OperationQueue()
pipeline.maxConcurrentOperationCount = 4
pipeline.addOperations([downloadOp, resizeOp, filterOp], waitUntilFinished: true)

print("\n최종 결과: \(filterOp.outputData ?? "없음")")

// MARK: - 4. 취소 패턴

print("\n=== 4. 협력적 취소 (Cooperative Cancellation) ===")

class CancellableOperation: Operation {
    override func main() {
        for step in 1...10 {
            guard !isCancelled else {
                print("❌ 취소됨 (step \(step)에서)")
                return
            }
            print("  처리 중... step \(step)")
            Thread.sleep(forTimeInterval: 0.02)
        }
        print("✅ 모든 step 완료")
    }
}

let cancelQueue = OperationQueue()
let longOp = CancellableOperation()
longOp.name = "LongOperation"

cancelQueue.addOperation(longOp)
Thread.sleep(forTimeInterval: 0.05)  // 조금 실행 후

longOp.cancel()
cancelQueue.waitUntilAllOperationsAreFinished()

// MARK: - 5. maxConcurrentOperationCount

print("\n=== 5. maxConcurrentOperationCount 제어 ===")

let controlled = OperationQueue()
controlled.maxConcurrentOperationCount = 2  // 동시 최대 2개

let concurrencyLock = NSLock()
var peakConcurrent = 0
var currentRunning = 0

for i in 1...6 {
    let op = BlockOperation {
        concurrencyLock.lock()
        currentRunning += 1
        peakConcurrent = max(peakConcurrent, currentRunning)
        concurrencyLock.unlock()

        Thread.sleep(forTimeInterval: 0.05)

        concurrencyLock.lock()
        currentRunning -= 1
        concurrencyLock.unlock()
    }
    controlled.addOperation(op)
}

controlled.waitUntilAllOperationsAreFinished()
print("최대 동시 실행: \(peakConcurrent) (제한: 2)")

// MARK: - 6. KVO로 Operation 상태 관찰

print("\n=== 6. Operation 상태 관찰 ===")

let observedOp = BlockOperation {
    Thread.sleep(forTimeInterval: 0.05)
}

// KVO 관찰 (isFinished)
let obs = observedOp.observe(\.isFinished, options: [.new]) { _, change in
    if change.newValue == true {
        print("✅ Operation 완료 감지 (KVO)")
    }
}

observedOp.completionBlock = {
    print("✅ Operation completionBlock 호출")
}

let obsQueue = OperationQueue()
obsQueue.addOperations([observedOp], waitUntilFinished: true)
obs.invalidate()

/*:
 ---
 ## ✅ 실습 체크리스트

 1. [ ] 다운로드 → 리사이즈 → 필터 파이프라인에서 resizeOp를 취소하면 filterOp도 실행 안 되는지 확인
 2. [ ] `maxConcurrentOperationCount = 1`로 바꿔 직렬 큐처럼 동작하는지 확인
 3. [ ] 검색어 변경 시 이전 Operation을 취소하는 SearchController 시뮬레이션 구현

 ## 💬 면접 질문 연습

 Q. GCD와 OperationQueue의 가장 큰 차이는 무엇인가요?
 Q. cancel()을 호출해도 작업이 즉시 멈추지 않는 이유는?
 Q. OperationQueue에서 의존성 그래프에 순환(cycle)이 생기면 어떻게 되나요?
 */
