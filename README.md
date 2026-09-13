# Wire Rush

건물과 공중 장애물에 한 줄 와이어를 직접 걸어 스윙하고, 낮은 지점에 재연결해 착지하는 3D 게임 프로토타입.

**v0.5.0 · Godot 4.7.1 · Windows x64 · 한국어/English · 오프라인 싱글플레이**

![Wire Rush gameplay](docs/screenshots/gameplay.png)

## 실행과 조작

로컬 `builds/WireRush-0.5.0-Windows.zip`을 풀고 `WireRush.exe`를 실행합니다. 엔진 설치 없이 실행할 수 있습니다.

- **좌·우 마우스 버튼 유지:** 커서가 가리킨 건물 또는 공중 장애물에 수동 연결하고 자동으로 줄을 감습니다.
- **반대 버튼:** 현재 한 줄을 새 지점으로 옮깁니다. 활성 버튼을 놓으면 관성을 유지하며 해제합니다.
- **Space:** 지상·스케이트에서 점프. **A/D:** 조향.
- **Esc:** 일시정지·설정. **R:** 재시작. **1/2/3:** 레벨업 선택.
- 설정에서는 한국어/English를 즉시 바꾸고 저장할 수 있습니다.

자동 앵커, 두 와이어 모드, E 양측 사출과 해당 업그레이드는 제거했습니다. 이전 설정 파일의 조준·와이어 개수 값도 사용하지 않습니다.

## 착지·장비·장애물

**마지막으로 실제 연결한 지점이 5m 이하일 때만 도로에 안전하게 착지합니다.** 5m를 넘으면 도로 충돌 시 게임오버이며 방어구·복귀 보호·연습 복구로 막을 수 없습니다. 일반 점프는 예외지만 점프 중 높은 지점에 새로 연결하면 예외가 해제됩니다. 벽의 청록색 선은 5m 높이 기준입니다.

스케이트는 낮은 연결 후 착지할 때 시작합니다. 타이머 대신 **마찰 계수 0.35 / 0.22 / 0.12**로 자연스럽게 감속합니다. 점프만 하고 재착지하면 스케이트가 갱신되지 않으며, 새로 낮은 지점에 연결해야 다시 슬라이드할 수 있습니다.

높이 업그레이드는 현재·미래 건물을 **+10 / +20 / +30m** 높이고 공중 장애물도 **+8 / +16 / +24m** 올립니다. 공중 장애물은 64m마다 4개, 각각 약 **2.6 × 2.2 × 1.4m**입니다. 연결할 수 있지만 몸으로 충돌하면 위험합니다. 도전 첫 128m와 연습 모드는 장애물 없이 시작합니다.

카메라는 기존 먼 시점(뒤 12m·위 4.5m)을 유지합니다. 상세 규칙은 [플레이 안내](docs/PLAY_GUIDE.md)에 있습니다.

## 개발과 검증

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate.ps1 -Godot 'C:\path\Godot_v4.7.1-stable_win64_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Windows.ps1 -Godot 'C:\path\Godot_v4.7.1-stable_win64_console.exe' -Templates 'C:\path\4.7.1.stable'
```

템플릿은 실행 엔진과 일치하는 공식 Windows export templates를 사용합니다. 엔진·템플릿·빌드 파일은 Git에 넣지 않습니다. `--test`는 기록 파일을 쓰지 않는 검증 모드입니다.

- [진행 현황과 검증 범위](docs/PROGRESS_OVERVIEW.md)
- [설계 및 원문 대비 결정](docs/IMPLEMENTATION.md)
- [원문 자료](docs/ORIGINAL_BRIEF.md)
- [엔진 라이선스 고지](docs/THIRD_PARTY_NOTICES.md)

새 저장소: https://github.com/Autopopcornshooter/wire-rush

로컬 개발 폴더는 `D:\GameProject\WireSwing`입니다. 기존 HellDelivery와 별도 Git 저장소입니다.
