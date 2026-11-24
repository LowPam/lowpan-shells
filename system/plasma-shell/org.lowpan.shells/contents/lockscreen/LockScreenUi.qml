/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2026 Kristen McWilliam <kristen@kde.org>
    SPDX-FileCopyrightText: 2026 LowPan Shells

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// LowPan Shells — tela de bloqueio no visual da tela de login do LowPan (greeter/Tela.qml, PLANEJAMENTO §22.11).
// A lógica (authenticator, PasswordSync, mostrar/esconder a interface, tipos de autenticação, teclado) é a do
// LockScreenUi.qml do Plasma 6.8 (org.kde.plasma.desktop); só o desenho mudou: fundo desfocado com véu escuro,
// relógio HH:MM com os dois-pontos laranja, avatar redondo (inicial quando não há foto), senha em pílula e botões
// redondos de energia. Textos vêm do catálogo do KDE (plasma_shell_org.kde.plasma.desktop), então seguem o idioma.

pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.accessibility
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.workspace.keyboardlayout as Keyboards
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.ki18n

import org.kde.plasma.private.sessions
import org.kde.plasma.workspace.dbus as DBus
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // ── Paleta e medidas (as do greeter) ─────────────────────────────────────
    readonly property color corTexto: "#ffffff"
    readonly property color corTexto2: Qt.rgba(1, 1, 1, 0.72)
    readonly property color corTexto3: Qt.rgba(1, 1, 1, 0.56)
    readonly property color corPreenchimento: Qt.rgba(1, 1, 1, 0.2)
    readonly property color corPreenchimentoHover: Qt.rgba(1, 1, 1, 0.3)
    readonly property color corDestaque: "#ff9f0a"
    readonly property color corPerigo: "#ff6961"
    readonly property color corFoco: "#a8c7fa"
    readonly property string fonteTexto: "Inter"
    readonly property string fonteNumeros: "Rubik"
    readonly property string fonteIcones: "Material Symbols Rounded"
    readonly property real d: Math.max(1, Math.min(width / 1920, height / 1080) * 1.1)

    // Fontes do LowPan (contents/fonts = link para shell/assets/fonts, como no greeter)
    Instantiator {
        model: ["Light", "Regular", "Medium", "SemiBold", "Bold"].map(p => `inter/Inter-${p}`)
            .concat(["Medium", "SemiBold", "Bold"].map(p => `rubik/Rubik-${p}`))
        delegate: FontLoader {
            required property string modelData
            source: Qt.resolvedUrl(`../fonts/${modelData}.ttf`)
        }
    }

    function tr(contexto: string, texto: string): string {
        return KI18n.i18ndc("plasma_shell_org.kde.plasma.desktop", contexto, texto).replace("&", "")
    }

    // ── Lógica do KDE (sem mudanças) ─────────────────────────────────────────
    property bool expectingPrompt: false
    property bool showPrompt: false
    property bool semSenha: false          // autenticou sem pedir nada: mostra só "Desbloquear" (NoPasswordUnlock)
    property string pendingPassword

    function handleMessage(msg) {
        if (!msg) {
            return;
        }
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
        lockScreenRoot.uiVisible = true
    }

    function startLogin() {
        const password = campo.text
        botaoEntrar.forceActiveFocus();   // contorna QTBUG-55460 (fechar com um campo de texto focado)
        if (authenticator.pamTimeout) {
            lockScreenUi.pendingPassword = password
            campo.enabled = false
        } else {
            authenticator.respond(password)
        }
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) {
                return;
            }
            lockScreenUi.handleMessage(lockScreenUi.tr("@info:status", "Unlocking failed"));
            root.clearPassword();
            authenticator.startAuthenticating();
            notificationRemoveTimer.restart();
            tremer.restart();
        }
        function onSucceeded() {
            authenticator.stopAuthenticating()
            if (!lockScreenUi.expectingPrompt || authenticator.hadPrompt) {
                Qt.quit();
            } else {
                lockScreenUi.semSenha = true
                botaoDesbloquear.forceActiveFocus();
            }
        }
        function onInfoMessageChanged() { lockScreenUi.handleMessage(authenticator.infoMessage); }
        function onErrorMessageChanged() { lockScreenUi.handleMessage(authenticator.errorMessage); }
        function onPromptChanged() { lockScreenUi.handleMessage(authenticator.prompt); }
        function onPromptForSecretChanged() {
            campo.forceActiveFocus();
            if (lockScreenUi.showPrompt) {
                lockScreenUi.handleMessage(authenticator.promptForSecret);
            }
        }
        function onPamTimeoutChanged(): void {
            if (!authenticator.pamTimeout && lockScreenUi.pendingPassword.length > 0) {
                authenticator.respond(lockScreenUi.pendingPassword);
                lockScreenUi.pendingPassword = "";
                campo.enabled = true;
            }
        }
        function onNoninteractiveError(kind, auth) {
            lockScreenUi.handleMessage(auth.errorMessage);
            notificationRemoveTimer.restart();
        }
    }

    Connections {
        target: root
        function onClearPassword() {
            campo.forceActiveFocus()
            campo.text = "";
            campo.text = Qt.binding(() => PasswordSync.password);
        }
        function onNotificationRepeated() { tremer.restart(); }
    }

    SessionManagement { id: sessionManagement }

    // Suspender/Hibernar pelo powerdevil (2026-11-23): o SessionManagement chama o login1 direto de dentro do greeter, e
    // no desktop do dono esse pedido nunca chegava ao logind (nenhum "suspend requested" desde 17/11); o botão de ligar
    // passa pelo powerdevil e funciona. Se o powerdevil não responder, cai no caminho do KDE.
    function dormir(metodo: string): void {
        root.clearPassword();
        DBus.SessionBus.asyncCall({
            service: "org.kde.Solid.PowerManagement",
            path: "/org/kde/Solid/PowerManagement/Actions/SuspendSession",
            iface: "org.kde.Solid.PowerManagement.Actions.SuspendSession",
            member: metodo,
            arguments: []
        }, () => {}, () => {
            if (metodo === "suspendToDisk") sessionManagement.hibernate(); else sessionManagement.suspend();
        });
    }
    AccessibilityStatus { id: accessibilityStatus }
    KeyboardIndicator.KeyState { id: capsLockState; key: Qt.Key_CapsLock }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() { root.clearPassword(); }
    }

    component Icone: Text {
        property real tamanho: 24
        font.family: lockScreenUi.fonteIcones
        font.pixelSize: tamanho
        font.variableAxes: ({ "FILL": 1 })
        color: lockScreenUi.corTexto
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component Rotulo: Text {
        font.family: lockScreenUi.fonteTexto
        color: lockScreenUi.corTexto
        renderType: Text.NativeRendering
    }

    MouseArea {
        id: lockScreenRoot

        property bool uiVisible: false
        property bool seenPositionChange: false
        property bool blockUI: containsMouse && (campo.text.length > 0 || Keyboards.KWinVirtualKeyboard.visible)

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            uiVisible = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
                campo.forceActiveFocus();
            }
            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            authenticator.startAuthenticating();
        }

        Timer { // mantém o backend ativo enquanto a interface está à vista
            interval: 1000
            running: !authenticator.unlocked && parent.uiVisible
            repeat: true
            onTriggered: authenticator.startAuthenticating()
        }

        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        ScreenLocker.ActiveScreenMonitor {
            lockscreenState: ScreenLocker.LockscreenState
            window: lockScreenRoot.Window.window
            onActiveChanged: {
                if (!active) {
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Keys.onEscapePressed: {
            if (uiVisible) {
                uiVisible = false;
                if (Keyboards.KWinVirtualKeyboard.visible) {
                    Keyboards.KWinVirtualKeyboard.active = false;
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }

        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.veryLongDuration * 2 } }

        // ── Fundo: o papel do bloqueio do KDE, desfocado e escurecido como no greeter ──
        ShaderEffectSource {
            id: fonteFundo
            anchors.fill: parent
            sourceItem: wallpaper
            hideSource: true
            live: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: fonteFundo
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 48
            saturation: 0.1
        }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.04, 0.04, 0.06, lockScreenRoot.uiVisible ? 0.45 : 0.3)
            Behavior on color { ColorAnimation { duration: 400 } }
        }

        ListModel {
            id: users
            Component.onCompleted: {
                users.append({
                    name: kscreenlocker_userName,
                    realName: kscreenlocker_userName,
                    icon: kscreenlocker_userImage !== ""
                          ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                          : "",
                })
            }
        }

        QtObject { id: relogio; property date date: new Date() }
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: relogio.date = new Date()
        }

        ColumnLayout {
            id: coluna
            anchors.centerIn: parent
            spacing: 0

            // Relógio: HH:MM com os dois-pontos em laranja (sempre à vista, como no greeter)
            Row {
                Layout.alignment: Qt.AlignHCenter
                visible: config.alwaysShowClock && !(config.hideClockWhenIdle && !lockScreenRoot.uiVisible)
                Repeater {
                    model: [Qt.formatDateTime(relogio.date, "HH"), ":", Qt.formatDateTime(relogio.date, "mm")]
                    Text {
                        required property string modelData
                        text: modelData
                        font.family: lockScreenUi.fonteNumeros
                        font.pixelSize: Math.round(72 * lockScreenUi.d)
                        font.weight: Font.Bold
                        font.features: ({ "tnum": 1 })
                        font.letterSpacing: Math.round(-72 * lockScreenUi.d * 0.02)
                        color: modelData === ":" ? lockScreenUi.corDestaque : lockScreenUi.corTexto
                        renderType: Text.NativeRendering
                    }
                }
            }
            Rotulo {
                Layout.alignment: Qt.AlignHCenter
                visible: config.alwaysShowClock
                text: Qt.locale().name.startsWith("pt")
                    ? Qt.locale().toString(relogio.date, "dddd, d 'de' MMMM")
                    : Qt.locale().toString(relogio.date, "dddd, d MMMM")
                color: lockScreenUi.corTexto2
                font.pixelSize: Math.round(18 * lockScreenUi.d)
            }

            // Daqui para baixo só com a interface à vista (mexer o mouse / tecla), como no bloqueio do KDE
            ColumnLayout {
                id: formulario
                Layout.alignment: Qt.AlignHCenter
                spacing: 0
                opacity: lockScreenRoot.uiVisible ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutQuad } }

                // Avatar
                Item {
                    id: avatar
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(44 * lockScreenUi.d)
                    implicitWidth: Math.round(96 * lockScreenUi.d)
                    implicitHeight: implicitWidth

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: lockScreenUi.corPreenchimento
                        visible: foto.status !== Image.Ready
                        Rotulo {
                            anchors.centerIn: parent
                            text: String(kscreenlocker_userName).charAt(0).toUpperCase()
                            font.pixelSize: Math.round(40 * lockScreenUi.d)
                            font.weight: Font.DemiBold
                        }
                    }
                    Image {
                        id: foto
                        anchors.fill: parent
                        visible: false
                        // sem foto (ou foto que não abre), a mascote do LowPan — como no greeter (2026-11-23)
                        property bool semFoto: users.count === 0 || users.get(0).icon === ""
                        source: semFoto ? Qt.resolvedUrl("../mascote.png") : users.get(0).icon
                        onStatusChanged: if (status === Image.Error && !semFoto) semFoto = true
                        sourceSize: Qt.size(avatar.width * 2, avatar.height * 2)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        id: mascara
                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                        layer.enabled: true
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: foto.status === Image.Ready
                        source: foto
                        maskEnabled: true
                        maskSource: mascara
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                }

                Rotulo {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(14 * lockScreenUi.d)
                    text: kscreenlocker_userName
                    font.pixelSize: Math.round(20 * lockScreenUi.d)
                    font.weight: Font.DemiBold
                }

                // Campo de senha
                Rectangle {
                    id: caixa
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(18 * lockScreenUi.d)
                    implicitWidth: Math.round(300 * lockScreenUi.d)
                    implicitHeight: Math.round(40 * lockScreenUi.d)
                    visible: !lockScreenUi.semSenha && mostrarCampo
                    property bool mostrarCampo: true
                    radius: height / 2
                    color: campo.activeFocus ? lockScreenUi.corPreenchimentoHover : lockScreenUi.corPreenchimento
                    border.width: root.notification.length > 0 ? 1 : 0
                    border.color: lockScreenUi.corPerigo
                    Behavior on color { ColorAnimation { duration: 120 } }

                    transform: Translate { id: deslocamento }
                    SequentialAnimation {
                        id: tremer
                        NumberAnimation { target: deslocamento; property: "x"; to: 10; duration: 50 }
                        NumberAnimation { target: deslocamento; property: "x"; to: -10; duration: 70 }
                        NumberAnimation { target: deslocamento; property: "x"; to: 6; duration: 60 }
                        NumberAnimation { target: deslocamento; property: "x"; to: 0; duration: 50 }
                    }

                    TextInput {
                        id: campo
                        anchors.left: parent.left
                        anchors.right: botaoEntrar.left
                        anchors.leftMargin: Math.round(18 * lockScreenUi.d)
                        anchors.rightMargin: Math.round(8 * lockScreenUi.d)
                        anchors.verticalCenter: parent.verticalCenter
                        focus: true
                        text: PasswordSync.password
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        font.family: lockScreenUi.fonteTexto
                        font.pixelSize: Math.round(16 * lockScreenUi.d)
                        color: lockScreenUi.corTexto
                        selectionColor: lockScreenUi.corFoco
                        clip: true
                        // o cursor piscando com a interface escondida gastaria quadros à toa
                        cursorVisible: activeFocus && lockScreenRoot.uiVisible
                        onAccepted: {
                            if (lockScreenRoot.uiVisible) {
                                lockScreenUi.startLogin();
                            }
                        }

                        Rotulo {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: campo.text.length === 0
                            text: lockScreenUi.tr("@info:placeholder in text field", "Password")
                            color: lockScreenUi.corTexto3
                            font.pixelSize: campo.font.pixelSize
                            elide: Text.ElideRight
                        }
                    }
                    Binding {
                        target: PasswordSync
                        property: "password"
                        value: campo.text
                    }

                    Rectangle {
                        id: botaoEntrar
                        anchors.right: parent.right
                        anchors.rightMargin: Math.round(5 * lockScreenUi.d)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.height - Math.round(10 * lockScreenUi.d)
                        height: width
                        radius: width / 2
                        activeFocusOnTab: true
                        color: areaEntrar.containsMouse || activeFocus ? lockScreenUi.corPreenchimentoHover : "transparent"
                        Accessible.role: Accessible.Button
                        Accessible.name: lockScreenUi.tr("@action:button accessible only", "Unlock")
                        Keys.onReturnPressed: lockScreenUi.startLogin()
                        Keys.onEnterPressed: lockScreenUi.startLogin()
                        Icone {
                            anchors.centerIn: parent
                            text: "arrow_forward"
                            tamanho: Math.round(20 * lockScreenUi.d)
                        }
                        MouseArea {
                            id: areaEntrar
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: lockScreenUi.startLogin()
                        }
                    }
                }

                // Autenticou sem senha (impressão digital, cartão…): só falta confirmar
                Rectangle {
                    id: botaoDesbloquear
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(18 * lockScreenUi.d)
                    visible: lockScreenUi.semSenha
                    implicitWidth: Math.round(200 * lockScreenUi.d)
                    implicitHeight: Math.round(40 * lockScreenUi.d)
                    radius: height / 2
                    color: areaDesbloquear.containsMouse || activeFocus ? lockScreenUi.corPreenchimentoHover : lockScreenUi.corPreenchimento
                    Keys.onReturnPressed: Qt.quit()
                    Keys.onEnterPressed: Qt.quit()
                    Rotulo {
                        anchors.centerIn: parent
                        text: lockScreenUi.tr("@action:button no-password unlock", "Unlock")
                        font.pixelSize: Math.round(15 * lockScreenUi.d)
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: areaDesbloquear
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.quit()
                    }
                }

                // Mensagem: falha, Caps Lock, pedidos do PAM
                Rotulo {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(10 * lockScreenUi.d)
                    Layout.maximumWidth: Math.round(420 * lockScreenUi.d)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: {
                        const partes = [];
                        if (capsLockState.locked) {
                            partes.push(lockScreenUi.tr("@info:status", "Caps Lock is on"));
                        }
                        if (accessibilityStatus.slowKeysEnabled) {
                            partes.push(lockScreenUi.tr("@info:status", "Slow Keys are enabled"));
                        }
                        if (root.notification) {
                            partes.push(root.notification);
                        }
                        return partes.length > 0 ? partes.join(" • ") : " ";
                    }
                    color: root.notification.length > 0 ? lockScreenUi.corPerigo : lockScreenUi.corTexto3
                    font.pixelSize: Math.round(13 * lockScreenUi.d)
                }

                // Tipos de autenticação (senha, digital…), só quando há mais de um — lógica do KDE
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(8 * lockScreenUi.d)
                    spacing: Math.round(8 * lockScreenUi.d)
                    visible: tipos.count > 1

                    Repeater {
                        id: tipos
                        model: ScreenLocker.AuthenticatorModel

                        delegate: PlasmaComponents3.ToolButton {
                            id: tipo
                            required property int type
                            required property string iconName
                            required property bool passwordField
                            required property bool expectingPrompt
                            required property string tooltip
                            required property bool showPrompt
                            required property bool functional

                            onFunctionalChanged: {
                                if (functional) {
                                    return
                                }
                                root.notification = ""
                                caixa.mostrarCampo = false
                                lockScreenUi.handleMessage(lockScreenUi.tr("@info:status",
                                    "This authentication method is not functioning correctly. Please try another method, and check your system configuration."))
                            }

                            enabled: functional
                            icon.name: iconName
                            checkable: true
                            checked: authenticator.authenticator === type
                            onClicked: {
                                authenticator.authenticator = type
                                root.notification = ""
                                caixa.mostrarCampo = passwordField
                                lockScreenUi.expectingPrompt = expectingPrompt
                                lockScreenUi.showPrompt = showPrompt
                            }

                            PlasmaComponents3.ToolTip.text: tooltip
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents3.ToolTip.visible: hovered

                            Component.onCompleted: {
                                if (checked) {
                                    clicked()
                                }
                            }
                        }
                    }
                }

                // Energia / sessão
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(36 * lockScreenUi.d)
                    spacing: Math.round(30 * lockScreenUi.d)

                    Repeater {
                        model: [
                            { icone: "bedtime", rotulo: lockScreenUi.tr("@action:button", "Slee&p"),
                              pode: sessionManagement.canSuspend, acao: () => lockScreenUi.dormir("suspendToRam") },
                            { icone: "ac_unit", rotulo: lockScreenUi.tr("@action:button", "&Hibernate"),
                              pode: sessionManagement.canHibernate, acao: () => lockScreenUi.dormir("suspendToDisk") },
                            { icone: "switch_account", rotulo: lockScreenUi.tr("@action:button", "Switch &User"),
                              pode: sessionManagement.canSwitchUser, acao: () => sessionManagement.switchUser() }
                        ]
                        Item {
                            id: botao
                            required property var modelData
                            visible: botao.modelData.pode
                            width: Math.round(64 * lockScreenUi.d)
                            height: disco.height + rotulo.anchors.topMargin + rotulo.height

                            Rectangle {
                                id: disco
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: width
                                radius: width / 2
                                color: areaBotao.containsMouse ? lockScreenUi.corPreenchimentoHover : lockScreenUi.corPreenchimento
                                scale: areaBotao.pressed ? 0.93 : 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Icone {
                                    anchors.centerIn: parent
                                    text: botao.modelData.icone
                                    tamanho: Math.round(26 * lockScreenUi.d)
                                }
                            }
                            Rotulo {
                                id: rotulo
                                anchors.top: disco.bottom
                                anchors.topMargin: Math.round(10 * lockScreenUi.d)
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: botao.modelData.rotulo
                                font.pixelSize: Math.round(13 * lockScreenUi.d)
                                font.weight: Font.Medium
                            }
                            MouseArea {
                                id: areaBotao
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: botao.modelData.acao()
                            }
                        }
                    }
                }
            }
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }

        // Rodapé: troca de layout do teclado (só com mais de um) e bateria — do KDE, discretos
        RowLayout {
            id: footer
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing
            opacity: formulario.opacity
            visible: opacity > 0

            PlasmaComponents3.ToolButton {
                id: keyboardButton
                focusPolicy: Qt.TabFocus
                Accessible.description: lockScreenUi.tr("Button to change keyboard layout", "Switch layout")
                icon.name: "input-keyboard"
                PW.KeyboardLayoutSwitcher {
                    id: keyboardLayoutSwitcher
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                }
                text: keyboardLayoutSwitcher.layoutNames.longName
                onClicked: keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout()
                visible: keyboardLayoutSwitcher.hasMultipleKeyboardLayouts
            }

            Item { Layout.fillWidth: true }

            Battery {}
        }
    }
}
