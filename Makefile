PROGS := sysctl lua kdv filt vmmap
CC    ?= clang
STRIP ?= strip

TARGET_SYSROOT ?= $(shell xcrun -sdk iphoneos --show-sdk-path)

CFLAGS  += -Os -isysroot $(TARGET_SYSROOT) -miphoneos-version-min=14.0 -arch arm64
LDLFAGS += -lSystem

all: $(PROGS)

clean:
	rm -f $(PROGS)
	$(MAKE) -C lua-5.3.6 clean

lua: always_rebuild
	$(MAKE) -C lua-5.3.6 iphoneos
	cp lua-5.3.6/src/lua .
	ldid -Sentitlements.xml -Kdev_certificate.p12 -Upassword $@

%: %.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< -o $@
	$(STRIP) $@
	ldid -Sentitlements.xml -Kdev_certificate.p12 -Upassword $@

.PHONY: all clean always_rebuild
