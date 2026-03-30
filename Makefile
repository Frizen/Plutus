.PHONY: setup test lint

setup:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit
	@echo "✓ Git hooks installed. Run 'make lint' or 'make test' manually."

test:
	xcodebuild test \
	  -scheme ExpenseCapture \
	  -destination 'platform=iOS Simulator,name=iPhone 17' \
	  -only-testing:ExpenseCaptureTests \
	  -quiet

lint:
	swiftlint lint --config .swiftlint.yml
