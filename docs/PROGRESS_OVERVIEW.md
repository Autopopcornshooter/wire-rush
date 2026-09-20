# Wire Rush — 프로토타입 0.7.0

2026-09-14. E 두 줄 사출을 제거하고 벽 점프·이중 점프를 새 기본 이동 능력으로 추가했습니다. 건물 배치는 배치 비교 실험 중 건물 간격 방식을 기본으로 고정했고, 연습 모드는 항상 양쪽 벽을 배치합니다. 이어서 스케이트를 마찰 계수 방식에서 등급별 2/3/4초 지속시간 방식으로 되돌리고, 점프 높이와 이중 점프를 별개의 업그레이드로 분리했으며, 레벨업이 즉시 정지하지 않고 업그레이드 대기 스택을 쌓다가 G 키로 한 번에 소비하도록 변경했습니다. 벽 점프는 실전에서 확인되지 않아 주석 처리로 비활성화했고, HUD를 큰 폭으로 정리해 불필요한 문구·패널을 제거했습니다.

2026-09-20 (PHASE A — Player Progression 개편). 업그레이드를 일반(WIRE/MOBILITY/MOMENTUM/SURVIVAL, 12종)과 코어(이중 점프·롤러스케이트·충격 방어구, 5레벨마다 1회)로 분리했습니다. 대기 큐는 각 항목의 종류(일반/코어)를 그대로 기억해 쌓인 순서대로 소비합니다. Building Height를 플레이어 업그레이드에서 완전히 제거하고 월드 쪽 값(City.high_level, 다음 난이도 시스템을 위해 남겨둠)으로만 유지합니다. SLINGSHOT/STREET SURFER/SKY RUNNER 3개의 자동 발동 시너지를 추가했습니다. 새 HUD 요소는 추가하지 않았고(기존 업그레이드 카드에 카테고리 라벨만 추가), 기존 City/애니메이션/차량/세이프존 등 핵심 게임플레이는 변경하지 않았습니다.

2026-09-20 (PHASE B — Difficulty Director + City Event System). 새 `scripts/difficulty_director.gd`가 진행 거리만으로 City 난이도를 결정합니다(0~500/500~1000/1000~2000/2000m+ 4단계 — TIER마다 building_height_level·공중 장애물 밀도·차량 밀도가 오름). Building Height는 이제 이 Director가 `City.apply_height_level()`을 매 프레임 호출해 정하며(PHASE A가 남겨둔 그 API를 그대로 재사용), 플레이어 업그레이드는 이 값에 전혀 관여하지 않습니다 — 기존처럼 이미 생성된 청크는 절대 바뀌지 않고, 새로 스트리밍되는 청크만 그 시점의 난이도를 반영합니다. 기존 2000m 이후 "no-building" 특수 케이스를 City Event 구조(SKY_GAP/TRAFFIC_SURGE, `City.event_for_chunk()`)로 정리하고, 새 이벤트 TRAFFIC SURGE(짧은 구간 차량 밀도 증가, 기존 car1~5만 사용)를 추가했습니다. 공중 장애물의 높이 배치 공식을 대칭 삼각파 방식으로 바꿔, 이전에 있던 "연속된 두 장애물이 이론상 기본 사거리 밖으로 벌어질 수 있는" 잠재적 버그(Traversability Guard, `City.MAX_BASE_TRAVERSAL_GAP`)를 없앴습니다. 새 HUD·난이도 표시는 추가하지 않았습니다.

2026-09-20 (PHASE C — City Boss Graybox + Rest Area + Signal Story). 새 `scripts/city_boss.gd`(Traversal Boss "Police Interceptor", 그레이박스)가 3200m(`DifficultyDirector.CITY_BOSS_START_DISTANCE`)에서 시작해 700m 진행 시 클리어됩니다. 체력·전투 시스템 없음 — INACTIVE→INTRO→ACTIVE→ESCAPE→CLEARED 상태를 거치며, ACTIVE 동안 PATH_BLOCK→LASER_SWEEP→DRONE_GATE를 고정 순서로 반복합니다(각 패턴은 telegraph→active→recovery 3단계). PATH_BLOCK은 항상 한쪽만 막고 반대편은 always open, LASER_SWEEP은 한 높이대만 가로지르며 기존 `Rider.hurt()`(방어구 1회 소비 규칙 그대로) 경로를 재사용, DRONE_GATE는 `City.obstacle()`을 그대로 호출해 기존 police drone 비주얼·collision·wireable 규칙을 상속합니다. Boss/Rest Area(클리어 후 400m, `DifficultyDirector.is_rest_zone()`) 구간에서는 Sky Gap/Traffic Surge가 겹치지 않도록 `DifficultyDirector.event_for_chunk()`에서 억제하고, Rest Area는 hazard·차량·drone을 아예 생성하지 않습니다. 새 `scripts/signal_story.gd`가 City Start/Mid/Boss Clear 3개의 1회성 자막을 관리하며(`Hud.draw_signal_subtitle()`, 새 다이얼로그창 없이 하단 자막만), Rest Area 끝에는 장식용 Wasteland 진입 게이트만 배치했습니다(실제 Wasteland 콘텐츠 없음). Player Progression(rider.gd/main.gd의 업그레이드·시너지 로직)은 이번 PHASE에서 전혀 수정하지 않았습니다.

2026-09-20 (PHASE C BOSS REVISION — Path Block/Laser 형태 확장 + Boss 길이 연장). `DifficultyDirector.CITY_BOSS_ESCAPE_DISTANCE`를 700m→**1500m**로 확장(Boss clear 3900m→**4700m**, Rest Area는 파생 상수 그대로 따라가 **4700~5100m**로 자동 이동 — 고정 숫자 중복 없이 `city_boss_clear_distance()`/`rest_area_end_distance()`만 수정). PATH_BLOCK을 6×9×3m 작은 박스에서 **한쪽 건물 라인 전체를 덮는 세로 벽**(폭 8m=건물 폭과 동일, 높이는 `City.high_level`에 따라 매 스폰 시 동적 계산 — `35(최대 base_height) + Rules.BUILDING_BONUS[high_level] + 8(여유분)`, 바닥 y=0부터 시작)으로 변경. LASER_SWEEP을 14m 폭의 얇은 빔에서 **양쪽 건물 라인 전체를 가로지르는 32m 폭의 면**(Y 두께는 0.6m로 그대로, 한 높이대만 위협)으로 변경. 두 패턴 모두 telegraph→active→recovery 단계, non-hookable, `Rider.hurt()` 재사용, DRONE_GATE는 완전히 무변경. 이 변경으로 Sky Gap/Traffic Surge 억제 구간과 Signal Story trigger는 파생 상수를 그대로 참조하므로 코드 수정 없이 자동으로 따라감.

2026-09-21 (PHASE C BOSS PATTERN REVISION V2 — Path Block/Laser 재정의 + Drone Gate 삭제 후 Robot Barrage 신설). PATH_BLOCK을 "루트를 막는 벽" 개념에서 **"한쪽 아파트 라인 전체가 잠깐(telegraph 0.8s/active 1.5s/recovery 0.4s) 접촉 즉사 구역이 되는" 개념**으로 재정의(폭/높이 계산식은 그대로, Z 범위만 4m→30m로 넓혀 짧아진 active 구간에도 실제로 플레이어 위치와 겹치도록 함). LASER_SWEEP을 y=8/30 고정 2단 교대에서 **매 스폰 시 0..건물 높이 사이 랜덤 높이**(`LASER_MIN_HEIGHT`/`LASER_TOP_MARGIN`로 경계, `city_boss.gd` 자체 RandomNumberGenerator 사용) 방식으로 변경하고 이름을 `LASER_PLANE`으로 바꿈, active를 0.5s→1.5s로 늘림. **DRONE_GATE를 완전히 제거**하고 새 패턴 **ROBOT_BARRAGE**로 교체 — 보스가 좌/중/우에서 장애물 로봇 3기를 0/0.45/0.9초 간격으로 순차 발사, 각 로봇은 발사 순간 플레이어 위치+속도로 소폭 선행 조준한 뒤 그 방향으로 고정 직진(호밍 없음), `City.spawn_vehicle()`과 동일하게 `AnimatableBody3D(sync_to_physics=false)`로 구현해 기존 차량과 같은 이동 충돌 방식을 재사용(`City.obstacle()`의 정지형 StaticBody3D는 사용하지 않음 — 움직이는 StaticBody3D는 충돌이 불안정해지는 기존에 확인된 이슈). 로봇은 패턴의 telegraph/active/recovery/cooldown 주기와 무관하게 자기 수명(6초) 또는 플레이어보다 충분히 뒤처지면 개별적으로 정리되며, Boss ESCAPE 진입 시 강제 정리됨. Boss 거리(3200/4700m)·Rest Area·Player Progression·Difficulty Director는 전혀 변경 없음.

2026-09-21 (PHASE C BOSS PATTERN REVISION V3 — A/B 레이저 범위 재정의 + 예고 연출). PATH_BLOCK을 **"닫힌 쪽 건물 라인 + 그 쪽 도로의 약 1/3까지 가로 범위 전체를 막는" 형태**로 재정의(`path_block_x_bounds()`: 건물 바깥쪽 끝선~도로 1/3 안쪽선, 도로 중앙선은 절대 넘지 않음. Y는 도로면~현재 Building Height 기준 최고 사용 높이까지, Z는 새 공용 상수 `PATTERN_ZONE_DEPTH`(40m)로 패턴 존 전체를 덮음). LASER_PLANE을 **"현재 사용 높이를 정확히 절반으로 나누고 위쪽 또는 아래쪽 절반 전체를 막는" 두꺼운 볼륨**으로 재정의(`laser_half_bounds()`: 매 스폰마다 위/아래를 번갈아 선택, X는 두 건물 라인+도로를 모두 덮는 전체 폭, Z도 동일한 `PATTERN_ZONE_DEPTH`). 두 패턴 모두 **공용 예고 연출**을 새로 추가 — 최종 위치·크기와 완전히 동일한 위험 볼륨이 대각선 해치 무늬의 반투명 붉은 재질로 즉시 나타나 충돌 없이 3회 점멸(약 1.08초) 후, 밝은 활성 재질로 전환되며 정확히 2.0초 동안 충돌이 유지됨(`WARNING_BLINK_COUNT`/`WARNING_BLINK_ON_TIME`/`WARNING_BLINK_OFF_TIME`/`WARNING_TOTAL_DURATION`/`WARNING_ACTIVE_DURATION` 공용 상수, `warning_blink_visible()`/`warning_material()`/`warning_hatch_texture()` 공용 함수). 새 HUD 경고 UI 없이 월드 공간 연출만 사용. `Rider.hurt("OBSTACLE COLLISION")` 재사용·방어구 1회 소비·중복 피격 억제는 완전히 그대로 유지(방어구 보호 시간 2.0초가 새 active 지속시간 2.0초와 정확히 일치). ROBOT_BARRAGE·Boss 상태 머신·Boss 거리(3200/1500/4700m)·Player Progression·Difficulty Director·Sky Gap/Traffic Surge는 전혀 변경 없음.

## 실행

- 프로젝트: `D:/GameProject/WireSwing/project.godot`
- 실행 파일: `builds/WireRush-0.7.0-Windows/WireRush.exe`
- 배포 ZIP: `builds/WireRush-0.7.0-Windows.zip`
- 저장소: https://github.com/Autopopcornshooter/wire-rush

기존 HellDelivery와 별도의 프로젝트입니다. 엔진·템플릿·빌드는 Git에서 제외하며 이전 0.1.0~0.5.2 로컬 빌드는 보존합니다.

## 현재 구현

| 영역 | 동작 |
|---|---|
| 입력 | 수동 한 줄만 사용. 좌·우 버튼으로 새 연결점 선택, 활성 버튼 유지로 감기, 해제로 관성 비행 |
| 먼 조준 | 조준 방향과 최대 사거리에 가까운 실제 벽·공중 장애물 표면으로 보정. 커서에 실제 연결점 표시, 사거리 퍽 반영 |
| 연결 유지 | 연결 완료된 공중 장애물 자체는 줄 가림에서 제외. 다른 물체의 줄 가림과 캐릭터 충돌 유지 |
| 벽 점프 | 코드는 있으나 비활성화(주석 처리). 건물 벽 자체는 몸으로 부딪혀도 안전(피격 없음) |
| 이중 점프 | 공중(벽 미접촉)에서 Space 1회 추가 점프. 기본 10초 재사용, 이중 점프 퍽 등급마다 10/7/5/3초로 단축(점프 높이 퍽과 별개) |
| 배치 | 건물 간격 방식으로 고정(128m 구역마다 한쪽 벽 제거). 연습 모드는 항상 양쪽 벽 |
| City 난이도 | Difficulty Director가 거리만으로 4단계 진행(0~500/500~1000/1000~2000/2000m+). Player Progression과 완전히 독립 — 업그레이드를 선택해도 난이도는 안 변하고, 거리가 늘어도 플레이어 tier는 안 변함 |
| City Event | SKY_GAP(2000m 이후, 3청크 길이, 10청크 주기 쿨다운: 건물 없음·드론만·차량 없음)과 TRAFFIC_SURGE(500m 이후 확률 등장, 3청크 길이: 차량 밀도만 일시 증가) 2종. 둘 다 종료 후 정상 City로 복귀, 경고 UI 없음 |
| City Boss | "Police Interceptor"(그레이박스), 3200m 시작·1500m 진행(4700m) 시 클리어. HP/전투 없음 — PATH_BLOCK(닫힌 쪽 건물 라인+도로 약 1/3까지 가로 범위 전체가 도로면~현재 건물 최고높이까지 막힘)→LASER_PLANE(현재 사용 높이를 정확히 절반으로 나눈 위/아래 절반 전체, 두 건물 라인+도로를 모두 덮는 전체 폭)→ROBOT_BARRAGE(장애물 로봇 3기 순차 직진 발사, 발사 시점 선행조준 후 비호밍, 자체 수명으로 정리) 고정 순서 반복. A/B 모두 최종 위험 볼륨과 동일한 붉은 해치 무늬가 충돌 없이 3회 점멸 후 정확히 2.0초 활성(방어구 1회 방어). 항상 반대편(A)·반대쪽 절반(B)으로 통과 가능한 route 보장. 클리어 시 후퇴·despawn |
| Rest Area | Boss 클리어 후 400m, hazard·차량·drone 없음, Sky Gap/Traffic Surge 없음. 물리·이동은 그대로 유지, 자동 이동·시네마틱 카메라 없음. 끝나면 CITY_COMPLETE + Wasteland 진입 장식 게이트 |
| Signal Story | City 시작/1500m/Boss 클리어 총 3개 자막, 한 run에 1회씩만. 하단 소형 자막(3.5초, 페이드), 게임 멈춤 없음. 한국어/영어 지원 |
| 업그레이드 | 일반 업그레이드(와이어/기동성/모멘텀/생존 4카테고리, 12종)와 코어 업그레이드(이중 점프·롤러스케이트·충격 방어구 3종, 5레벨마다 1회)로 분리. 레벨업은 즉시 멈추지 않고 종류(일반/코어)를 유지한 채 대기 스택에 쌓이며, G 키로 쌓인 순서대로 소비. 건물 높이는 이 목록에서 제외(아래 건물 항목 참고) |
| 시너지 | 조건 충족 시 자동 발동(직접 선택 불가): SLINGSHOT(감기+사거리 투자, 고속 해제 시 소폭 가속), STREET SURFER(롤러스케이트 최고 등급+모멘텀 투자, 슬라이드 종료 시 관성 일부 유지), SKY RUNNER(이중 점프 최고 등급+점프력 투자, 이중 점프 직후 첫 와이어 연결 가속) |
| 제외 | E 두 줄 사출, 배치 선택 설정, 자동 앵커 네트워크, 마우스 두 와이어 독립 모드, 와이어 개수 설정 |
| 착지 | 마지막 줄 해제 당시 플레이어 높이 5m 이하만 도로 생존. 5m 초과는 보호·방어구·연습 복구와 관계없이 게임오버 |
| 점프 | 일반 점프는 높이 예외. 새 연결이 성립하면 예외 해제, 이후 플레이어 해제 높이를 사용 |
| 스케이트 | 새 연결 후 플레이어 높이 5m 이하에서 해제하고 착지. 등급별 2/3/4초 동안 착지 속도 유지 후 정지. 점프만으로 슬라이드 갱신 불가 |
| 건물 | 높이는 플레이어 업그레이드가 아니라 Difficulty Director가 거리로 결정하는 월드 값(0~3단계). 값이 바뀌어도 그 시점 이후 새로 생성되는 청크만 반영, 기존 청크·벽 연결점은 그대로 유지 |
| 공중 장애물 | 첫 128m 이후 64m당 4개 이상(거리 구간별로 증가). 약 2.6×2.2×1.4m, 연결 가능하며 몸 충돌은 위험. 높이 배치는 대칭 삼각파(항상 낮은 구간에서 시작·종료)라 연속 장애물 사이가 기본 사거리를 넘지 않음이 보장됨 |
| 고층 장애물 | 건물 퍽에 맞춰 +8/+16/+24m. 앵커가 이동해도 착지 기준은 플레이어 해제 높이 |
| 보호 | 방어구 및 복귀 후 2초 보호는 장애물 충돌에 적용. 5m 초과 해제 후 도로 착지는 우회 불가 |
| 기타 | 한국어/영어, 먼 카메라, XP·레벨업·기록, 청크 정리·원점 이동, EXE·ZIP |

## 검증

Godot 4.7.1.stable.official.a13da4feb / Windows / NVIDIA GeForce RTX 2070 SUPER / OpenGL Compatibility.

- 에디터 import와 Windows export 오류 없음.
- `tests/run.gd`: **77/77**. 실제 갈고리·줄 제약·관성, 플레이어 해제 높이 4.99/5.00/5.01/18m 착지 경계, 방어구·보호·연습 우회 방지, 높은 앵커에서 낮은 해제·낮은 앵커에서 높은 해제·재연결 후 낮은 해제, 점프 예외, 등급별 슬라이드 지속시간·속도 유지·정지, 점프 후 슬라이드 재생성 방지, 건물 메시·콜라이더/기존·미래 구간/최대 등급, 공중 장애물 연결·위험성, 이동한 장애물과 해제 높이 독립성, 해제 이후 상승·하강/갈고리 취소/복귀/연결 유지 착지, 청크·원점·성장, 두 줄 사출 제거 확인, 레벨업 대기 스택·G 키 순차 소비·전부 맥스일 때 무모달 소비.
- `tests/settings_aim.gd`: **36/36**. 언어·설정·버튼·정지, 마우스 입력 큐·조준 광선·벽 선택, 한 줄 교체·개별 버튼 해제, 사거리·가림·임시 연결점 정리, 제거한 기능 부재.
- `tests/range_obstacle.gd`: **24/24**. 실제 카메라의 먼 벽·장애물 조준, 30/39m 경계, 보정점 발사·연결, 표면 부재·가림, 장애물 뒤쪽 스윙·높이 변경 중 연결 유지, 다른 장애물의 가림과 캐릭터 충돌.
- `tests/jump_abilities.gd`: **19/19**. 기본 건물 간격 배치와 연습 모드 양쪽 벽 확인, 지상 점프·이중 점프 높이 일치, 이중 점프 소비·기본 10초 재사용, 점프 높이 퍽과 이중 점프 퍽의 분리(각각 단독으로 높이만/재사용만 변경), 착지해도 쿨다운은 그대로 유지, 실제 고속 건물 충돌이 안전하고 벽 접촉을 감지함, 벽 점프가 비활성화되어 벽 접촉만으로는 추가 점프가 발동하지 않음.
- `tests/comfort.gd`: **37/37**. 옥상 시작 낙하, 방어구 위치·속도 보존·점멸·충돌 클러스터 1회 소비, 레벨업 선택지 제외, 복귀 카운트다운 3·2·1, 마우스 카메라 댐핑·사거리.
- `tests/traversal.gd`: 수동 위치 지정 자동 입력으로 장애물 없는 연습 구간 **30초 / 975.08m / 82회 연결 / 복구 0회**, 도중 사망 없음.
- 배포 EXE: 메뉴, 한국어/영어 설정, 수동 스윙 렌더링을 캡처·검토. 각 실행 exit 0, stderr 비어 있음.

자동 검사는 지정된 위치·속도 fixture와 실제 물리 이동을 사용합니다. 사람의 자유 플레이·장애물 전체 조합의 공정성·시각 피로를 검증한 결과는 아닙니다. 이전 버전에서 제거된 규칙의 검사는 현재 규칙의 검사로 교체했습니다.

## 후속 기준

1. [핵심 조작 #1](https://github.com/Autopopcornshooter/wire-rush/issues/1): 높은 스윙→플레이어 높이 5m 이하에서 해제→마찰 슬라이드→점프·재연결의 사람 입력 체감과 학습 난도.
2. [공중 장애물 #2](https://github.com/Autopopcornshooter/wire-rush/issues/2): 소형 블록의 조준성·회피 경로·고층 밀도·충돌 예고를 높이 등급마다 확인.
3. [표현·접근성 #3](https://github.com/Autopopcornshooter/wire-rush/issues/3): 음량, 아트·애니메이션, 플레이어 해제 높이 규칙의 튜토리얼 개선.

검증 로그와 임시 캡처는 `validation/`, 최신 대표 화면은 `docs/screenshots/`에 있습니다.
