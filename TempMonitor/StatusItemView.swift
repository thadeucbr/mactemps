import Cocoa

class StatusItemView: NSView {

    struct TemperatureDisplayInfo {
        let stringValue: String
        let iconName: String? // Nome do ícone (ex: "cpu_icon") ou nil
        // Futuramente, podemos adicionar coordenadas ou quadrante aqui se necessário
    }

    // Propriedades para armazenar as temperaturas a serem exibidas
    // Inicialmente, vamos lidar com uma única temperatura.
    // Isso será expandido para suportar múltiplos quadrantes.
    var temperaturesToDisplay: [TemperatureDisplayInfo] = [] {
        didSet {
            needsDisplay = true // Marca a view para ser redesenhada quando os dados mudam
        }
    }

    var currentLayout: LayoutMode = .singleQuadrant {
        didSet {
            needsDisplay = true
            updateWidth()
        }
    }

    enum LayoutMode {
        case singleQuadrant
        case dualQuadrant
        case quadQuadrant

        var width: CGFloat {
            switch self {
            case .singleQuadrant: return 45
            case .dualQuadrant: return 80
            case .quadQuadrant: return 80
            }
        }

        var numberOfTemperatures: Int {
            switch self {
            case .singleQuadrant: return 1
            case .dualQuadrant: return 2
            case .quadQuadrant: return 4
            }
        }
    }

    private weak var statusItem: NSStatusItem?

    // Inicializador
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        // A largura inicial será definida pelo layout padrão
        let initialWidth = currentLayout.width
        super.init(frame: NSRect(x: 0, y: 0, width: initialWidth, height: NSStatusBar.system.thickness))
        updateWidth() // Garante que o statusItem também seja atualizado
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateWidth() {
        let newWidth = currentLayout.width
        var newFrame = self.frame
        newFrame.size.width = newWidth
        self.frame = newFrame

        // Atualiza também a largura do NSStatusItem ao qual esta view pertence
        statusItem?.length = newWidth
        needsDisplay = true
    }

    // Método de desenho principal
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Fundo (opcional, pode ser transparente por padrão)
        // NSColor.clear.set() // Exemplo de fundo transparente
        // NSColor.lightGray.withAlphaComponent(0.2).set() // Exemplo de fundo leve para depuração
        // dirtyRect.fill()

        guard !temperaturesToDisplay.isEmpty else {
            // Desenha um placeholder se não houver temperaturas
            drawPlaceholder(in: bounds)
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let fontSize: CGFloat
        let iconSize: CGFloat
        let iconPadding: CGFloat = 2 // Espaço entre ícone e texto

        switch currentLayout {
        case .singleQuadrant:
            fontSize = 13
            iconSize = 14
        case .dualQuadrant, .quadQuadrant:
            fontSize = 10
            iconSize = 11 // Ícone menor para layouts mais densos
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        // Função auxiliar para desenhar um item (ícone + texto)
        func drawItem(tempInfo: TemperatureDisplayInfo, inRect itemRect: CGRect) {
            var textOriginX = itemRect.origin.x
            var textWidth = itemRect.width

            if let iconName = tempInfo.iconName, let icon = NSImage(named: iconName) {
                // Se for SFSymbol, configurar para template e cor do texto
                // No macOS 10.15, SF Symbols não são diretamente suportados da mesma forma que no macOS 11+.
                // NSImage(systemSymbolName:) está disponível a partir do macOS 11.
                // Para versões anteriores, precisaríamos de assets PNG/PDF ou outra biblioteca de ícones.
                // Vamos assumir que os ícones nomeados em Assets.xcassets já estão corretos (e podem ser template).
                // A lógica de `icon.isTemplate = true` pode ser mantida se os assets forem configurados como template.
                if icon.isTemplate { // Verifica se o asset é um template
                    // Não precisa definir icon.isTemplate = true aqui, pois já deve estar no asset.
                    // A cor será aplicada durante o desenho.
                }

                let iconRectWidth = iconSize
                let iconRectHeight = iconSize
                let iconY = itemRect.origin.y + (itemRect.height - iconRectHeight) / 2 // Centraliza o ícone verticalmente
                let iconRect = CGRect(x: itemRect.origin.x + iconPadding, y: iconY, width: iconRectWidth, height: iconRectHeight)

                // Salva o estado gráfico atual
                NSGraphicsContext.current?.saveGraphicsState()

                if icon.isTemplate {
                    // Define a cor de preenchimento para o ícone template
                    NSColor.labelColor.set() // Usa a cor do texto padrão
                }

                // Desenha o ícone
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])

                // Restaura o estado gráfico
                NSGraphicsContext.current?.restoreGraphicsState()


                textOriginX += iconRectWidth + iconPadding * 2 // Ajusta a origem do texto
                textWidth -= (iconRectWidth + iconPadding * 2) // Ajusta a largura do texto
            }

            // Ajusta o alinhamento do texto para a esquerda se houver ícone, ou centralizado se não houver.
            let tempParagraphStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            if tempInfo.iconName != nil {
                 // Adiciona um pequeno espaço à esquerda para o texto não colar no ícone
                textOriginX += iconPadding
                textWidth -= iconPadding
                tempParagraphStyle.alignment = .left
            } else {
                tempParagraphStyle.alignment = .center
            }

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: tempParagraphStyle
            ]

            let textRect = CGRect(x: textOriginX, y: itemRect.origin.y + (itemRect.height - fontSize - 1) / 2, width: textWidth, height: fontSize + 2)
            (tempInfo.stringValue as NSString).draw(with: textRect, options: .usesLineFragmentOrigin, attributes: textAttributes)
        }


        // Desenha as temperaturas com base no layout
        switch currentLayout {
        case .singleQuadrant:
            if let tempInfo = temperaturesToDisplay.first {
                drawItem(tempInfo: tempInfo, inRect: bounds)
            }
        case .dualQuadrant:
            let itemWidth = bounds.width / 2
            for (index, tempInfo) in temperaturesToDisplay.prefix(2).enumerated() {
                let rect = CGRect(x: itemWidth * CGFloat(index), y: 0, width: itemWidth, height: bounds.height)
                drawItem(tempInfo: tempInfo, inRect: rect)
            }
        case .quadQuadrant:
            let itemWidth = bounds.width / 2
            let itemHeight = bounds.height / 2
            for (index, tempInfo) in temperaturesToDisplay.prefix(4).enumerated() {
                let x = (index % 2 == 0) ? 0 : itemWidth
                // Ajuste para o sistema de coordenadas do drawItem
                // Linha superior (índices 0, 1) deve ter y = itemHeight
                // Linha inferior (índices 2, 3) deve ter y = 0
                let yCoord = (index < 2) ? itemHeight : 0

                let rect = CGRect(x: x, y: CGFloat(yCoord), width: itemWidth, height: itemHeight)
                drawItem(tempInfo: tempInfo, inRect: rect)
            }
        }
    }

    private func drawPlaceholder(in rect: NSRect) {
        let placeholderText = "--°"
        let fontSize: CGFloat = (currentLayout == .singleQuadrant) ? 13 : 10
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                return style
            }()
        ]
        let textRect = CGRect(x: 0, y: (rect.height - fontSize - 1) / 2, width: rect.width, height: fontSize + 2)
        (placeholderText as NSString).draw(with: textRect, options: .usesLineFragmentOrigin, attributes: attributes)
    }

    // Permite que cliques passem para o NSStatusItem para exibir o menu
    override func mouseDown(with event: NSEvent) {
        statusItem?.button?.performClick(nil)
    }
}
