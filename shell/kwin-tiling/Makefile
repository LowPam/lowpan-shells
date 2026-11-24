PROJECT_NAME = krohnkite
# versão fixa: desde 2026-11-21 o motor mora no repositório principal, que não tem as tags do fork (saía vazia)
PROJECT_VER  = 0.9.9.3
# revisão do Krohnkite em que o fork se baseia (fixa: o git daqui é o do repositório principal)
PROJECT_REV  = 9f3a066

KWINPKG_FILE = $(PROJECT_NAME)-$(PROJECT_VER).kwinscript
KWINPKG_DIR  = pkg

KWIN_META    = $(KWINPKG_DIR)/metadata.json
KWIN_QML     = $(KWINPKG_DIR)/contents/ui/main.qml
NODE_SCRIPT  = $(PROJECT_NAME).js
NODE_FILES   = $(NODE_SCRIPT) package-lock.json

SRC = $(shell find src -name "*.ts")

all: $(KWINPKG_DIR)

clean:
	@rm -rvf $(KWINPKG_DIR)
	@rm -vf $(NODE_FILES)

install: package
	kpackagetool6 -t KWin/Script -s $(PROJECT_NAME) \
		&& kpackagetool6 -t KWin/Script -u $(KWINPKG_FILE) \
		|| kpackagetool6 -t KWin/Script -i $(KWINPKG_FILE)

uninstall:
	kpackagetool6 -t kwinscript -r $(PROJECT_NAME)

package: $(KWINPKG_FILE) package_json

test: $(NODE_SCRIPT) package_json
	npm test

run: $(KWINPKG_DIR)
	bin/load-script.sh "$(KWIN_QML)" "$(PROJECT_NAME)-test"
	@find "$(KWINPKG_DIR)" '(' -name "*.qmlc" -o -name "*.jsc" ')' -delete

stop:
	bin/load-script.sh "unload" "$(PROJECT_NAME)-test"

$(KWINPKG_FILE): $(KWINPKG_DIR)
	@rm -f "$(KWINPKG_FILE)"
	@7z a -tzip $(KWINPKG_FILE) ./$(KWINPKG_DIR)/*

$(KWINPKG_DIR): remove_meta
$(KWINPKG_DIR): $(KWIN_META)
$(KWINPKG_DIR): $(KWIN_QML)
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/ui/config.ui
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/ui/popup.qml
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/ui/droppreview.qml
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/ui/shortcuts.qml
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/code/main.js
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/code/script.js
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/config/main.xml
# traduções da tela de configuração (2026-11-22): o KWin carrega contents/locale/<idioma>/LC_MESSAGES/<id do script>.mo
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/locale/pt_BR/LC_MESSAGES/lowpan-tiling.mo
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/locale/pt/LC_MESSAGES/lowpan-tiling.mo
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/locale/ru/LC_MESSAGES/lowpan-tiling.mo
$(KWINPKG_DIR): $(KWINPKG_DIR)/contents/locale/zh/LC_MESSAGES/lowpan-tiling.mo
	@touch $@

$(KWIN_META): res/metadata.json
	@mkdir -vp `dirname $(KWIN_META)`
	@touch "$(KWIN_META)"
	sed "s/\$$VER/$(PROJECT_VER)/" $< \
		| sed "s/\$$REV/$(PROJECT_REV)/" \
		> $(KWIN_META)

remove_meta:
	@rm -f "$(KWIN_META)"

$(KWIN_QML): res/main.qml

$(KWINPKG_DIR)/contents/ui/config.ui: res/config.ui
$(KWINPKG_DIR)/contents/ui/popup.qml: res/popup.qml
$(KWINPKG_DIR)/contents/ui/droppreview.qml: res/droppreview.qml
$(KWINPKG_DIR)/contents/ui/shortcuts.qml: res/shortcuts.qml
$(KWINPKG_DIR)/contents/code/script.js: $(NODE_SCRIPT)
$(KWINPKG_DIR)/contents/code/main.js: res/main.js
$(KWINPKG_DIR)/contents/config/main.xml: res/config.xml
$(KWINPKG_DIR)/contents/locale/pt_BR/LC_MESSAGES/lowpan-tiling.mo: translations/pt_BR.po
	@mkdir -p `dirname $@` && msgfmt -o $@ $<
$(KWINPKG_DIR)/contents/locale/pt/LC_MESSAGES/lowpan-tiling.mo: translations/pt_BR.po
	@mkdir -p `dirname $@` && msgfmt -o $@ $<
$(KWINPKG_DIR)/contents/locale/ru/LC_MESSAGES/lowpan-tiling.mo: translations/russian.po
	@mkdir -p `dirname $@` && msgfmt -o $@ $<
$(KWINPKG_DIR)/contents/locale/zh/LC_MESSAGES/lowpan-tiling.mo: translations/chinese.po
	@mkdir -p `dirname $@` && msgfmt -o $@ $<
$(KWINPKG_DIR)/%:
	@mkdir -vp `dirname $@`
	@cp -v $< $@

$(NODE_SCRIPT): $(SRC)
	npm install --save-dev
	npm run tsc --

package_json: package.json
	sed -i 's/"version": [^,]*/"version": "$(PROJECT_VER)"/' package.json

.PHONY: all clean install package test run stop package_json
