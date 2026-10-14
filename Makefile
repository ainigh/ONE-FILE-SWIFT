# CountdownOverlay — needs Apple's command line tools with Swift 6 (or an Xcode 16+).
#   make build    compile (release) into .build/
#   make app      assemble + ad-hoc sign build/CountdownOverlay.app (and the .zip)
#   make run      build the app and open it
#   make install  install into ~/Applications (same place install.sh uses) and open it
#   make test     run the CountdownCore test suite
#   make clean

NAME := CountdownOverlay
APP  := build/$(NAME).app
DEST := $(HOME)/Applications/$(NAME).app

.PHONY: build app run install test clean

build:
	swift build -c release --product $(NAME)

app:
	scripts/make-app.sh

run: app
	open $(APP)

install: app
	pkill -x $(NAME) 2>/dev/null; sleep 1; true
	mkdir -p $(HOME)/Applications
	rm -rf "$(DEST)"
	ditto $(APP) "$(DEST)"
	open "$(DEST)"
	@echo "Installed to $(DEST)"

test:
	swift test

clean:
	rm -rf ./build ./.build
