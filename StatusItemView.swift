import Cocoa

class StatusItemView: NSView {

    struct TemperatureDisplayInfo {
        let stringValue: String
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
        switch currentLayout {
        case .singleQuadrant:
            fontSize = 13
        case .dualQuadrant, .quadQuadrant:
            fontSize = 10 // Fonte menor para mais informações
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor, // Adapta-se ao modo light/dark
            .paragraphStyle: paragraphStyle
        ]

        // Desenha as temperaturas com base no layout
        switch currentLayout {
        case .singleQuadrant:
            if let tempInfo = temperaturesToDisplay.first {
                let textRect = CGRect(x: 0, y: (bounds.height - fontSize - 1) / 2, width: bounds.width, height: fontSize + 2)
                (tempInfo.stringValue as NSString).draw(with: textRect, options: .usesLineFragmentOrigin, attributes: attributes)
            }
        case .dualQuadrant:
            let itemWidth = bounds.width / 2
            for (index, tempInfo) in temperaturesToDisplay.prefix(2).enumerated() {
                let textRect = CGRect(x: itemWidth * CGFloat(index), y: (bounds.height - fontSize - 1) / 2, width: itemWidth, height: fontSize + 2)
                (tempInfo.stringValue as NSString).draw(with: textRect, options: .usesLineFragmentOrigin, attributes: attributes)
            }
        case .quadQuadrant:
            let itemWidth = bounds.width / 2
            let itemHeight = bounds.height / 2
            for (index, tempInfo) in temperaturesToDisplay.prefix(4).enumerated() {
                let x = (index % 2 == 0) ? 0 : itemWidth
                let yOffset = (bounds.height - (fontSize * 2 + 2)) / 2 // Centraliza verticalmente o bloco 2x2
                let y = (index < 2) ? itemHeight + yOffset - ( (itemHeight - fontSize) / 2 + fontSize ) : yOffset + ( (itemHeight - fontSize) / 2 )

                // Ajuste fino do y para alinhar melhor as duas linhas
                let adjustedY : CGFloat
                if (index < 2) { // Linha superior
                    adjustedY = itemHeight + (itemHeight - fontSize - 1) / 2
                } else { // Linha inferior
                    adjustedY = (itemHeight - fontSize - 1) / 2
                }
                let textRect = CGRect(x: x, y: adjustedY , width: itemWidth, height: fontSize + 2)
                (tempInfo.stringValue as NSString).draw(with: textRect, options: .usesLineFragmentOrigin, attributes: attributes)
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
