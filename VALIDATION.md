# 명령어 기반 엔진 검증

검증일: 2026-11-14. Linux, Python, requirements-ios.txt의 고정 의존성 사용.

- `python -m unittest discover -s tests -v`: 28개 통과.
- 실제 yt-dlp 로컬 HTTP 영상/오디오/자막 전송과 바이트 검증. 외부 프로세스 호출 차단.
- 다운로드당 추출 호출 한 번, UI 옵션 → CLI 필터, 커스텀 명령 우선순위.
- 미지원 확장자/화질, 분리 스트림 병합, 라이브, 연령 제한, 잘못된 명령, 결과 파일 없음 처리.
- 시작 전/전송 중 취소, 명령 파싱 오류 뒤 재시도.
- 로그 URL 가림, 엔진 wheel SHA-256 검증, EJS 제공자 등록 및 스크립트 로드.
- 기기·시뮬레이터 Python 확장 모듈 패키징 테스트.

로컬 환경에는 Xcode가 없습니다. iOS 컴파일은 GitHub Actions로 별도 확인합니다. 실제 iPhone 설치, YouTube/Instagram 등 외부 서비스 다운로드, JavaScriptCore 챌린지 실행, Live Activity와 백그라운드 오디오는 미검증입니다. 로컬 테스트 성공은 실기기 성공을 보장하지 않습니다.

회귀 검증: 720p 단일 원본과 1080p 분리 트랙이 함께 제공되면 최고 품질은 1080p 영상과 오디오를 내려받습니다. AVFoundation의 실제 기기 병합은 별도 확인이 필요합니다.
