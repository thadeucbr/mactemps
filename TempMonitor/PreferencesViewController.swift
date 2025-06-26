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
            // Agora obtemos os sensores que estão realmente disponíveis
            if let monitor = self.hardwareMonitor {
                self.availableSensors = monitor.getAvailableSensors()
                print("PreferencesViewController: Carregados \(self.availableSensors.count) sensores disponíveis.")
            } else {
                self.availableSensors = [] // Nenhum monitor, nenhum sensor
                print("PreferencesViewController: HardwareMonitor não encontrado. Nenhum sensor disponível.")
                // Considerar mostrar um alerta ou mensagem na UI se o monitor não estiver disponível
            }
        } else {
            self.availableSensors = []
            print("PreferencesViewController: AppDelegate não encontrado. Nenhum sensor disponível.")
        }
        // self.availableSensors = HardwareMonitor.potentialSensors // Comentado: Usar a lista filtrada

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

        // Obtém todas as chaves de sensores atualmente selecionadas em *outros* popups.
        var currentlySelectedKeysInOtherPopUps: Set<String> = []
        for (idx, btn) in quadrantPopUpButtons.enumerated() {
            // Se o botão já tem uma seleção (de loadCurrentSelections ou de uma mudança anterior)
            if let selectedKey = btn.selectedItem?.representedObject as? String, !selectedKey.isEmpty {
                 // Não adicionamos a chave do popup que estamos prestes a popular
                 // Este loop roda antes de popular cada popup, então as seleções
                 // dos outros já estão (ou deveriam estar) definidas.
                 // No entanto, esta função é chamada uma vez para popular todos.
                 // Precisamos de uma lógica diferente para "on change" ou repopular todos.

                 // Para a lógica inicial de popular todos:
                 // Quando populamos o popup X, as seleções dos popups Y, Z, W são relevantes.
                 // Melhor obter as seleções salvas de AppSettings diretamente para determinar
                 // o que está "em uso" pelos outros.
            }
        }
        // Vamos refazer a lógica de popular para cada botão individualmente,
        // considerando as seleções dos outros.

        for popUpButtonToPopulate in quadrantPopUpButtons {
            popUpButtonToPopulate.removeAllItems()
            popUpButtonToPopulate.addItem(withTitle: noneSensor.name)
            popUpButtonToPopulate.lastItem?.representedObject = noneSensor.key

            let currentQuadrantTag = popUpButtonToPopulate.tag
            var otherSelectedKeys: Set<String> = []
            for otherButton in quadrantPopUpButtons {
                if otherButton.tag == currentQuadrantTag { continue } // Não considera a si mesmo

                // Obtém a chave selecionada do AppSettings para o outro botão
                if let otherKey = AppSettings.shared.sensorKey(forQuadrant: otherButton.tag), !otherKey.isEmpty {
                    otherSelectedKeys.insert(otherKey)
                }
            }

            // Sensor atualmente selecionado para ESTE popup (se houver)
            let currentSensorKeyForThisPopUp = AppSettings.shared.sensorKey(forQuadrant: currentQuadrantTag)

            for sensor in availableSensors {
                // O sensor pode ser adicionado se:
                // 1. Não estiver selecionado em NENHUM outro popup.
                // OU
                // 2. For o sensor ATUALMENTE selecionado para ESTE popup (para que apareça na lista).
                if !otherSelectedKeys.contains(sensor.key) || sensor.key == currentSensorKeyForThisPopUp {
                    popUpButtonToPopulate.addItem(withTitle: sensor.name)
                    popUpButtonToPopulate.lastItem?.representedObject = sensor.key
                }
            }
        }
    }


    private func loadCurrentSelections() {
        for popUpButton in quadrantPopUpButtons {
            let quadrant = popUpButton.tag
            let savedKey = AppSettings.shared.sensorKey(forQuadrant: quadrant)

            if let key = savedKey, !key.isEmpty {
                // Verifica se a chave salva corresponde a um sensor *disponível*
                if availableSensors.contains(where: { $0.key == key }) {
                    // Tenta selecionar o item. O item pode não existir no popup se
                    // populatePopUpButtons já o filtrou por estar em uso em outro lugar
                    // (embora a lógica atual de populatePopUpButtons deve permitir o item atual).
                    var foundAndSelected = false
                    for item in popUpButton.itemArray {
                        if let itemKey = item.representedObject as? String, itemKey == key {
                            popUpButton.select(item)
                            foundAndSelected = true
                            break
                        }
                    }
                    if !foundAndSelected {
                        // Se não foi encontrado (ex: estava em uso por outro e foi filtrado), seleciona "Nenhum"
                        // Isso pode acontecer se as configurações salvas tiverem duplicatas e a UI agora as impede.
                        print("Preferências: Chave salva '\(key)' para Q\(quadrant) não encontrada no popup (possivelmente em uso ou indisponível). Definindo para Nenhum.")
                        popUpButton.selectItem(withTitle: "Nenhum")
                        // Opcional: remover a configuração inválida de AppSettings
                        // AppSettings.shared.setSensorKey(nil, forQuadrant: quadrant)
                    }
                } else {
                    // Chave salva refere-se a um sensor não disponível (não passou na validação inicial)
                    print("Preferências: Chave salva '\(key)' para Q\(quadrant) refere-se a um sensor não disponível. Definindo para Nenhum.")
                    popUpButton.selectItem(withTitle: "Nenhum")
                    // Opcional: remover a configuração inválida de AppSettings
                    AppSettings.shared.setSensorKey(nil, forQuadrant: quadrant)
                }
            } else {
                // Nenhuma chave salva ou a chave é vazia ("Nenhum")
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

        // Após uma mudança, repopular todos os popups para refletir as novas restrições
        // e então recarregar as seleções para garantir que a UI esteja consistente.
        populatePopUpButtons()
        loadCurrentSelections()
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
