.DEFAULT_GOAL := help

.PHONY: bootstrap help FORCE

bootstrap:
	@command -v pwsh >/dev/null 2>&1 || { \
		echo "PowerShell 7.6 or later is required."; \
		exit 1; \
	}
	@pwsh -NoLogo -NoProfile -NonInteractive -File ./build.ps1 -Task install

help:
	@command -v pwsh >/dev/null 2>&1 || { \
		echo "PowerShell 7.6 or later is required."; \
		exit 0; \
	}
	@pwsh -NoLogo -NoProfile -NonInteractive -File ./build.ps1 -Task help

Makefile: ;

%: FORCE
	@command -v pwsh >/dev/null 2>&1 || { \
		echo "PowerShell 7.6 or later is required."; \
		exit 1; \
	}
	@pwsh -NoLogo -NoProfile -NonInteractive -File ./build.ps1 -Task "$@"

FORCE:
