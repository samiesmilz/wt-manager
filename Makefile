# wt-manager - what am I in the middle of, and what is it costing me?
#
# `make install` puts wt-manager.app in /Applications, registers it as a login item,
# and links the CLI onto PATH from inside the bundle. One installed artifact
# serves both surfaces, so the menu bar and the terminal can never be running
# different versions of the engine.

# A Command Line Tools newer than Xcode (here: Swift 6.4 beside Xcode's 6.3.2)
# hands Xcode's compiler the CLT SDK when nothing names one, and a fresh build
# dies compiling Package.swift. Naming the developer directory xcode-select
# already chose keeps the compiler and SDK a matched pair; where they already
# match, this changes nothing. A cached .build hides the problem entirely.
export DEVELOPER_DIR ?= $(shell xcode-select -p)

APP      := app/wt-manager.app
DEST     := /Applications/wt-manager.app
BUNDLE   := com.samiesmilz.wtmanager
AGENT    := $(HOME)/Library/LaunchAgents/$(BUNDLE).plist
BINDIR   := $(HOME)/.local/bin
LSREG    := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: help build bundle install uninstall run cli check clean snapshots stop start login-on login-off

help:
	@echo "make bundle     build wt-manager.app"
	@echo "make install    install to /Applications, run at login, link the CLI"
	@echo "                LOGIN=0 make install  installs without the login item"
	@echo "make stop       quit the app and keep it from returning until make start or next login"
	@echo "make start      launch it again"
	@echo "make login-off  stop launching it at login (leaves the app installed)"
	@echo "make login-on   launch it at login again"
	@echo "make cli        link only the CLI (no app)"
	@echo "make uninstall  remove all of it"
	@echo "make run        run the app from the checkout"
	@echo "make check      exercise the engine without installing"
	@echo "make snapshots  render the window in both appearances to app/.build/snapshots"

build:
	@swift build -c release --package-path app

bundle:
	@CONFIG=release app/Scripts/bundle.sh

# Every subcommand, against THIS copy of the engine - not whatever `wt-manager` on
# PATH happens to point at. The symlink points into the installed bundle, so a
# check that ran `wt-manager` would test the previously installed build and pass while
# the code in front of you is broken. That is exactly how a missing method
# shipped.
check:
	@python3 -c "import ast; [ast.parse(open(f).read()) for f in ('wtmanager.py','mascot.py')]" \
		&& echo "  parses"
	@python3 -m unittest -q test_wtmanager
	@swift test --package-path app
	@python3 mascot.py - > /dev/null && echo "  character exports"
	@python3 wtmanager.py --here --json > /dev/null && echo "  default view"
	@python3 wtmanager.py --here agent --no-size > /dev/null && echo "  agent"
	@python3 wtmanager.py --here reap > /dev/null && echo "  reap (dry run)"
	@python3 wtmanager.py --here clean --list-unknown > /dev/null && echo "  clean"
	@python3 wtmanager.py --here doctor > /dev/null && echo "  doctor"
	@python3 wtmanager.py --here size > /dev/null && echo "  size"
	@echo "engine ok"

install: bundle
	@echo "==> installing to /Applications"
	@# launchctl unload only stops the copy it manages. One started any other
	@# way - double-clicked, an old login item - would survive and be joined by
	@# a second, giving two status items at once.
	@pkill -f 'wt-manager\.app/Contents/MacOS/wt-manager' 2>/dev/null || true
	@if [ -e "$(DEST)" ]; then rm -r "$(DEST)"; fi
	@cp -R $(APP) $(DEST)
	@# Replacing a bundle in place does not invalidate the LaunchServices icon
	@# cache, so re-register to force a re-read.
	@$(LSREG) -f $(DEST) 2>/dev/null || true
	@# The checkout copy declares the same bundle identifier, so leaving it
	@# behind gives LaunchServices two records for one app and either may win.
	@$(LSREG) -u "$(CURDIR)/$(APP)" 2>/dev/null || true
	@if [ -e "$(CURDIR)/$(APP)" ]; then rm -r "$(CURDIR)/$(APP)"; fi
	@$(MAKE) --no-print-directory cli DEST_ENGINE=$(DEST)/Contents/Resources/engine/wtmanager.py
	@# An always-running agent is a choice, not a given. LOGIN=0 installs the
	@# app and the CLI and leaves launching to `make start` or a double-click.
	@if [ "$(LOGIN)" = "0" ]; then \
		echo "==> not registering a login item (LOGIN=0); \`make start\` launches it"; \
		launchctl unload $(AGENT) 2>/dev/null || true; rm -f $(AGENT); \
		open $(DEST); \
	else \
		$(MAKE) --no-print-directory login-on; \
	fi
	@# Smoke-test what was actually installed. The app shells out to this exact
	@# file, and a failure here shows up as a traceback in the window rather
	@# than as a failed install, which is far harder to trace back to here.
	@printf "==> checking the installed engine... "
	@/usr/bin/python3 $(DEST)/Contents/Resources/engine/wtmanager.py --here agent --no-size \
		> /dev/null 2>/tmp/wt-manager-install-check.err \
		&& echo "ok" \
		|| { echo "FAILED"; tail -5 /tmp/wt-manager-install-check.err; exit 1; }
	@echo "==> running. Wity is on screen; the CLI is \`wt-manager\`."

# Linked from inside the bundle when installed, from the checkout otherwise, so
# `wt-manager` on PATH is always the same engine the menu bar is using.
DEST_ENGINE ?= $(CURDIR)/wtmanager.py
cli:
	@mkdir -p $(BINDIR)
	@ln -sf "$(DEST_ENGINE)" $(BINDIR)/wt-manager
	@echo "==> wt-manager -> $(DEST_ENGINE)"
	@case ":$$PATH:" in *":$(BINDIR):"*) ;; \
		*) echo "    note: $(BINDIR) is not on your PATH" ;; esac

# The login item. KeepAlive is false on purpose: quitting from the menu must
# quit, and launchd must not bring it back until the next login or `make start`.
login-on:
	@echo "==> registering login item"
	@mkdir -p $(HOME)/Library/LaunchAgents
	@/usr/libexec/PlistBuddy -c "Clear dict" \
		-c "Add :Label string $(BUNDLE)" \
		-c "Add :ProgramArguments array" \
		-c "Add :ProgramArguments:0 string $(DEST)/Contents/MacOS/wt-manager" \
		-c "Add :RunAtLoad bool true" \
		-c "Add :KeepAlive bool false" \
		-c "Add :ProcessType string Interactive" \
		-c "Add :StandardOutPath string $(HOME)/Library/Logs/wt-manager.log" \
		-c "Add :StandardErrorPath string $(HOME)/Library/Logs/wt-manager.log" \
		$(AGENT) >/dev/null
	@launchctl unload $(AGENT) 2>/dev/null || true
	@launchctl load $(AGENT)

login-off:
	@launchctl unload $(AGENT) 2>/dev/null || true
	@if [ -e "$(AGENT)" ]; then rm "$(AGENT)"; fi
	@echo "==> no longer launched at login. it is still installed; \`make start\` runs it."

# Stop means stop: unload the agent so launchd forgets it for this session,
# then end every copy however it was started. `make start` or the next login
# brings it back.
stop:
	@launchctl unload $(AGENT) 2>/dev/null || true
	@pkill -f 'wt-manager\.app/Contents/MacOS/wt-manager' 2>/dev/null || true
	@echo "==> stopped. \`make start\` runs it again$$( [ -e "$(AGENT)" ] && echo ', as will the next login' )."

start:
	@if [ -e "$(AGENT)" ]; then launchctl load $(AGENT) 2>/dev/null || open $(DEST); else open $(DEST); fi
	@echo "==> running."

uninstall:
	@pkill -f 'wt-manager\.app/Contents/MacOS/wt-manager' 2>/dev/null || true
	@launchctl unload $(AGENT) 2>/dev/null || true
	@if [ -e "$(AGENT)" ]; then rm "$(AGENT)"; fi
	@if [ -e "$(DEST)" ]; then rm -r "$(DEST)"; fi
	@if [ -L "$(BINDIR)/wt-manager" ]; then rm "$(BINDIR)/wt-manager"; fi
	@echo "==> removed the app, the login item and the CLI link."
	@echo "    deliberately left behind, so a reinstall picks up where it left off:"
	@printf "      %-40s %s\n" "~/.cache/wt-manager" "$$(du -sh $(HOME)/.cache/wt-manager 2>/dev/null | cut -f1 || echo 0B) of caches — \`python3 wtmanager.py config --clear-cache\` or rm -r"
	@printf "      %-40s %s\n" "~/.config/wt-manager/config.json" "your roots and base pins"
	@printf "      %-40s %s\n" "~/Library/Logs/wt-manager.log" "$$(du -sh $(HOME)/Library/Logs/wt-manager.log 2>/dev/null | cut -f1 || echo 0B) of log"

run: bundle
	@$(APP)/Contents/MacOS/wt-manager

# The window, rendered offscreen in light and dark, every section and the
# confirm sheet, from the engine's own envelope for the current repo. Needs no
# screen and no Screen Recording permission. The palette was once written
# without ever being seen rendered; this is how it gets seen.
snapshots:
	@swift build --package-path app
	@mkdir -p app/Resources && python3 mascot.py app/Resources/mascot.json > /dev/null
	@python3 wtmanager.py --here agent > app/.build/envelope.json
	@app/.build/debug/WTManager --snapshot app/.build/snapshots app/.build/envelope.json 2>/dev/null
	@ls app/.build/snapshots

clean:
	@swift package clean --package-path app 2>/dev/null || true
	@if [ -e "$(APP)" ]; then rm -r "$(APP)"; fi
