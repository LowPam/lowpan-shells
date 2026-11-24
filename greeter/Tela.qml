// LowPan Shells — conteúdo de uma tela do login do LowPan (§21.72).
// Fundo desfocado em todas as telas; relógio, usuário, senha, sessão e energia só na principal.
// Medidas e cores copiadas da tela de sessão do LowPan (shell/modules/iris/session/IrisSessionScreen.qml).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell

Item {
    id: tela

    required property var estado
    required property bool principal

    // Paleta (valores do LowPan sobre mídia escura)
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
    readonly property real d: Math.max(1, Math.min(tela.width / 1920, tela.height / 1080) * 1.1)

    // ── Fundo ────────────────────────────────────────────────────────────────
    Image {
        id: fundo
        anchors.fill: parent
        anchors.margins: -64
        visible: false
        source: tela.estado.papelDeParede.length > 0 ? "file://" + tela.estado.papelDeParede : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Vai ser desfocado: decodificar pequeno poupa memória e tempo.
        sourceSize: Qt.size(Math.max(1, Math.round(tela.width / 4)), Math.max(1, Math.round(tela.height / 4)))
    }
    MultiEffect {
        anchors.fill: fundo
        visible: fundo.status === Image.Ready
        source: fundo
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 48
        saturation: 0.1
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.04, 0.04, 0.06, fundo.status === Image.Ready ? 0.45 : 1)
    }

    // ── Formulário (só na tela principal) ────────────────────────────────────
    Loader {
        anchors.fill: parent
        active: tela.principal
        sourceComponent: formulario
    }

    // ── Saída: fade para o preto antes de lançar a sessão (shell.qml, "saindo") ──
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: tela.estado.saindo ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InCubic } }
        MouseArea { anchors.fill: parent; enabled: tela.estado.saindo }   // nada de clique durante a saída
    }

    component Icone: Text {
        property real tamanho: 24
        font.family: tela.fonteIcones
        font.pixelSize: tamanho
        font.variableAxes: ({ "FILL": 1 })
        color: tela.corTexto
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component Rotulo: Text {
        font.family: tela.fonteTexto
        color: tela.corTexto
        renderType: Text.NativeRendering
    }

    Component {
        id: formulario

        FocusScope {
            id: palco
            focus: true

            SystemClock { id: relogio; precision: SystemClock.Minutes }

            // Ações de energia: Reiniciar e Desligar pedem um segundo clique (como na tela de sessão).
            readonly property var acoes: [
                { id: "suspend", icone: "bedtime", rotulo: "Suspender", confirmar: false },
                { id: "reboot", icone: "restart_alt", rotulo: "Reiniciar", confirmar: true },
                { id: "poweroff", icone: "power_settings_new", rotulo: "Desligar", confirmar: true }
            ]
            property string pendente: ""
            Timer { id: expirarPendente; interval: 5000; onTriggered: palco.pendente = "" }

            function acionar(acao: var): void {
                if (acao.confirmar && palco.pendente !== acao.id) {
                    palco.pendente = acao.id
                    expirarPendente.restart()
                    return
                }
                palco.pendente = ""
                tela.estado.acaoEnergia(acao.id)
            }

            Component.onCompleted: Qt.callLater(() => campo.forceActiveFocus())

            Connections {
                target: tela.estado
                function onLimparCampo(): void {
                    campo.text = ""
                    campo.forceActiveFocus()
                }
                function onFalhasChanged(): void { tremer.restart() }
            }

            // Clicar no fundo devolve o foco ao campo e cancela a confirmação pendente.
            MouseArea {
                anchors.fill: parent
                onClicked: { palco.pendente = ""; campo.forceActiveFocus() }
            }

            ColumnLayout {
                id: coluna
                anchors.centerIn: parent
                spacing: 0

                // Relógio: HH:MM com os dois-pontos em laranja (IrisClock)
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Repeater {
                        model: [Qt.formatDateTime(relogio.date, "HH"), ":", Qt.formatDateTime(relogio.date, "mm")]
                        Text {
                            required property string modelData
                            text: modelData
                            font.family: tela.fonteNumeros
                            font.pixelSize: Math.round(72 * tela.d)
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                            font.letterSpacing: Math.round(-72 * tela.d * 0.02)
                            color: modelData === ":" ? tela.corDestaque : tela.corTexto
                            renderType: Text.NativeRendering
                        }
                    }
                }
                Rotulo {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.locale("pt_BR").toString(relogio.date, "dddd, d 'de' MMMM")
                    color: tela.corTexto2
                    font.pixelSize: Math.round(18 * tela.d)
                }

                // Avatar
                Item {
                    id: avatar
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(44 * tela.d)
                    implicitWidth: Math.round(96 * tela.d)
                    implicitHeight: implicitWidth

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: tela.corPreenchimento
                        visible: foto.status !== Image.Ready
                        Rotulo {
                            anchors.centerIn: parent
                            text: (tela.estado.usuarioAtual.nomeCompleto || tela.estado.usuarioAtual.nome).charAt(0).toUpperCase()
                            font.pixelSize: Math.round(40 * tela.d)
                            font.weight: Font.DemiBold
                        }
                    }
                    Image {
                        id: foto
                        Connections {
                            target: tela.estado
                            function onUsuarioAtualChanged(): void { foto.semFoto = false }
                        }
                        anchors.fill: parent
                        visible: false
                        // sem foto no AccountsService, a mascote do LowPan (mascote.png = link para o logo; o instalar
                        // copia com cp -L) — 2026-11-23, pedido do dono; a inicial fica só se nem ela carregar
                        property bool semFoto: false
                        source: tela.estado.usuarioAtual.nome.length === 0 ? ""
                            : semFoto ? Quickshell.shellPath("mascote.png")
                            : "file:///var/lib/AccountsService/icons/" + tela.estado.usuarioAtual.nome
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

                // Nome (setas só com mais de um usuário)
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(14 * tela.d)
                    spacing: Math.round(8 * tela.d)

                    component Seta: Icone {
                        id: seta
                        property int passo: 1
                        visible: tela.estado.usuarios.length > 1
                        tamanho: Math.round(22 * tela.d)
                        color: areaSeta.containsMouse ? tela.corTexto : tela.corTexto3
                        MouseArea {
                            id: areaSeta
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tela.estado.trocarUsuario(seta.passo)
                        }
                    }

                    Seta { text: "chevron_left"; passo: -1 }
                    Rotulo {
                        text: tela.estado.usuarioAtual.nomeCompleto || tela.estado.usuarioAtual.nome
                        font.pixelSize: Math.round(20 * tela.d)
                        font.weight: Font.DemiBold
                    }
                    Seta { text: "chevron_right"; passo: 1 }
                }

                // Campo de senha (ou resposta a um pedido extra do PAM)
                Rectangle {
                    id: caixa
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(18 * tela.d)
                    implicitWidth: Math.round(300 * tela.d)
                    implicitHeight: Math.round(40 * tela.d)   // era 44: "gordinho"; 38 ficou fino demais (2026-11-16)
                    radius: height / 2
                    color: campo.activeFocus ? tela.corPreenchimentoHover : tela.corPreenchimento
                    border.width: tela.estado.mensagemErro ? 1 : 0
                    border.color: tela.corPerigo
                    Behavior on color { ColorAnimation { duration: 120 } }

                    transform: Translate { id: deslocamento }
                    SequentialAnimation {
                        id: tremer
                        loops: 1
                        NumberAnimation { target: deslocamento; property: "x"; to: 10; duration: 50 }
                        NumberAnimation { target: deslocamento; property: "x"; to: -10; duration: 70 }
                        NumberAnimation { target: deslocamento; property: "x"; to: 6; duration: 60 }
                        NumberAnimation { target: deslocamento; property: "x"; to: 0; duration: 50 }
                    }

                    TextInput {
                        id: campo
                        anchors.left: parent.left
                        anchors.right: botaoEntrar.left
                        anchors.leftMargin: Math.round(18 * tela.d)
                        anchors.rightMargin: Math.round(8 * tela.d)
                        anchors.verticalCenter: parent.verticalCenter
                        focus: true
                        enabled: !tela.estado.ocupado || tela.estado.pedidoVisivel
                        echoMode: tela.estado.pedidoVisivel ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        font.family: tela.fonteTexto
                        font.pixelSize: Math.round(16 * tela.d)
                        color: tela.corTexto
                        selectionColor: tela.corFoco
                        clip: true
                        onAccepted: tela.estado.enviar(campo.text)
                        Keys.onEscapePressed: { campo.text = ""; palco.pendente = "" }
                        Keys.onPressed: event => {
                            // Alt+←/→ troca o usuário; F2 alterna a sessão.
                            if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left) {
                                tela.estado.trocarUsuario(-1); event.accepted = true
                            } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right) {
                                tela.estado.trocarUsuario(1); event.accepted = true
                            } else if (event.key === Qt.Key_F2) {
                                tela.estado.escolherSessao(tela.estado.sessao === "iris" ? "plasma" : "iris"); event.accepted = true
                            }
                        }

                        Rotulo {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: campo.text.length === 0
                            text: tela.estado.pedidoVisivel ? tela.estado.pedido
                                : tela.estado.ocupado ? "Verificando…" : "Senha"
                            color: tela.corTexto3
                            font.pixelSize: campo.font.pixelSize
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: botaoEntrar
                        anchors.right: parent.right
                        anchors.rightMargin: Math.round(5 * tela.d)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.height - Math.round(10 * tela.d)
                        height: width
                        radius: width / 2
                        color: areaEntrar.containsMouse ? tela.corPreenchimentoHover : "transparent"
                        Icone {
                            anchors.centerIn: parent
                            text: tela.estado.ocupado && !tela.estado.pedidoVisivel ? "progress_activity" : "arrow_forward"
                            tamanho: Math.round(20 * tela.d)
                            RotationAnimation on rotation {
                                running: tela.estado.ocupado && !tela.estado.pedidoVisivel
                                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                            }
                        }
                        MouseArea {
                            id: areaEntrar
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tela.estado.enviar(campo.text)
                        }
                    }
                }

                // Mensagem (erro do PAM, "Senha incorreta", "Entrando…")
                Rotulo {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(10 * tela.d)
                    Layout.maximumWidth: Math.round(420 * tela.d)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: tela.estado.mensagem.length > 0 ? tela.estado.mensagem
                        : tela.estado.modoTeste ? "Modo de teste: a senha é \"teste\"" : " "
                    color: tela.estado.mensagemErro ? tela.corPerigo : tela.corTexto3
                    font.pixelSize: Math.round(13 * tela.d)
                }

                // Sessão: LowPan / Plasma
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(16 * tela.d)
                    implicitWidth: linhaSessoes.implicitWidth + Math.round(8 * tela.d)
                    implicitHeight: Math.round(36 * tela.d)
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.1)

                    Row {
                        id: linhaSessoes
                        anchors.centerIn: parent
                        spacing: Math.round(4 * tela.d)
                        Repeater {
                            model: tela.estado.sessoes
                            Rectangle {
                                id: opcao
                                required property var modelData
                                readonly property bool marcada: tela.estado.sessao === opcao.modelData.id
                                width: Math.round(96 * tela.d)
                                height: Math.round(28 * tela.d)
                                radius: height / 2
                                color: opcao.marcada ? Qt.rgba(1, 1, 1, 0.85)
                                    : areaOpcao.containsMouse ? tela.corPreenchimento : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Rotulo {
                                    anchors.centerIn: parent
                                    text: opcao.modelData.nome
                                    color: opcao.marcada ? "#111114" : tela.corTexto2
                                    font.pixelSize: Math.round(13 * tela.d)
                                    font.weight: Font.Medium
                                }
                                MouseArea {
                                    id: areaOpcao
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { tela.estado.escolherSessao(opcao.modelData.id); campo.forceActiveFocus() }
                                }
                            }
                        }
                    }
                }

                // Energia
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(44 * tela.d)
                    spacing: Math.round(30 * tela.d)

                    Repeater {
                        model: palco.acoes
                        Item {
                            id: botao
                            required property var modelData
                            readonly property bool armado: palco.pendente === botao.modelData.id
                            width: Math.round(64 * tela.d)
                            height: disco.height + rotulo.anchors.topMargin + rotulo.height

                            Rectangle {
                                id: disco
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: width
                                radius: width / 2
                                color: botao.armado ? tela.corPerigo
                                    : areaBotao.containsMouse ? tela.corPreenchimentoHover : tela.corPreenchimento
                                scale: areaBotao.pressed ? 0.93 : 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Icone {
                                    anchors.centerIn: parent
                                    text: botao.modelData.icone
                                    tamanho: Math.round(26 * tela.d)
                                }
                            }
                            Rotulo {
                                id: rotulo
                                anchors.top: disco.bottom
                                anchors.topMargin: Math.round(10 * tela.d)
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: botao.armado ? "Confirmar" : botao.modelData.rotulo
                                color: botao.armado ? tela.corPerigo : tela.corTexto
                                font.pixelSize: Math.round(13 * tela.d)
                                font.weight: Font.Medium
                            }
                            MouseArea {
                                id: areaBotao
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: palco.acionar(botao.modelData)
                            }
                        }
                    }
                }

                Rotulo {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Math.round(18 * tela.d)
                    text: palco.pendente.length > 0
                        ? "Clique de novo para " + (palco.pendente === "reboot" ? "reiniciar" : "desligar")
                        : "F2 troca a sessão"
                    color: tela.corTexto3
                    font.pixelSize: Math.round(12 * tela.d)
                }
            }
        }
    }
}
