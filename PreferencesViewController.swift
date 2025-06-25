import Cocoa

class PreferencesViewController: NSViewController {

    // NSPopUpButtons para cada quadrante
    private var quadrantPopUpButtons: [NSPopUpButton] = []
    private var labels: [NSTextField] = []

    private var availableSensors: [Sensor] = []

    // Referência ao HardwareMonitor para obter a lista de sensores
    // Idealmente, isso seria passado ou acessado de forma mais limpa,
    // mas para este escopo, podemos obtê-lo do AppDelegate.
    private weak var hardwareMonitor: HardwareMonitor?

    override func loadView() {
        // Define o tamanho da view. Pode ser ajustado.
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        self.view.wantsLayer = true // Bom para performance e customização
        // self.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Obtém a referência ao HardwareMonitor
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            self.hardwareMonitor = appDelegate.hardwareMonitor
        }
        self.availableSensors = HardwareMonitor.knownSensors // Usamos a lista estática

        setupUI()
        populatePopUpButtons()
        loadCurrentSelections()

        // Adiciona observador para quando as configurações de sensor mudarem externamente
        // (ex: se tivéssemos um botão "Resetar para Padrão" nesta janela)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleSensorSettingsChange(_:)),
                                               name: .sensorSettingsDidChange,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .sensorSettingsDidChange, object: nil)
    }

    private func setupUI() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 20 // Espaço entre cada par label-popup
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])

        for i in 1...4 {
            let label = NSTextField(labelWithString: "Sensor para Quadrante \(i):")
            label.translatesAutoresizingMaskIntoConstraints = false
            labels.append(label)

            let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
            popUpButton.translatesAutoresizingMaskIntoConstraints = false
            popUpButton.target = self
            popUpButton.action = #selector(popUpButtonChanged(_:))
            popUpButton.tag = i // Usamos a tag para identificar o quadrante (1 a 4)
            quadrantPopUpButtons.append(popUpButton)

            let hStack = NSStackView(views: [label, popUpButton])
            hStack.orientation = .horizontal
            hStack.spacing = 8
            hStack.alignment = .centerY
            // Para alinhar os popups, podemos dar um tamanho mínimo ao label ou usar constraints mais específicas
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal) // Label não estica
            popUpButton.setContentHuggingPriority(.defaultLow, for: .horizontal) // Popup estica se necessário
            popUpButton.setContentCompressionResistancePriority(.required, for: .horizontal)


            stackView.addArrangedSubview(hStack)

            // Adicionar constraints para largura do popup
            NSLayoutConstraint.activate([
                popUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200), // Largura mínima
                label.widthAnchor.constraint(equalToConstant: 160) // Largura fixa para o label
            ])
        }
    }

    private func populatePopUpButtons() {
        let noneSensor = Sensor(key: "", name: "Nenhum") // Opção para desabilitar um quadrante
        let sensorsWithNone = [noneSensor] + availableSensors

        for popUpButton in quadrantPopUpButtons {
            popUpButton.removeAllItems()
            for sensor in sensorsWithNone {
                popUpButton.addItem(withTitle: sensor.name)
                // Armazena a chave do sensor no item para fácil recuperação
                popUpButton.lastItem?.representedObject = sensor.key
            }
        }
    }

    private func loadCurrentSelections() {
        for popUpButton in quadrantPopUpButtons {
            let quadrant = popUpButton.tag
            if let selectedKey = AppSettings.shared.sensorKey(forQuadrant: quadrant) {
                if selectedKey.isEmpty { // Representa "Nenhum"
                    popUpButton.selectItem(withTitle: "Nenhum")
                } else if let index = availableSensors.firstIndex(where: { $0.key == selectedKey }) {
                    // availableSensors não inclui "Nenhum", então o índice é +1
                    popUpButton.selectItem(at: index + 1)
                } else {
                    // Chave salva não encontrada (talvez um sensor removido?), seleciona "Nenhum"
                    popUpButton.selectItem(withTitle: "Nenhum")
                }
            } else {
                // Nenhuma chave salva, seleciona "Nenhum"
                popUpButton.selectItem(withTitle: "Nenhum")
            }
        }
    }

    @objc private func popUpButtonChanged(_ sender: NSPopUpButton) {
        let quadrant = sender.tag
        guard let selectedItem = sender.selectedItem else { return }

        // A chave do sensor está no representedObject do item.
        // Se "Nenhum" foi selecionado, representedObject será "" (empty string).
        let sensorKey = selectedItem.representedObject as? String

        AppSettings.shared.setSensorKey(sensorKey, forQuadrant: quadrant)
        // A notificação .sensorSettingsDidChange será postada por AppSettings
        // e o AppDelegate irá lidar com a atualização da StatusItemView.
        print("Preferências: Quadrante \(quadrant) definido para sensor key: '\(sensorKey ?? "nil")'")
    }

    @objc func handleSensorSettingsChange(_ notification: Notification) {
        // Se as configurações mudarem externamente (ex: reset para padrão),
        // recarregamos as seleções nos popups.
        // Verificamos se o objeto da notificação não é um dos nossos popups
        // para evitar recarregar desnecessariamente se a mudança veio daqui.
        // No entanto, para este caso, AppSettings envia o quadrante como objeto.
        // Se a mudança veio de um popup, o `object` da notificação será o `quadrant` (Int).
        // Se for nil ou outro tipo, a mudança pode ser externa.

        // Simplesmente recarregar é seguro.
        print("PreferencesVC: Notificação de mudança de sensor recebida, recarregando seleções.")
        loadCurrentSelections()
    }
}
