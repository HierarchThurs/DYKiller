#
#  DYKiller —— 抖音 UI 增强插件（模块化 hook 框架）
#

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = Aweme

DK_VERSION := $(shell awk -F': *' '$$1 == "Version" { print $$2; exit }' control)
DYKILLER_PACKAGE_SCHEME ?= $(if $(THEOS_PACKAGE_SCHEME),$(THEOS_PACKAGE_SCHEME),rootful)

ifeq ($(strip $(DK_VERSION)),)
$(error Missing Version in control)
endif

ifeq ($(DYKILLER_PACKAGE_SCHEME),rootful)
unexport THEOS_PACKAGE_SCHEME
DYKILLER_PACKAGE_SUFFIX = arm-rootful
else ifeq ($(DYKILLER_PACKAGE_SCHEME),rootless)
export THEOS_PACKAGE_SCHEME = rootless
DYKILLER_PACKAGE_SUFFIX = arm64-rootless
else ifeq ($(DYKILLER_PACKAGE_SCHEME),roothide)
export THEOS_PACKAGE_SCHEME = roothide
DYKILLER_PACKAGE_SUFFIX = arm64e-roothide
else
$(error Unsupported DYKILLER_PACKAGE_SCHEME: $(DYKILLER_PACKAGE_SCHEME))
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYKiller
DYKiller_FILES = $(shell find src -type f \( -name '*.m' -o -name '*.mm' -o -name '*.x' -o -name '*.xm' -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) | sort)
DYKiller_INCLUDE_DIRS = $(shell find src -type d | sort)
DYKiller_CFLAGS = -fobjc-arc -w $(addprefix -I,$(DYKiller_INCLUDE_DIRS)) -DDK_VERSION=@\"$(DK_VERSION)\"
DYKiller_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics
DYKiller_LDFLAGS += -lz
DYKiller_LOGOS_DEFAULT_GENERATOR = internal

export THEOS_STRICT_LOGOS = 0
export ERROR_ON_WARNINGS = 0
export LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@rm -rf .theos packages

package-rootful::
	@rm -rf .theos
	@$(MAKE) all package DYKILLER_PACKAGE_SCHEME=rootful FINALPACKAGE=1

package-rootless::
	@rm -rf .theos
	@$(MAKE) all package DYKILLER_PACKAGE_SCHEME=rootless FINALPACKAGE=1

package-roothide::
	@if [ -d "$(THEOS_VENDOR_MODULE_PATH)/roothide" ] || [ -d "$(THEOS_MODULE_PATH)/roothide" ]; then \
		rm -rf .theos; \
		$(MAKE) all package DYKILLER_PACKAGE_SCHEME=roothide FINALPACKAGE=1; \
	elif [ "$$GITHUB_ACTIONS" = "true" ]; then \
		echo "error: roothide Theos package scheme is required in CI."; \
		exit 1; \
	else \
		echo "warning: roothide Theos package scheme not found; skipped roothide package."; \
	fi

all-packages::
	@rm -rf packages
	@mkdir -p packages
	@$(MAKE) package-rootful FINALPACKAGE=1
	@$(MAKE) package-rootless FINALPACKAGE=1
	@$(MAKE) package-roothide FINALPACKAGE=1

before-package::
ifneq ($(THEOS_PACKAGE_INSTALL_PREFIX),)
	@mkdir -p "$(_THEOS_SCHEME_STAGE)"
endif

after-package::
	@mkdir -p packages
	@DEB=$$(cat .theos/last_package 2>/dev/null || true); \
	 OUT="packages/DYKiller_$(DK_VERSION)_$(DYKILLER_PACKAGE_SUFFIX).deb"; \
	 if [ -n "$$DEB" ] && [ -f "$$DEB" ]; then mv -f "$$DEB" "$$OUT"; fi
	@if [ "$(DYKILLER_PACKAGE_SCHEME)" = "rootful" ]; then \
		DYLIB=$$(find .theos/obj -name 'DYKiller.dylib' 2>/dev/null | head -1); \
		if [ -n "$$DYLIB" ]; then cp -f "$$DYLIB" packages/DYKiller.dylib; fi; \
	fi
	@echo "==> 成品: packages/DYKiller_$(DK_VERSION)_$(DYKILLER_PACKAGE_SUFFIX).deb"
