# yt-dlp GUI · iOS 0.2.0

iOS 26용 SwiftUI 앱(build 6)입니다. Liquid Glass 카드, 시스템 탭·도구 막대와 SF Symbols를 사용해 표준 iOS 앱 구조를 따릅니다.

## 포함된 기능

- 링크 입력과 시스템 붙여넣기 버튼
- 제목, 제작자, 길이, 썸네일 확인
- MP4 동영상 / M4A 오디오 선택
- 최고 화질 / 1080p 이하 / 720p 이하 / 480p 이하
- 비디오·오디오 형식 ID 직접 지정
- 언어 우선순위 및 자동 생성 자막 옵션, 미디어와 자막 함께 공유
- 안전한 허용 목록 기반 추가 yt-dlp 인자
- 앱 안에서 최신 yt-dlp wheel 원클릭 설치 및 번들 버전 복구
- 진행률, 속도, 예상 시간, 취소
- 공유 시트에서 링크·형식·화질을 본 앱으로 전달해 바로 다운로드하고, 앱을 열 수 없으면 대기열에 추가
- Dynamic Island·잠금 화면 Live Activity 진행률과 최근 로그 2줄
- 현재 또는 마지막 작업의 로그 500개 저장·공유
- 다운로드 중 무음 오디오 반복 재생으로 백그라운드 실행 유지 시도, 설정에서 끄기
- 기기 내 보관함, Quick Look 미리보기, 공유 및 파일 앱 저장
- 시스템 / 라이트 / 다크 모드
- 앱 내부 CPython과 yt-dlp. 별도 서버 없음
- YouTube EJS를 Apple JavaScriptCore에서 실행하는 네이티브 어댑터
- GitHub Actions의 기기 및 시뮬레이터 빌드 설정

`Design/preview.html`은 초기 화면 구상을 위한 예전 정적 데모입니다. 현재 SwiftUI 화면과 차이가 있으며 실제 다운로드를 실행하지 않습니다.

## 현재 검증 상태

Linux 환경에서 Python 엔진과 패키징 테스트 19개가 통과했습니다. 테스트에는 실제 yt-dlp HTTP 다운로드, 영상/오디오 두 파일 검증, 외부 프로세스 호출 방지, 화질 상한·코덱·형식 ID 선택, 자막 선택, 추가 인자 차단, SHA-256 검증 업데이트, 취소, JavaScriptCore 제공자 등록과 플랫폼별 확장 모듈 배치가 포함됩니다.

**Xcode 컴파일, iPhone 설치, JavaScriptCore에서의 실제 YouTube 챌린지 실행, AVFoundation 병합, 공유 확장, Live Activity, 무음 오디오 백그라운드 실행은 아직 검증하지 못했습니다.** 따라서 설치·다운로드 성공이 확인된 배포판이 아니라 빌드 및 기기 검증을 진행할 소스 버전입니다. 아래 Actions 설정은 포함되어 있으며 여기서 실행된 것은 아닙니다.

## 맥 없이 GitHub Actions로 빌드

1. 새 GitHub 저장소에 이 폴더의 **내용**을 업로드합니다. `App`, `Python`, `tools`, `.github`가 저장소 루트에 있어야 합니다. `.github`도 업로드해야 합니다.
2. 저장소의 **Actions → iOS build → Run workflow**를 실행합니다. `main`으로 push해도 실행됩니다.
3. 빌드가 성공하면 `yt-dlp-GUI-unsigned-IPA` 결과물을 받습니다.
4. 결과물은 **미서명 IPA**입니다. 파일을 받는 것만으로 iPhone에 설치할 수 없으며, 본인 기기용 서명과 설치 도구가 별도로 필요합니다. 서명 도구는 앱뿐 아니라 포함된 Python 확장 프레임워크도 서명해야 합니다. 공유·Live Activity 확장도 서명해야 하며 앱과 공유 확장에 동일한 App Group 권한을 포함해야 합니다.

기본 runner는 `macos-15`이며, 설치된 Xcode 중 26 이상을 자동으로 선택합니다. 해당 runner에 Xcode 26 이상이 없으면 명확한 오류와 함께 종료하므로, 그때 사용 가능한 더 최신 macOS runner로 바꿉니다.

이 프로젝트는 본인의 저장소에 게시하거나 Actions를 원격 실행하지 않았습니다. Apple 계정, 인증서, 프로비저닝 프로파일은 포함하지 않습니다.

## 맥에서 빌드

Xcode 26 이상과 Python 3.12 이상이 필요합니다.

```sh
brew install xcodegen
python3 tools/bootstrap.py
open YTDLPGUI.xcodeproj
```

Xcode에서 Signing & Capabilities의 Team을 본인 계정으로 선택하고, 필요하면 Bundle Identifier를 고유한 값으로 수정한 뒤 기기를 선택해 실행합니다. 생성 전 Bundle Identifier를 바꾸려면 `project.yml`의 앱·두 확장 식별자를 편집합니다. `APP_GROUP_IDENTIFIER`를 본인 팀에서 등록한 그룹으로 변경하고, 앱과 공유 확장 모두 같은 App Group과 Team으로 서명하세요.

bootstrap은 SHA-256으로 고정한 BeeWare Python 3.13 iOS 지원 패키지와 버전을 고정한 순수 Python 패키지를 가져옵니다. 표준 라이브러리의 네이티브 확장은 Python 3.13 공식 iOS 가이드의 패키징 방식에 따라 프레임워크로 옮기며, `.fwork`와 `.origin`으로 Python 로더에 위치를 알려줍니다. 다운로드 또는 빌드 환경에 따라 최초 설치에 시간이 걸릴 수 있습니다.

## 동작 범위

- MP4는 HTTP(S)로 받을 수 있는 H.264 / AAC 원본을 선택합니다. 더 높은 해상도의 AV1·VP9만 제공되는 경우 선택한 상한보다 낮은 해상도로 저장될 수 있습니다. 화질 선택은 업스케일이 아닙니다.
- 영상과 오디오가 분리되어 있으면 각각 내려받고 AVFoundation으로 합칩니다. FFmpeg 실행 파일은 사용하지 않습니다.
- M4A는 AAC 오디오 원본을 저장합니다. MP3 변환, WebM, 암호화 HLS, DRM, 로그인 쿠키, 재생목록 및 진행 중인 라이브는 첫 버전의 범위에 포함하지 않습니다.
- YouTube는 yt-dlp의 추출기와 번들 EJS를 사용합니다. 제공자 등록과 EJS 버전 검증은 통과했지만 JavaScriptCore 호환성과 실제 YouTube 다운로드 성공은 기기에서 확인해야 합니다. 서비스 변경, 추가 인증 요구에 따라 실패할 수 있습니다.
- 무음 오디오 설정은 기본 켜짐입니다. 다운로드 시작 시 16 kHz 모노 PCM의 모든 샘플이 0인 WAV를 반복 재생하고 완료·실패·취소 시 종료합니다. `.playback` + `.mixWithOthers`와 `UIBackgroundModes: audio`를 사용합니다. 오디오 중단 후 시스템이 재개를 허용하면 진행 중 작업에 한해 다시 재생합니다. 미리보기 정보 조회와 유휴 상태에서는 재생하지 않습니다.
- 통화, 앱 강제 종료, 메모리 회수 등으로 작업이 중단될 수 있으며 백그라운드 유지 시간은 보장하지 않습니다. 무음 유지가 꺼져 있거나 실패하면 유한한 백그라운드 완료 시간을 사용하고 만료 시 취소합니다. 강제 종료 후 작업 복원은 구현하지 않았습니다.
- 공유 확장은 사용자 선택을 딥링크로 본 앱에 전달해 다운로드를 바로 시작합니다. 시스템이 앱 열기를 허용하지 않으면 App Group 대기열에 저장하며, 이 경우 사용자가 앱을 열면 다운로드가 시작됩니다. 후속 대기열 작업도 앱이 전경일 때 시작합니다.
- Island 축약 화면에는 진행률, 펼친 화면에는 진행 바와 로그 2줄을 표시합니다. 탭하면 전체 로그 화면을 엽니다. 로그 업데이트는 최대 초당 1회이며 진행률이 없으면 대기 표시, 30초 이상 업데이트가 없으면 오래된 상태 안내를 표시합니다. 로그에서 HTTP URL을 가리지만 공유 전 내용을 확인하세요.
- 무음 오디오를 단순 실행 유지 목적으로 사용하는 설계는 App Store 배포 적합성을 보장하지 않습니다. [Apple 심사 지침 2.5.4](https://developer.apple.com/app-store/review/guidelines/#software-requirements)는 백그라운드 모드를 해당 목적에 맞게 사용하도록 요구합니다.
- 취소는 다운로드 콜백과 단계 사이에서 확인합니다. 응답 대기 또는 JavaScript 실행 중에는 즉시 중단되지 않을 수 있습니다. 파일 결합 단계에서 취소하면 결과를 보관함에 넣지 않습니다.
- 설정의 업데이트 버튼은 PyPI 최신 wheel을 내려받아 게시된 SHA-256과 대조한 뒤 `Application Support/YTDLPEngine/<버전>`에 원자적으로 설치합니다. 다음 앱 실행에서 이 패키지를 번들보다 먼저 불러옵니다. 로드에 실패하면 활성 표식을 제거하고 번들 버전으로 되돌아갑니다.
- 추가 인자는 셸로 전달하지 않습니다. `--socket-timeout`, `--retries`, `--fragment-retries`, `--user-agent`, `--referer`, `--add-header`만 yt-dlp Python API 옵션으로 변환합니다.

## 테스트

```sh
python3 -m pip install --target Python/app --no-deps -r requirements-ios.txt
PYTHONPATH=Python/app python3 -m unittest discover -s tests -v
```

Actions에는 iOS 26+ 시뮬레이터를 골라 XCTest 5개를 실행하는 단계도 포함합니다. 이 환경에서는 실행하지 않았습니다.

네이티브 브리지 `_ios_bridge`는 테스트에서 대체합니다. 실제 HTTP 전송은 yt-dlp가 수행하고 네트워크 콘텐츠는 로컬 생성 테스트 데이터만 사용합니다.

## 기기에서 확인할 순서

1. 앱 실행, 화면 회전, 다크 모드, 큰 텍스트 크기
2. 본인이 제작한 영상 링크의 정보 확인
3. MP4 720p 이하 및 M4A 다운로드, 소리와 재생 확인
4. 분리된 영상/오디오의 MP4 병합과 취소
5. 파일 앱 → 나의 iPhone → yt-dlp GUI와 공유 저장
6. 앱 종료 후 보관함 표시, 파일 삭제
7. 네트워크 끊김, 제공되지 않는 화질, 잘못된 링크
8. Safari·YouTube 공유 시트에서 앱 선택 → 대기열 추가 → 앱을 직접 열어 다운로드 확인
9. Dynamic Island 축약·확장 및 잠금 화면 진행률·로그, Island 탭으로 로그 열기
10. 화면 잠금 및 다른 앱 전환 후 실제 파일 증가 확인, 완료·실패·취소 시 오디오 세션 종료
11. 다른 음악 앱과 동시 실행, 통화 인터럽트·재개, 설정 끄기, 앱 강제 종료 시 오래된 Live Activity 안내
12. 설정에서 yt-dlp 업데이트 → 앱 완전 종료·재실행 → 현재 버전 확인 → 번들 버전 복구
13. 자막 언어 우선순위, 자동 자막 끄기, 형식 ID 지정 및 허용되지 않은 추가 인자 오류 확인

## 구조

| 경로 | 역할 |
| --- | --- |
| `App/` | SwiftUI 화면, 상태, 파일 보관, AVFoundation 병합 |
| `App/Native/` | CPython C API와 JavaScriptCore 브리지 |
| `Python/app/downloader.py` | yt-dlp 호출과 형식 선택 |
| `Python/app/ios_jsc.py` | 번들 EJS와 JavaScriptCore 연결 |
| `project.yml` | XcodeGen 설정 |
| `tools/bootstrap.py` | iOS Python 런타임과 의존성 설치 |
| `.github/workflows/ios.yml` | 미서명 IPA 및 시뮬레이터 빌드 |
| `Design/` | 디자인 미리보기 |
| `tests/` | 엔진 검증 |
| `Shared/` | App Group 대기열과 Live Activity 상태 |
| `ShareExtension/` | 공유 시트 화면 |
| `LiveActivityExtension/` | Dynamic Island·잠금 화면 위젯 |
| `NativeTests/` | 링크·대기열·Activity 상태 XCTest 5개(미실행) |

## 참고와 라이선스

앱 코드에는 MIT 라이선스를 적용합니다. 의존성의 라이선스는 각각 유지됩니다. yt-dlp와 EJS는 Unlicense, CPython은 PSF 라이선스, BeeWare 지원 도구는 해당 프로젝트의 라이선스, certifi의 인증서 번들은 MPL 2.0 등 자체 라이선스를 따릅니다. bootstrap이 의존성의 라이선스와 패키지 메타데이터를 보존하며, 배포 시 Python 지원 패키지의 OpenSSL 등 추가 의존성 고지도 확인해야 합니다.

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Python 3.13 on iOS와 공식 빌드 단계](https://docs.python.org/3.13/using/ios.html)
- [BeeWare Python Apple Support](https://github.com/beeware/Python-Apple-support)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [yt-dlp JavaScript 지원](https://github.com/yt-dlp/yt-dlp/wiki/EJS)
