# yt-dlp GUI · iOS 0.3.0

iOS 26용 SwiftUI 앱입니다. Liquid Glass 카드, 시스템 탭·도구 막대와 SF Symbols를 사용해 표준 iOS 앱 구조를 따릅니다.

## 포함된 기능

- 링크 입력과 시스템 붙여넣기 버튼
- 제목, 제작자, 길이, 썸네일 확인
- 동영상 / 오디오 저장 유형 선택
- 최고 품질 / 2160p / 1440p / 1080p / 720p / 480p / 360p / 직접 입력 화질 상한
- 파일 형식·확장자·화질을 yt-dlp CLI 인수로 변환하는 단일 엔진
- 출력 포맷을 자동/MP4/MOV/WebM/MKV 또는 오디오 포맷으로 선택하고 직접 확장자 입력 가능
- 언어 및 자동 생성 자막 옵션, 미디어와 자막 함께 공유
- 메인 화면의 커스텀 명령어 입력. 인수가 있으면 앱의 다른 다운로드 옵션보다 우선
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

Python 엔진·패키징 테스트 25개가 통과했습니다. 실제 yt-dlp와 로컬 HTTP 서버를 사용하여 영상/오디오 원본 전송, 자막 저장, 확장자·화질 선택, 커스텀 인수 우선순위, 단일 추출 호출, 전송 중 취소, 잘못된 명령 이후 복구를 검증합니다. 다운로드 테스트는 외부 프로세스를 차단한 상태로 실행합니다.

Xcode 컴파일은 GitHub Actions에서 확인하며, iPhone 설치·실제 YouTube 챌린지 실행·공유 확장·Live Activity·백그라운드 실행은 별도 기기 검증이 필요합니다. `VALIDATION.md`에 로컬 검증 범위를 기록합니다.

## 맥 없이 GitHub Actions로 빌드

1. 새 GitHub 저장소에 이 폴더의 **내용**을 업로드합니다. `App`, `Python`, `tools`, `.github`가 저장소 루트에 있어야 합니다. `.github`도 업로드해야 합니다.
2. 저장소의 **Actions → iOS build → Run workflow**를 실행합니다. `main`으로 push해도 실행됩니다.
3. 빌드가 성공하면 `yt-dlp-GUI-unsigned-IPA` 결과물을 받습니다.
4. 결과물은 **미서명 IPA**입니다. 파일을 받는 것만으로 iPhone에 설치할 수 없으며, 본인 기기용 서명과 설치 도구가 별도로 필요합니다. 서명 도구는 앱뿐 아니라 포함된 Python 확장 프레임워크도 서명해야 합니다. 공유·Live Activity 확장도 서명해야 하며 앱과 공유 확장에 동일한 App Group 권한을 포함해야 합니다.

기본 runner는 `macos-15`이며, 설치된 Xcode 중 26 이상을 자동으로 선택합니다. 해당 runner에 Xcode 26 이상이 없으면 명확한 오류와 함께 종료하므로, 그때 사용 가능한 더 최신 macOS runner로 바꿉니다.

Apple 계정, 인증서, 프로비저닝 프로파일은 포함하지 않습니다.

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

- 모든 다운로드는 **UI → CLI 인수 배열 → `yt_dlp.parse_options` → `YoutubeDL.extract_info(download=True)`** 한 경로를 사용합니다. 정보를 추출한 뒤 같은 URL을 다시 추출하거나 내부 스트림 목록을 직접 정렬하지 않습니다. 별도의 정보 확인 버튼은 `download=False`를 사용합니다.
- 기본 동영상 선택은 `-f b`(영상과 소리가 합쳐진 최상 원본), 오디오는 `-f ba`(오디오 전용 최상 원본)입니다. 예를 들어 MP4·720p 이하는 `-f 'b[ext=mp4][height<=720]'`입니다. 화질은 보장값이 아닌 상한입니다.
- 확장자는 `[ext=...]` 필터입니다. 확장자만 바꾸거나 다른 포맷으로 변환하지 않습니다. 요청한 원본이 없으면 오류를 표시합니다. 자동 선택은 실제 원본 확장자로 저장합니다.
- **기존 AVFoundation 분리 스트림 병합 경로를 제거했습니다.** 따라서 분리 영상/오디오만 있는 링크, 분리 스트림 전용 1080p/4K, FFmpeg 변환은 이 단순 엔진에서 지원하지 않습니다. 이 제한 때문에 일부 링크는 이전 버전보다 낮은 화질만 가능하거나 다운로드가 실패할 수 있습니다.
- 커스텀 명령은 `-f worst` 또는 `yt-dlp -f 'b[height<=720]'`처럼 입력합니다. 링크는 링크 입력란에 넣습니다. 선택 UI와 자막 설정을 대체하며 `-t`도 직접 입력할 수 있지만 FFmpeg/외부 실행 파일을 요구하면 명시적으로 실패합니다. 셸 명령 연결·파이프는 실행하지 않습니다.
- 앱이 진행률·로그·취소·출력 디렉터리와 파일명을 관리합니다. `-o`/`-P`는 앱의 임시 저장 경로로 대체합니다. 다중 미디어, 라이브, 시뮬레이션 등 파일을 만들지 않는 명령은 보관함 다운로드로 완료되지 않습니다. 커스텀 인수 원문은 자격 증명 노출을 피하기 위해 로그에 기록하지 않습니다.
- 자막은 yt-dlp의 `--write-subs`, `--write-auto-subs`, `--sub-langs`로 다운로드합니다. 현재 보관함은 미디어당 자막 하나를 저장하며 여러 자막이 있으면 첫 파일만 저장하고 로그로 알립니다.
- 예전 공유 대기열의 `yt-dlp 기본 사용` 요청은 `-f b` 명령으로 변환합니다. 새 공유 화면에서는 동영상/오디오 및 화질만 선택합니다.
- YouTube는 yt-dlp의 추출기와 번들 EJS를 사용합니다. 제공자 등록과 EJS 버전 검증은 통과했지만 JavaScriptCore 호환성과 실제 서비스 상태에 따라 다운로드가 달라질 수 있습니다.
- 무음 오디오 설정은 기본 켜짐입니다. 다운로드 시작 시 16 kHz 모노 PCM 무음 WAV를 반복 재생하고 완료·실패·취소 시 종료합니다. 통화, 앱 강제 종료, 메모리 회수 등으로 작업이 중단될 수 있으며 백그라운드 유지 시간은 보장하지 않습니다.
- 공유 확장은 링크·저장 유형·화질을 본 앱으로 전달합니다. 시스템이 앱 열기를 허용하지 않으면 App Group 대기열에 저장합니다.
- Dynamic Island와 잠금 화면에는 진행률과 최근 로그를 표시합니다. 로그에서 HTTP URL을 가리지만 공유 전 내용을 확인하세요.
- 설정의 업데이트 버튼은 PyPI 최신 wheel을 SHA-256으로 검증해 설치하고, 로드 실패 시 번들 버전으로 되돌립니다.

## 테스트

```sh
python3 -m pip install --target Python/app --no-deps -r requirements-ios.txt
PYTHONPATH=Python/app python3 -m unittest discover -s tests -v
```

Actions는 기기 앱과 시뮬레이터 앱을 빌드합니다. `NativeTests`의 XCTest는 별도 실행이 필요합니다.

네이티브 브리지 `_ios_bridge`는 테스트에서 대체합니다. 실제 HTTP 전송은 yt-dlp가 수행하고 네트워크 콘텐츠는 로컬 생성 테스트 데이터만 사용합니다.

## 기기에서 확인할 순서

1. 앱 실행, 화면 회전, 다크 모드, 큰 텍스트 크기
2. 본인이 제작한 영상 링크의 정보 확인
3. MP4 720p 이하 및 M4A 다운로드, 소리와 재생 확인
4. 분리 스트림 명령의 명확한 오류 표시와 전송 중 취소
5. 파일 앱 → 나의 iPhone → yt-dlp GUI와 공유 저장
6. 앱 종료 후 보관함 표시, 파일 삭제
7. 네트워크 끊김, 제공되지 않는 화질, 잘못된 링크
8. Safari·YouTube 공유 시트에서 앱 선택 → 대기열 추가 → 앱을 직접 열어 다운로드 확인
9. Dynamic Island 축약·확장 및 잠금 화면 진행률·로그, Island 탭으로 로그 열기
10. 화면 잠금 및 다른 앱 전환 후 실제 파일 증가 확인, 완료·실패·취소 시 오디오 세션 종료
11. 다른 음악 앱과 동시 실행, 통화 인터럽트·재개, 설정 끄기, 앱 강제 종료 시 오래된 Live Activity 안내
12. 설정에서 yt-dlp 업데이트 → 앱 완전 종료·재실행 → 현재 버전 확인 → 번들 버전 복구
13. 직접 화질·확장자 입력, 커스텀 인수 우선순위, 잘못된 인수 입력 후 재시도

## 구조

| 경로 | 역할 |
| --- | --- |
| `App/` | SwiftUI 화면, 상태, 파일 보관 |
| `App/Native/` | CPython C API와 JavaScriptCore 브리지 |
| `Python/app/downloader.py` | CLI 인수 생성과 단일 yt-dlp 실행 |
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
