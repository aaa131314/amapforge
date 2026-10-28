ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AMapForge

AMapForge_FILES = main.m RootViewController.m ForgeRunner.m
AMapForge_FRAMEWORKS = UIKit Foundation
AMapForge_CFLAGS = -fobjc-arc
AMapForge_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
