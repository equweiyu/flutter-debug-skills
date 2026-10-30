DART_FILES := $(shell find skills tests tool -type f -name '*.dart')
NODE_FILES := $(shell find skills -type f -name '*.mjs')

.PHONY: check validate format analyze test scripts whitespace

check: validate format analyze test scripts whitespace

validate:
	dart run tool/validate_repository.dart

format:
	dart format --output=none --set-exit-if-changed $(DART_FILES)

analyze:
	dart analyze $(DART_FILES)

test:
	dart tests/capture_app_logs_test.dart
	dart tests/vm_service_rpc_test.dart
	dart tests/android_database_export_test.dart
	dart tests/ios_database_skill_test.dart
	dart tests/database_mutation_policy_test.dart

scripts:
	@for file in $(NODE_FILES); do node --check "$$file"; done
	@node skills/flutter-live-control/scripts/vm_service_rpc.mjs --help >/dev/null

whitespace:
	git diff --check
