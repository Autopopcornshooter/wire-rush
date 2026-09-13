# Wire Rush — 프로토타입 0.2.1

2026-09-14. 기본 앵커를 16~18m로 올리고 마우스 버튼 유지 시 자동으로 줄을 감도록 변경했습니다. 한국어/영어와 자동/직접 조준 설정을 유지합니다.

## 실행 위치

- 프로젝트: `D:\GameProject\WireSwing\project.godot`
- 실행 파일: `builds/WireRush-0.2.1-Windows/WireRush.exe`
- 배포 ZIP: `builds/WireRush-0.2.1-Windows.zip`
- 저장소: https://github.com/Autopopcornshooter/wire-rush

원본 HellDelivery에는 게임 코드나 문서를 변경하지 않았습니다. 설치된 Godot 실행 파일과 일치하는 공식 export template를 재사용했습니다. 신규 저장소에는 엔진·템플릿·빌드를 포함하지 않습니다.

## 구현 완료

| 영역 | 현재 동작 |
|---|---|
| 기본 플레이 | 메뉴 → 거리 도전/연습 → 재시작/메뉴 |
| 설정·언어 | 메인 메뉴/Esc 일시정지 → 설정, 한국어/영어 즉시 전환·저장, 한글 글꼴 포함 |
| 직접 조준 | 커서로 건물 벽의 임의 지점 선택, 반대 버튼으로 스윙 중 재연결, 연결 지점 고정 |
| 스윙 | 16~18m 높이 앵커, 실제 갈고리 이동 시간, 한 줄 유지, 클릭 유지 중 자동 줄 감기, 관성 해제 |
| 착지 | 수직 충격 판정, 0.6초 넘어짐, 착지 전후 해제 여유 시간 |
| 스케이트 | 속도 보존 슬라이드, 거리 소모, 점프/재연결, 공중 재충전 |
| 특수 장비 | 양측 사출, 방어구, 미래 고층 앵커, 각 3단계 |
| 성장 | 새 거리/아이템 XP, 선택 카드, 정지·재개 처리, XP 이월 |
| 도시 | 6종 패턴, 64m 청크, 앞쪽 생성/뒤쪽 정리, 연결 중 청크 보호, 원점 이동 |
| 표시 | 거리/속도/장비/슬라이드, 다음 앵커, 조작 안내, 결과 요약 |
| 데이터 | 최고 거리 로컬 저장, 별도 설정 파일, 연습과 자동 검증 기록 분리 |
| 배포 | Godot가 없어도 실행하는 Windows x64 EXE, 안내서 포함 ZIP |

## 실행한 검증

Godot **4.7.1.stable.official.a13da4feb**, Windows, NVIDIA GeForce RTX 2070 SUPER / OpenGL 3.3 Compatibility.

- Godot headless editor import: 오류 없이 완료.
- `tests/run.gd`: **43/43 통과**. 높은 앵커, Shift 없이 자동 감기, 해제 시 감기 중단, 거리 중복 방지, 실제 스윙/줄 제약/관성, 착지·슬라이드·점프·재연결, 방어구, 사출, UI 정지, XP 이월, 청크 보호/해제, 원점 이동, 35m/s 충돌.
- `tests/settings_aim.gd`: **36/36 통과**. 직접 조준의 Shift 없는 자동 감기, 설정 저장·복원, 언어·버튼·정지 유지, 카메라 광선→서로 다른 벽과 높이 선택→실제 스윙, 재연결, 사거리·가림 검사, 임시 앵커 정리, 원점 이동·청크 보호, 한 프레임 내 누름/해제, 자동 모드 복귀.
- `tests/traversal.gd`: 자동 입력 **30초 / 920.38m / 115회 연결 / 자동 복구 0회**. 시작 위치 이외의 순간이동 없이 장애물 없는 Practice 청크를 연결. `--fixed-fps 60`으로 시뮬레이션 시간을 가속 실행.
- 배포 EXE의 한국어 메뉴, 한국어/영어 설정, 자동/직접 조준 플레이 화면을 캡처·검토. 다섯 프로세스 모두 **exit 0**, stderr 비어 있음. 플레이 캡처는 스크립트 입력을 사용한 렌더링 확인입니다.
- 배포 EXE SHA256: `CAE58C43C8031ED384AC6CA1D6FC616C42F373C3CEAEB4675BFB9FA0F6365C3B`.

자동 검사는 재현 가능한 기계적 동작 검사입니다. 여러 검사는 초기 위치와 속도를 지정하는 fixture를 사용합니다. 사용자의 자유 플레이, 체감 재미, 다른 GPU/PC에서의 실행까지 검증했다는 의미는 아닙니다.

메뉴와 플레이 캡처: `docs/screenshots/menu.png`, `docs/screenshots/gameplay.png`, `docs/screenshots/settings-ko.png`, `docs/screenshots/settings-en.png`. 로컬 상세 로그는 `validation/`에 생성되며 Git에서 제외합니다. 이전 `v0.1.0`, `v0.2.0` 빌드는 로컬에서 그대로 보존합니다.

## 남은 작업

1. [**핵심 체감 검증 — #1**](https://github.com/Autopopcornshooter/wire-rush/issues/1): 사람의 입력으로 저공 스윙→슬라이드→재연결 5회 연속. 해제 0.15초·충격 4m/s·앵커 선택과 카메라 수치 조정.
2. [**장애물 공정성 — #2**](https://github.com/Autopopcornshooter/wire-rush/issues/2): 6종 청크 전체와 연결부를 기본 장비로 검사. 진입 속도별 보장 경로, 예고 가시성, 상부 차단물 난도, 구덩이 도입 여부.
3. [**표현과 접근성 — #3**](https://github.com/Autopopcornshooter/wire-rush/issues/3): 한국어·조준 방식 설정은 완료. 음량, 선택 장비 전체 결과 표시, 조작 튜토리얼, 아트·애니메이션 교체는 후속 범위.

이 문서의 완료 항목과 후속 이슈를 기준으로 다음 변경을 관리합니다. 원문에 있는 기획 요소 전체가 완성됐다고 주장하지 않습니다.
