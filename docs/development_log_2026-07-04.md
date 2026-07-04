# Stack Over Snow 개발 내역서 - 2026-07-04

## 개요

`Stack Over Snow`는 눈 큐브를 쌓아 한 줄을 완성하면 얼음줄로 고정되고, 눈이 녹으면서 얼음줄이 아래로 떨어지는 모바일 중심 퍼즐 게임 프로토타입이다. 이번 개발에서는 초기 Flutter 프로토타입 구성부터 모바일 UI, 커스텀 픽셀 아트 버튼, 광고 영역, 개인 기록 저장, 오디오, 베이스라인 로직까지 구현했다.

## 오늘 커밋 흐름

- `3bdaad9 Initial Stack Over Snow prototype`: Flutter 기반 첫 플레이 가능 프로토타입 구현. 보드, 눈 큐브, 얼음줄 생성, 기본 조작을 구성했다.
- `d388c28 Refine gameplay UI controls`: 조작 버튼 배치와 게임 화면 구성을 모바일 플레이에 맞게 조정했다.
- `88e7729 Simplify mobile gameplay layout`: 모바일 화면에서 `NEXT` 영역을 제거하고 게임 영역과 버튼 영역을 단순화했다.
- `aa502e5 Use custom button assets`: `assets/ui`의 버튼 이미지를 적용했다.
- `b027971 Refine mobile controls and ad spacing`: 상단 광고 여백, 하단 버튼 간격, 설정 버튼 위치를 정리했다.
- `e5f7a22 Simplify title and pause controls`: 시작 화면과 일시정지 흐름을 단순화했다.
- `3d8ecb5 Adjust control button styling`: 조작 버튼 크기와 스타일을 조정했다.
- `9a8f7bb Use menu button assets`: 메뉴 모달용 버튼 이미지를 적용했다.
- `b81ecbf Refine pause menu layout`: 메뉴 모달 내 버튼 배치를 이미지에 맞춰 다듬었다.
- `8305800 Use relative pause menu layout`: 모달 크기/위치를 화면 비율 기반으로 계산하게 변경해 직접 수치 튜닝이 쉽도록 했다.
- `14930e6 Split pause menu button heights`: 메뉴 버튼별 높이 조절값을 분리했다.
- `6e629ce Split pause menu button positions`: 메뉴 버튼별 위치 조절값을 분리했다.

## 이번 미커밋 작업 내용

### 오디오

- `assets/bgm/moonlight.ogg`를 배경 음악으로 추가했다.
- `assets/audio/click.ogg`, `assets/audio/footstep_snow.ogg`, `assets/audio/ice-freezing.mp3`를 각각 클릭, 눈 큐브 착지, 얼음줄 생성 효과음으로 연결했다.
- `audioplayers` 기반 네이티브 오디오 컨트롤러와, 웹 전용 `dart:html` 오디오 컨트롤러를 분리했다.
- BGM 상태 정책을 적용했다.
  - 게임 시작/재시작: 처음부터 재생
  - 일시정지 메뉴 열기: 일시정지
  - 메뉴 닫기: 멈춘 지점부터 재개
  - 홈으로 이동: 정지 및 처음 위치로 초기화

### 라이선스

- Musopen / Wikimedia Commons public domain 음악 고지를 `NOTICE.md`에 추가했다.
- 배경 음악 파일의 public domain 상태와 Musopen attribution 요청을 문서화했다.

### 게임 로직

- 기준선 로직을 변경했다.
- 기준선은 단순히 가장 위에 있는 얼음줄이 아니라, `아래에 눈이 없는 하단 고정 얼음 스택 중 가장 위의 얼음줄`로 판정한다.
- 아래에 눈이 있는 얼음줄은 떠 있는 상태로 유지되고, 눈이 녹아서 아래가 비면 기존 베이스라인까지 떨어진 뒤 기준선 후보가 된다.
- 하단에 고정된 얼음 스택은 내부적으로 2줄만 유지한다. 그 아래의 오래된 얼음줄은 기록에는 남지만 보드 공간을 계속 차지하지 않도록 정리한다.

### UI/UX

- 게임 이름을 `Stack Over Snow`로 정리했다.
- 점수 기준을 `얼음줄 개수`로 단순화했다.
- 시작 화면의 불필요한 설정/기록 표시를 제거했다.
- 모바일 기준으로 게임 영역, 설정 버튼, 하단 조작 버튼의 크기/위치 조절 상수를 코드 상단부 위젯 내부에 분리해 두었다.
- 메뉴 모달은 이미지 기반 모달을 유지하고, 닫기/재시작/홈 버튼만 남겼다.

## 트러블슈팅

### 1. 웹에서 `audioplayers` MissingPluginException 발생

문제:

웹 빌드 실행 중 `MissingPluginException(No implementation found for method listen on channel xyz.luan/audioplayers.global/events)` 오류가 발생했다.

원인:

Flutter Web에서 `audioplayers_web` 플러그인 채널 초기화가 현재 실행 환경과 맞지 않아 이벤트 채널이 등록되지 않았다.

해결:

- `audio_controller.dart`를 conditional export 구조로 변경했다.
- Android/Windows 등 IO 플랫폼은 `audioplayers`를 사용한다.
- Web은 `dart:html`의 `AudioElement`를 직접 사용한다.
- 웹 빌드 결과 JS에서 문제가 된 `xyz.luan/audioplayers.global/events` 문자열이 사라진 것을 확인했다.

### 2. 베이스라인을 1.5줄로 보이게 하려다 반칸 틈 발생

문제:

하단 베이스 얼음줄을 1.5줄처럼 보이게 하려고 그림만 0.5칸 아래로 내렸더니, 기존 블록과 베이스 사이에 0.5칸 틈이 생겼다.

해결:

- 베이스 표시를 2줄 전체 표시로 변경했다.
- `baseIceVisualDropRows` 값을 `0`으로 두어 시각적 반칸 오프셋을 제거했다.

### 3. 모바일 버튼 비율과 실제 이미지 크기 불일치

문제:

버튼 이미지 자체의 여백과 비율이 서로 달라 같은 `width/height`를 줘도 화면상 크기가 다르게 보였다.

해결:

- `ImageButton`에 `scaleX`, `scaleY`를 추가했다.
- 좌측 이동 버튼 등 일부 버튼은 개별 스케일 보정값으로 맞출 수 있게 했다.
- 하단 조작 버튼과 설정 버튼의 위치/크기 상수를 분리해 직접 튜닝 가능하게 했다.

### 4. 메뉴 모달 버튼 튜닝 반복

문제:

모달 이미지 안의 실제 버튼 자리와 Flutter 위젯 좌표가 맞지 않아 버튼이 이미지 밖으로 나가거나 너무 낮게 보였다.

해결:

- `PauseMenu`에서 모달 너비/높이 기준의 상대 좌표를 사용했다.
- 닫기, 재시작, 홈 버튼의 너비/높이/위치를 각각 독립 조절 가능하게 분리했다.

## 검증 내역

- `dart format` 실행
- `flutter analyze` 통과
- `flutter test` 통과
- `flutter build web` 통과
- Android 빌드는 별도 실행 결과를 커밋 전 확인한다.

## 다음 작업 후보

- 정식 릴리즈용 Android signing 설정 추가
- 실제 기기에서 광고 노출과 오디오 autoplay 정책 확인
- 게임오버/난이도 조절 규칙 추가
- 앱 아이콘과 스플래시 화면을 로고 에셋으로 교체
- 메뉴 내 음악/효과음 on/off 옵션 추가
