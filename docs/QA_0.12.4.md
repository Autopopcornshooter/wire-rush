# Wire Rush — City Vertical Slice QA / 0.12.4

2026-09-22 · Godot 4.7.1.stable.official.a13da4feb · Windows · OpenGL Compatibility · RTX 2070 SUPER · 1280×720.

**판정:** 재현된 런타임 버그 5종을 안정화했다. 기본 조작과 보스 A/B/C 렌더링·상태 전이·휴식 구간을 확인했다. City Slice는 추가 플레이테스트가 가능한 상태이지만, **무보정 보스 클리어·전체 조합의 공정성·C 가독성을 최종 승인한 결과는 아니다.** 새 콘텐츠나 신규 HUD는 추가하지 않았다.

검증 방법: 전체 headless suite, 실제 창의 Windows 키/마우스 조작, Godot OpenGL 화면 캡처, 위치 고정 probe, 실제 Main 물리 루프를 사용하는 자동 조작/보조 주행을 함께 사용했다. probe에서 지정한 위치·보호와 정상 입력을 구분한다. 임시 실행 스크립트는 작업 후 제거하고, 회귀 검사와 보고서·로그·캡처를 남긴다. `--test`로 개인 기록 파일 쓰기를 막았다.

## [REPOSITORY]

- 시작 branch/HEAD: `main` / `580f41913f19fd03db5de3d60662e5332984fafd`.
- 시작 version: `0.12.3`; 시작 working tree: clean. 안정화 빌드: `0.12.4`.
- 종료 변경은 working tree에만 보관한다. commit/push 없음.
- Player Progression (`rules/rider/main`), 순수 World Progression (`difficulty_director`), 상태를 가진 Boss (`city_boss`) 분리를 유지했다.
- `rules`, `rider`, `main`, `city`, `difficulty_director`, `city_boss`, `character_visual`, `hud` 및 관련 tests를 확인했다. README/진행 문서의 과거 수치보다 실제 코드를 기준으로 했다.

## [BASELINE TEST]

수정 전 `tools/Validate.ps1` 전부 통과. import 포함, 명명된 검사 **803개**와 traversal 별도.

| Suite | Baseline | 안정화 회귀 포함 |
|---|---:|---:|
| run | 99 | 105 |
| upgrades | 94 | 94 |
| difficulty | 266 | 266 |
| city_boss | 115 | 136 |
| settings_aim | 41 | 41 |
| range_obstacle | 31 | 31 |
| jump_abilities | 27 | 27 |
| comfort | 37 | 37 |
| character_animation | 93 | 93 |
| 합계 | 803 | 830 |

Baseline traversal: 실제 물리 자동 조작 30초, **975.79m / 82회 연결 / 복구 0 / 공중 ground pose 위반 0**. 신규 보스 회귀는 수정 전 14개 실패, 신규 스케이트 회귀는 수정 전 6개 실패를 확인했다. 검사 함수만 호출해 통과시킨 것이 아니라 Main 원점 이동, 실제 생성 청크/이동 차량, 실제 물리 착지를 추가했다.

최종 전체 검증은 **830/830 + traversal 통과**, import·export 오류 없음, 빌드 도구 exit 0. 결과: `validation/qa-build-final.log`. 개별 결과는 `validation/*.log`, 수정 전 증거는 `qa-regression-before.log`, `qa-skate-regression-before.log`에 있다.

## [PLAYER QA]

- **Movement:** 실제 W 걷기, A/D 이동, Space 점프와 착지를 조작하고 화면 확인. 대기·걷기·스트레이프·점프·낙하·착지 구분됨.
- **Wire:** 실제 마우스로 연결→감기→swinging/hold→해제→낙하 확인. 사거리 보정점과 줄 렌더링 확인. 높은 해제 뒤 도로 사망도 실제 조작에서 확인했다.
- **고속/애니메이션:** 보스 접근 자동 와이어 조작에서 35m/s와 30회 연결을 기록. 기존 30초 traversal과 character_animation 검사도 재검증. 공중 걷기 재발은 확인되지 않았다. 보조 주행 초기 로그의 pose 1프레임은 첫 visual update 전 fixture 초기 idle 표본이며, 초기 표본을 제외한 3번째 주행은 0이었다.
- **Double jump:** probe로 코어만 지급한 후 실제 Space 두 번으로 발동, 재사용 대기 9.6초 표본 확인. 기본 미해금 동작은 suite에서 확인.
- **Skate:** 실제 점프→와이어→낮은 해제→착지에서 조기 정지 버그를 발견·수정. 같은 입력 재실행에서 `slide`, charge 0.67, 수평 약 4.68m/s와 낮은 슬라이드 자세 확인. 4.36/4.69/15/25m/s 물리 probe는 충전 소진까지 지속. 충전 유지·재충전·점프만으로 재생성 금지는 suite로 보완.
- 지지면 판정만 보완했고 감기·사거리·공중 제어·해제 관성·스케이트 속도/시간 수치는 바꾸지 않았다.

화면: [와이어 연결](../validation/qa-real-hook.png), [스케이트 수정 후](../validation/qa-slide-fixed.png), [고속 조작](../validation/qa_run_0_600.png).

## [CITY QA]

- 난이도 0/500/1000/2000m, 기존 청크 불변, Player/World 독립성 통과. 기본 reach 기준 Sky Gap 내부/입구/출구/청크 경계의 기하학적 연결성 통과. 모든 경로의 사람 조작 성공을 의미하지는 않는다.
- Safe Zone, 실제 건물·배경 도시·도로·하늘·car1~5·정지 경찰 드론을 렌더링 확인했다. Safe Zone 표식이 착지 높이 규칙을 무효화하지는 않는다.
- 2060m Sky Gap의 건물 없는 드론 경로와 2320m Traffic Surge 차량 증가를 실제 창에서 확인. 차량 우측 통행·non-wireable·방어구 소모/무방어 사망은 실제 물리 suite로 확인.
- 정지 드론과 C 로봇은 같은 모델이라 움직임을 놓치면 구별하기 어렵다. 모델 교체는 하지 않았다.

화면: [Sky Gap](../validation/qa-sky-gap.png), [Traffic Surge](../validation/qa-traffic-surge.png).

## [BOSS A — SIDE LASER]

- LEFT/RIGHT 모두 렌더링 확인. tier 3 기준 X는 `[-15.4,-4.667]` 또는 `[4.667,15.4]`, Y는 0~73m, Z 깊이 40m. 중앙선을 넘지 않는다.
- 네 A/B fixture 모두 3회 점멸, 경고 중 collision OFF, 활성 120/60=2초, recovery 이후 정리 확인.
- 경고와 활성은 같은 위치·mesh/shape를 사용한다. 원점 이동 뒤에도 상대 위치 유지.
- 반대쪽은 시각적으로 읽힌다. 1.08초 예고가 모든 속도·측면 위치에서 충분한지는 미승인이다. 중앙의 열린 도로로도 회피할 수 있어 반드시 크게 좌우를 바꾸게 하는 패턴은 아니다.

화면: [LEFT 경고](../validation/qa_after_a_left_warning.png), [RIGHT 경고](../validation/qa_after_a_right_warning.png), [LEFT 활성](../validation/qa_after_a_left_active.png).

## [BOSS B — HEIGHT LASER]

- UPPER/LOWER 모두 렌더링 확인. tier 3의 코드상 사용 상단 65m, 분할 32.5m, 폭 32m, 깊이 40m. 실제 개별 건물마다 높이는 다르며 이 값은 tier의 공용 상단이다.
- 경고 3회·활성 2초·위치/크기 일치, 안전한 반쪽과 실제 overlap 사망/방어구 검증 통과.
- 화면에서 위/아래 차단은 구별된다. 활성 재질이 매우 밝아 배경을 가린다. 특히 지상에서 LOWER를 만났을 때 1.08초 안에 안전 높이로 올라갈 수 있는지는 사람 플레이 검토가 필요하다.

화면: [LOWER 경고](../validation/qa_after_b_lower_warning.png), [LOWER 활성](../validation/qa_after_b_lower_active.png), [UPPER 활성](../validation/qa_after_b_upper_active.png).

## [BOSS C — ROBOT BARRAGE]

- 1/20/40m 시점에서 3사이클 렌더링, 최대 3기, 순차 발사·이동·수명 후 0기 확인. 전체 보스 주행에서도 반복 실행됐다.
- **버그:** 기존 로봇은 보스 위치가 아니라 임의 Y에서 생겼다. 20m 시점 측정에서 보스와 47.16m 떨어진 출현을 확인. 보스 선체 좌/중/우 포트에서 나오도록 수정했으며 발사 직후 거리는 약 3.1~4.9m로 줄었다.
- 고정 16m/s, 발사 때만 속도 기반 조준, 이후 직선·비호밍 유지. 수명 6초/후방 20m/보스 escape 정리 통과.
- **가시성은 여전히 개선 대상:** 기본 지상 카메라에서 보스 중심의 화면 Y가 약 -76px(화면 밖). 20m에서는 약 76px, 40m에서는 약 229px다. beacon이 작고 일반 드론과 같은 모델이라 C가 시작됐다는 신호가 약하다. 발사 위치 수정만으로 가독성 완료라고 판단하지 않는다.
- 속도·높이별 회피 가능성과 체감 압박은 최종 승인하지 않았다. 속도·카메라·모델·패턴 시간의 디자인 조정은 하지 않았다.

화면: [수정 후 발사](../validation/qa_after_c_y20_f105.png), [이동 후](../validation/qa_after_c_y20_f240.png), [지상 시점](../validation/qa_after_c_y1_f40.png).

## [FULL BOSS RUN]

| 실행 | 방식 | 결과 |
|---|---|---|
| 0 | 3180m 배치, 코어 3종 1단계 지급, 실제 와이어 자동 조작, 추가 보호/복구 없음 | 3592.95m 장애물 사망, 30회 연결, 최고 35m/s |
| 1 | 25m/s 위치·속도/높이 보정, 보호 적용, Main/Boss/City 실제 루프 | 4750.59m, CLEARED / Rest |
| 2 | 35m/s 동일 보조 방식 | 4770.63m, CLEARED / Rest |
| 3 | 35m/s 동일 보조 방식 | 4770.63m, CLEARED / Rest |

**보조 전체 주행 3회 성공, 무보정 전체 클리어 0회.** 성공 3회를 사람 자유 플레이 성공으로 바꾸어 보고하지 않는다. A→cooldown→B→cooldown→C→cooldown 반복, 3200 시작, 4700 escape, 약 2초 후 CLEARED 확인. 현재 구현은 C 뒤뿐 아니라 각 패턴 뒤에도 cooldown이 있다.

고속 진행 기준 1500m는 약 43초(35m/s)~60초(25m/s)로 3패턴을 여러 번 본다. 반복 피로도와 불가능한 조합의 부재는 승인하지 않았다. 일반 드론에 실패한 자동 조작 1회만으로 보스가 불공정하다고 단정하지도 않는다. 보스 전체 주행은 마지막 스케이트 지지면 수정 전 수행했고, 그 수정 뒤에는 스케이트 재플레이와 전체 suite를 다시 실행했다.

## [REST AREA / STORY]

- 보조 주행에서 Boss Clear, retreat/despawn, 모든 공격·로봇 정리, Signal 3종 1회씩 발생 확인. 보스/휴식 구간 event 억제는 실제 생성 경로와 suite에서 확인.
- 첫 Rest 청크의 4703/4708.25/4713.5/4718.75/4724m 드론과 외부 차량 침범을 수정. 30초 차량 이동 probe에서 Rest 내부 차량 6대→0대, 드론 5기→0기.
- 4800m 실제 창에서 중력 착지 후 `ground/idle`, 속도 0으로 정지 가능함을 확인. 자동 heal/recharge 보너스는 추가하지 않았다.
- [휴식 화면과 Clear Signal](../validation/qa-rest-stop.png).

## [BUGS FIXED]

| 재현 | 원인 | 최소 수정 | 재검증 |
|---|---|---|---|
| 4096m에서 보스 위험물이 약 2048m 멀어짐 | Main rebase에서 Boss 누락; 패턴은 top-level | boss 및 독립 root들을 각각 한 번 이동 | Main 실제 분기, A/B와 live robot, 전후 화면 |
| Rest 첫 28m에 드론·차량, 이후 외부 차량 진입 | 청크 시작만으로 rest 판정, 움직이는 차량에는 제한 없음 | 생성 footprint·차량 이동 구간과 Rest 겹침 검사 | 경계 청크, 양 방향 차량, origin offset 포함 |
| C가 보스와 떨어진 허공에 출현 | random Y 및 보스 뒤 Z에서 spawn | 선체 기준 고정 포트 사용 | 세 포트 거리, 3시점 렌더링, 직선·수명 회귀 |
| A/B collision 2초보다 1 tick 길음 | 1/60 반복 차감의 양수 잔여 오차 | phase 종료에 작은 epsilon | LEFT/RIGHT/UPPER/LOWER 각 120 tick |
| 스케이트가 77~95% charge를 남기고 정지 | 일시적 floor 접촉 누락→air→새 착지로 정지 | 5cm 도로 지지 검사 후에만 air 판정 | 6개 실패→통과, 실제 마우스 재플레이, 낭떠러지 즉시 air 검사 유지 |

## [PERFORMANCE]

- 보조 주행의 1초 간격 FPS 표본 중앙값은 60(60fps 제한), resident chunks는 7~8. 최고 노드는 run1 12,189, run2/3 12,343으로 반복 실행마다 계속 증가하지 않았다. Rest 진입 후 약 5천대로 감소.
- 일반 차량 약 38~44대, barrage 최대 3기, 수명/escape 이후 0기. 동일 seed/경로 반복에서 누적 징후 없음. 장시간 soak test까지 수행한 결과는 아니다.
- Main에서 실제로 4096m origin shift를 통과했고 화면·pattern·robot 좌표 연속성을 재확인했다.
- 청크 생성 순간 physics monitor는 일부 표본에서 약 20~21ms. 새 run/강제 거리 배치 직후 27~53fps도 관측. 자동 검증 동시 실행 및 probe 캡처 영향을 포함하므로 독립 성능 벤치마크/1% low 수치로 사용하지 않는다. streaming hitch는 후속 프로파일링 대상이다.

## [HUMAN/DESIGN REVIEW]

1. C의 ground-view 발사 예고, 작은 beacon, 일반 드론과 구분되는 world-space 표현. 신규 HUD 없이 먼저 검토할 것.
2. B LOWER의 지상 대응과 A의 측면 전환 시간: 기본 능력, 실제 입력, 15/25/35m/s별 자유 플레이 필요.
3. A/B 활성 재질 밝기·시야 가림, 초반 청록 표식 밝기, 1500m 반복 체감. 현재 값을 임의 조정하지 않았다.
4. 큰 드론 모델의 시각적 외곽은 기존 충돌 박스보다 높이/깊이가 크다. 기존 asset-fit 정책이며 이번에는 유지했다. 충돌 학습성과 C 구분성 평가에 포함할 것.
5. 캐릭터 선택 UI는 없고 `ACTIVE_CHARACTER` 및 단일 CHARACTERS 항목을 사용한다. 신규 캐릭터 선택 기능은 구현하지 않았다.

## [NEXT DEVELOPMENT]

1. C 가독성과 B LOWER 대응의 짧은 사용자 플레이테스트. 위 스크린샷/측정으로 범위를 좁힌 뒤 디자인 확정.
2. 실제 기본 능력으로 보스 무보정 클리어 반복 및 실패 위치 기록. 필요하면 확정된 값만 조정.
3. 청크 생성·배경 도시/모델 인스턴싱 비용을 단독 프로파일링하고, 확인된 hitch만 최적화.
4. 이동·착지·코어 해금의 플레이 안내를 다듬고 사용자가 룰을 읽을 수 있는지 확인.
5. 이 검증이 끝난 뒤 최종 Boss asset 또는 다음 지역/캐릭터 선택을 별도 승인 범위로 계획. 이번 작업에서는 시작하지 않았다.

## [BUILD / ARTIFACTS]

- Windows EXE: `builds/WireRush-0.12.4-Windows/WireRush.exe`.
- ZIP: `builds/WireRush-0.12.4-Windows.zip`.
- 빌드 도구의 전체 Validate→export→ZIP 완료, exit 0. 배포 EXE를 별도로 2회 실행해 메뉴와 자동 스윙 화면을 확인했다. 모두 exit 0, `CAPTURE_RESULT 0`, 로그에 SCRIPT ERROR/ERROR 없음.
- EXE SHA256: `42F0630F0D36D2F49741D90DEFFEEDD1215B9CB40037FCB778785787C6FBC6C9`.
- ZIP SHA256: `E58EAD75DD536A4F329B429B03C3FB13A76DBB708321904263FC494F1E12F0D2`.
- [배포 메뉴](../validation/qa-export-menu.png), [배포 스윙](../validation/qa-export-play.png). 직접 입력 QA는 소스 실행에서, 배포 EXE smoke test는 기존 demo 기능으로 수행했다.
- 임시 `.gd` probe, UID, Windows 입력 helper는 제거했다. `git diff --check` 통과. 최종 HEAD는 시작 HEAD 그대로이며 commit/push하지 않았다.
- 로그/화면은 `.gitignore` 정책대로 로컬 `validation/`에 보관한다. 연결된 이미지가 없는 다른 checkout에서도 본문의 재현값·판정은 읽을 수 있다.
