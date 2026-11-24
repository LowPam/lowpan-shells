// LowPan Shells — tela de login do LowPan (greetd + Quickshell), §21.72.
// Autônoma: não importa nada de shell/ (é copiada sozinha para /usr/share/lowpan-greeter/).
// Visual baseado em shell/modules/iris/session/IrisSessionScreen.qml (mesmo projeto, GPL-3.0).
//
// Produção: roda num kwin_wayland próprio (lançador /usr/lib/lowpan-greeter/iniciar) como usuário "greeter".
// Teste: LOWPAN_GREETER_TESTE=1 (ou sem greetd) abre uma janela comum; a senha "teste" entra, o resto falha.
//        LOWPAN_GREETER_DIR=<pasta> lê config.json/estado.json dessa pasta em vez de /etc e /var.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

ShellRoot {
    id: raiz

    // ── Ambiente ─────────────────────────────────────────────────────────────
    readonly property string pastaDados: Quickshell.env("LOWPAN_GREETER_DIR") ?? ""
    readonly property bool modoTeste: Quickshell.env("LOWPAN_GREETER_TESTE") === "1" || !Greetd.available
    readonly property string caminhoConfig: raiz.pastaDados.length > 0
        ? raiz.pastaDados + "/config.json" : "/etc/lowpan-greeter/config.json"

    // ── Configuração (/etc/lowpan-greeter/config.json) ───────────────────────
    // { "usuario": "lowpan", "papelDeParede": "/var/lib/lowpan-greeter/papel-de-parede.jpg",
    //   "telaPrincipal": "DP-1", "estado": "/var/lib/lowpan-greeter/estado.json" }
    property var config: ({})
    readonly property string papelDeParede: String(raiz.config.papelDeParede ?? "")
    readonly property string telaPrincipal: String(raiz.config.telaPrincipal ?? "")
    readonly property string caminhoEstado: raiz.pastaDados.length > 0
        ? raiz.pastaDados + "/estado.json"
        : String(raiz.config.estado ?? "/var/lib/lowpan-greeter/estado.json")

    readonly property var sessoes: [
        { id: "iris", nome: "LowPan", comando: ["/usr/lib/lowpan-greeter/lowpan-sessao-iris"] },
        { id: "plasma", nome: "Plasma", comando: ["/usr/lib/lowpan-greeter/lowpan-sessao-plasma"] }
    ]

    // ── Estado da tela ───────────────────────────────────────────────────────
    property string sessao: "iris"
    property var usuarios: []            // [{ nome, nomeCompleto }]
    property int indiceUsuario: 0
    readonly property var usuarioAtual: raiz.usuarios[raiz.indiceUsuario] ?? { nome: String(raiz.config.usuario ?? ""), nomeCompleto: "" }
    property string mensagem: ""
    property bool mensagemErro: false
    property bool ocupado: false         // esperando o greetd/PAM
    property string senhaPendente: ""
    property string pedido: ""           // pergunta extra do PAM (ex.: código), quando houver
    property bool pedidoVisivel: false
    property int falhas: 0               // muda a cada falha: as telas tremem e limpam o campo

    signal limparCampo()

    function nomeSessao(id: string): string {
        return (raiz.sessoes.find(s => s.id === id) ?? raiz.sessoes[0]).nome
    }

    function escolherSessao(id: string): void {
        if (!raiz.sessoes.some(s => s.id === id))
            return
        raiz.sessao = id
    }

    function trocarUsuario(passo: int): void {
        if (raiz.usuarios.length < 2 || raiz.ocupado)
            return
        raiz.indiceUsuario = (raiz.indiceUsuario + passo + raiz.usuarios.length) % raiz.usuarios.length
        raiz.mensagem = ""
    }

    function falhar(texto: string): void {
        raiz.ocupado = false
        raiz.senhaPendente = ""
        raiz.pedidoVisivel = false
        raiz.pedido = ""
        raiz.mensagem = texto
        raiz.mensagemErro = true
        raiz.falhas++
        raiz.limparCampo()
        if (!raiz.modoTeste && Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession()
    }

    // Enter no campo: senha (ou a resposta a um pedido extra do PAM).
    function enviar(texto: string): void {
        if (raiz.ocupado && !raiz.pedidoVisivel)
            return
        if (raiz.pedidoVisivel) {
            raiz.pedidoVisivel = false
            raiz.ocupado = true
            raiz.limparCampo()
            Greetd.respond(texto)
            return
        }
        if (texto.length === 0 || raiz.usuarioAtual.nome.length === 0)
            return
        raiz.mensagem = ""
        raiz.mensagemErro = false
        raiz.ocupado = true
        if (raiz.modoTeste) {
            testeResposta.senha = texto
            testeResposta.restart()
            return
        }
        raiz.senhaPendente = texto
        Greetd.createSession(raiz.usuarioAtual.nome)
    }

    function acaoEnergia(acao: string): void {
        if (raiz.modoTeste) {
            console.log("[greeter] teste: systemctl " + acao)
            return
        }
        Quickshell.execDetached(["systemctl", acao])
    }

    function salvarEstado(): void {
        arqEstado.setText(JSON.stringify({ sessao: raiz.sessao, usuario: raiz.usuarioAtual.nome }) + "\n")
    }

    // Saída: a tela escurece em fade (Tela.qml, "saindo") e só então a sessão é lançada — o KWin da tela de login
    // fecha e o da sessão abre no preto; a apresentação do LowPan (lowpan-splash) entra com fade a partir do preto.
    property bool saindo: false
    property var comandoSaida: []

    function iniciarSessao(): void {
        const s = raiz.sessoes.find(x => x.id === raiz.sessao) ?? raiz.sessoes[0]
        raiz.salvarEstado()
        raiz.mensagem = "Entrando no " + s.nome + "…"
        raiz.mensagemErro = false
        raiz.comandoSaida = s.comando
        raiz.saindo = true
        atrasoSaida.restart()
    }

    Timer {
        id: atrasoSaida
        interval: 420   // um pouco mais que o fade da Tela.qml (350 ms)
        onTriggered: {
            if (raiz.modoTeste) {
                console.log("[greeter] teste: iniciaria " + JSON.stringify(raiz.comandoSaida) + " como " + raiz.usuarioAtual.nome)
                Qt.quit()
                return
            }
            // O tipo da sessão vai no ambiente do greetd: sem ele o logind registra a sessão como "tty" e o
            // pam_kwallet5 pula ("not a graphical session") — a carteira pedia senha de novo (2026-11-14).
            Greetd.launch(raiz.comandoSaida, ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=KDE", "XDG_CURRENT_DESKTOP=KDE"])
        }
    }

    // Lista de usuários normais (UID 1000–59999, shell de login válido); o padrão da config vem primeiro.
    function lerUsuarios(texto: string): void {
        const lista = []
        for (const linha of texto.split("\n")) {
            const c = linha.split(":")
            if (c.length < 7)
                continue
            const uid = parseInt(c[2])
            const shell = c[6].trim()
            if (!(uid >= 1000 && uid < 60000) || /(nologin|false)$/.test(shell) || shell.length === 0)
                continue
            lista.push({ nome: c[0], nomeCompleto: (c[4] ?? "").split(",")[0].trim() })
        }
        raiz.usuarios = lista
        raiz.escolherUsuario(arqEstadoDados.usuario ?? String(raiz.config.usuario ?? ""))
    }

    function escolherUsuario(nome: string): void {
        const i = raiz.usuarios.findIndex(u => u.nome === nome)
        raiz.indiceUsuario = i >= 0 ? i : 0
    }

    property var arqEstadoDados: ({})

    FileView {
        id: arqConfig
        path: raiz.caminhoConfig
        blockLoading: true
        printErrors: false
        onLoaded: {
            try { raiz.config = JSON.parse(arqConfig.text()) } catch (e) { console.warn("[greeter] config inválida: " + e) }
        }
    }

    FileView {
        id: arqEstado
        path: raiz.caminhoEstado
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                raiz.arqEstadoDados = JSON.parse(arqEstado.text())
                raiz.escolherSessao(String(raiz.arqEstadoDados.sessao ?? "iris"))
            } catch (e) {}
        }
    }

    FileView {
        id: arqSenhas
        path: "/etc/passwd"
        blockLoading: true
        onLoaded: raiz.lerUsuarios(arqSenhas.text())
    }

    // ── greetd ───────────────────────────────────────────────────────────────
    Connections {
        target: Greetd
        enabled: !raiz.modoTeste

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (!responseRequired) {
                // Informação/erro do PAM: o Quickshell já confirma sozinho; só mostra.
                if (message.length > 0) {
                    raiz.mensagem = message
                    raiz.mensagemErro = error
                }
                return
            }
            if (raiz.senhaPendente.length > 0 && !echoResponse) {
                const senha = raiz.senhaPendente
                raiz.senhaPendente = ""
                Greetd.respond(senha)
                return
            }
            // Pergunta extra (ou com eco): devolve o campo para o usuário responder.
            raiz.pedido = message
            raiz.pedidoVisivel = true
            raiz.ocupado = false
            raiz.limparCampo()
        }

        function onAuthFailure(message: string): void {
            raiz.falhar("Senha incorreta")
        }

        function onError(error: string): void {
            raiz.falhar("Erro do greetd: " + error)
        }

        function onReadyToLaunch(): void {
            raiz.iniciarSessao()
        }
    }

    Timer {
        id: testeResposta
        property string senha: ""
        interval: 500
        onTriggered: {
            if (testeResposta.senha === "teste")
                raiz.iniciarSessao()
            else
                raiz.falhar("Senha incorreta")
        }
    }

    // ── Fontes do LowPan (copiadas junto: fonts/ → shell/assets/fonts no projeto) ──
    Instantiator {
        model: ["Light", "Regular", "Medium", "SemiBold", "Bold"].map(p => `inter/Inter-${p}`)
            .concat(["Medium", "SemiBold", "Bold"].map(p => `rubik/Rubik-${p}`))
        delegate: FontLoader {
            required property string modelData
            source: Quickshell.shellPath(`fonts/${modelData}.ttf`)
        }
    }

    // ── Janelas ──────────────────────────────────────────────────────────────
    function ehPrincipal(tela: var): bool {
        const telas = Quickshell.screens
        const nomeada = telas.find(t => t.name === raiz.telaPrincipal)
        return tela === (nomeada ?? telas[0])
    }

    // Produção: uma camada por tela; o formulário só na principal. Em arquivo à parte e carregado só fora do
    // modo de teste: sem Wayland (teste fora da tela) o PanelWindow nem compila.
    LazyLoader {
        active: !raiz.modoTeste
        source: Qt.resolvedUrl("Camadas.qml")
        onItemChanged: if (item) item.estado = raiz
    }

    // Teste: uma janela comum.
    LazyLoader {
        active: raiz.modoTeste

        FloatingWindow {
            title: "Tela de login do LowPan (teste)"
            implicitWidth: 1280
            implicitHeight: 800
            color: "#0b0b0f"

            Tela {
                anchors.fill: parent
                estado: raiz
                principal: true
            }
        }
    }
}
