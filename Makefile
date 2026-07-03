.PHONY: native-build native-run native-test native-clean electron-run electron-install electron-clean clean

# --- Native (Swift/AppKit) ---

native-build:
	swift build -c release --package-path native
	native/build-app.sh

native-run: native-build
	open native/build/*.app

# Swift Testing's Testing.framework (and its lib_TestingInterop.dylib) live under CLT
# paths that `swift test` doesn't search or rpath by default without Xcode.app
# installed. See native/README.md "Toolchain notes" for why these flags are needed.
TESTING_FRAMEWORK_DIR := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TESTING_LIB_DIR := /Library/Developer/CommandLineTools/Library/Developer/usr/lib

native-test:
	swift test --package-path native \
		-Xswiftc -F -Xswiftc $(TESTING_FRAMEWORK_DIR) \
		-Xlinker -F -Xlinker $(TESTING_FRAMEWORK_DIR) \
		-Xlinker -rpath -Xlinker $(TESTING_FRAMEWORK_DIR) \
		-Xlinker -rpath -Xlinker $(TESTING_LIB_DIR)

native-clean:
	rm -rf native/.build native/build

# --- Electron POC (legacy, kept for comparison) ---

electron-install:
	$(MAKE) -C electron-poc install

electron-run:
	$(MAKE) -C electron-poc start

electron-clean:
	$(MAKE) -C electron-poc clean

# --- Both ---

clean: native-clean electron-clean
