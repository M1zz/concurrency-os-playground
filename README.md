# 동시성과 병렬 프로그래밍을 위한 운영체제
### Operating Systems for Concurrency & Parallel Programming

> iOS 개발자를 위한 동시성 완전 정복 — GCD부터 Swift Concurrency, Actor, Combine까지

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2015%2B%20%7C%20macOS%2012%2B-blue?logo=apple)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 📖 강의 소개

컴퓨터공학 운영체제(OS) 및 병렬프로그래밍 이론을 **iOS/Swift 실전 코드와 연결**하여 학습하는 집중 과정입니다.  
단순 API 암기를 넘어, *'왜 이 API가 존재하는가'* 를 OS 원리부터 이해하는 것을 목표로 합니다.

- 🎯 **대상**: iOS 개발자 또는 iOS 개발 지망생 (Swift 기초 이상)
- 📊 **수준**: 중급 (Intermediate)
- 🏢 **제작**: 개발자리 (Apple Developer Academy @ POSTECH)

---

## 🗂️ 커리큘럼

| Unit | 주제 | 핵심 API |
|------|------|----------|
| [Unit 01](Playgrounds/Unit01_ThreadVsProcess.playground) | Thread vs Process | `Thread`, `ProcessInfo` |
| [Unit 02](Playgrounds/Unit02_GCDBasics.playground) | GCD 기초 | `DispatchQueue`, sync/async, QoS |
| [Unit 03](Playgrounds/Unit03_GCDAdvanced.playground) | GCD 심화 | `DispatchGroup`, `DispatchSemaphore`, Barrier |
| [Unit 04](Playgrounds/Unit04_OperationQueue.playground) | Operation / OperationQueue | `Operation`, `OperationQueue`, 의존성 |
| [Unit 05](Playgrounds/Unit05_AsyncAwaitBasics.playground) | async/await 기초 | `async`, `await`, `Continuation` |
| [Unit 06](Playgrounds/Unit06_AsyncAwaitAdvanced.playground) | async/await 심화 | `Task`, `TaskGroup`, `async let` |
| [Unit 07](Playgrounds/Unit07_Actor.playground) | Actor | `actor`, `nonisolated`, Reentrancy |
| [Unit 08](Playgrounds/Unit08_Sendable.playground) | Sendable | `Sendable`, `@unchecked Sendable`, `@Sendable` |
| [Unit 09](Playgrounds/Unit09_MainActor.playground) | MainActor | `@MainActor`, `MainActor.run` |
| [Unit 10](Playgrounds/Unit10_CombineBasics.playground) | Combine 기초 | `Publisher`, `Subject`, `Operator` |
| [Unit 11](Playgrounds/Unit11_CombineAdvanced.playground) | Combine 심화 | 에러 처리, `Scheduler`, `AnyCancellable` |

---

## 🚀 시작하기

### 요구 사항

- Xcode 15.0+
- Swift 5.9+
- macOS 14.0+ (Playground 실행 환경)

### 실행 방법

```bash
# 레포지토리 클론
git clone https://github.com/your-username/concurrency-os-playground.git
cd concurrency-os-playground

# Xcode에서 특정 Unit 열기
open Playgrounds/Unit01_ThreadVsProcess.playground
```

또는 Finder에서 `.playground` 파일을 더블클릭하면 Xcode Playground으로 바로 열립니다.

---

## 📚 각 Playground 구성

모든 Playground는 동일한 구조를 따릅니다:

```
Unit0X_TopicName.playground/
├── Contents.swift          # 학습 내용 + 실습 코드
└── contents.xcplayground   # Xcode 메타데이터
```

**Contents.swift 내부 구조**:
```
/*: 이론 설명 (Markdown 렌더링) */

// MARK: - 1. 기본 개념 코드
// MARK: - 2. 심화 패턴
// MARK: - 3. 실전 예제
// ...

/*: 실습 체크리스트 + 면접 질문 */
```

---

## 🎯 학습 목표

- [ ] 스레드/프로세스 OS 원리를 iOS 런타임 관점에서 설명할 수 있다
- [ ] GCD API를 올바르게 선택하고 Deadlock·Race Condition을 예방할 수 있다
- [ ] Swift Concurrency(`async/await`, `Actor`)로 구조적 동시성 코드를 작성할 수 있다
- [ ] `Sendable` 프로토콜로 타입 안전성을 컴파일 타임에 보장할 수 있다
- [ ] Combine 스트림으로 비동기 이벤트를 선언적으로 처리할 수 있다
- [ ] iOS 면접에서 동시성 관련 질문에 자신 있게 답변할 수 있다

---

## 🗺️ 기술 선택 가이드

| 상황 | 권장 기술 |
|------|-----------|
| 단순 백그라운드 작업 + UI 업데이트 | `async/await` + `@MainActor` |
| 여러 독립 API 동시 호출 (정적 개수) | `async let` |
| 동적 개수 병렬 작업 | `TaskGroup` |
| 공유 가변 상태 보호 | `actor` |
| 레거시 콜백 API 래핑 | `withCheckedContinuation` |
| 복잡한 작업 파이프라인 (취소·의존성) | `OperationQueue` |
| 선언적 이벤트 스트림 (검색, 폼) | `Combine` |
| 단순 일회성 비동기 (iOS 구버전 포함) | `GCD (DispatchQueue)` |

---

## 📝 라이선스

MIT License — 자유롭게 사용, 수정, 배포 가능합니다.

---

<div align="center">
  <strong>개발자리</strong> · Apple Developer Academy @ POSTECH<br>
  <a href="https://github.com/your-username">GitHub</a> · 
  <a href="https://youtube.com/@개발자리">YouTube</a>
</div>
