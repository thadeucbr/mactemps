import Cocoa

class PreferencesViewController: NSViewController {

    // NSPopUpButtons para cada quadrante
    private var quadrantPopUpButtons: [NSPopUpButton] = []
    private var labels: [NSTextField] = []
    private var sensorSelectionCheckboxes: [NSButton] = [] // Para as checkboxes de seleção de sensor
    private var allPotentialSensors: [Sensor] = [] // Todos os sensores que podem existir
    private var availableSensorsForQuadrants: [Sensor] = [] // Sensores disponíveis para os quadrantes (filtrados por seleção do usuário E leitura)

    // Referência ao HardwareMonitor para obter a lista de sensores
    // Idealmente, isso seria passado ou acessado de forma mais limpa,
    // mas para este escopo, podemos obtê-lo do AppDelegate.
    private weak var hardwareMonitor: HardwareMonitor?

    override func loadView() {
        // Define o tamanho da view. Pode ser ajustado.
        // Aumentar a altura para acomodar a nova seção de checkboxes
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 480)) // Aumentado width e height
        self.view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSensorData() // Carrega os dados dos sensores antes de configurar a UI
        setupUI() // Configura a UI, incluindo as novas checkboxes
        loadAndApplyUserSelections() // Carrega e aplica as seleções do usuário (checkboxes e popups)

        // Observadores de Notificações
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleSensorSettingsChange(_:)),
                                               name: .sensorSettingsDidChange, // Para mudanças nos quadrantes
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleUserSelectedSensorsChange(_:)),
                                               name: .userSelectedSensorsDidChange, // Para mudanças na seleção de sensores ativos
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self) // Remove todos os observadores para esta classe
    }

    private func loadSensorData() {
        // Obtém todos os sensores potenciais (para a lista de checkboxes)
        self.allPotentialSensors = HardwareMonitor.potentialSensors
        print("PreferencesViewController: Carregados \(self.allPotentialSensors.count) sensores potenciais.")

        // Obtém a referência ao HardwareMonitor e os sensores *atualmente disponíveis* para os quadrantes
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            self.hardwareMonitor = appDelegate.hardwareMonitor
            if let monitor = self.hardwareMonitor {
                // Esta chamada a getAvailableSensors() já respeitará a seleção do usuário
                // devido às modificações anteriores no HardwareMonitor.
                self.availableSensorsForQuadrants = monitor.getAvailableSensors()
                print("PreferencesViewController: Carregados \(self.availableSensorsForQuadrants.count) sensores disponíveis para quadrantes.")
            } else {
                self.availableSensorsForQuadrants = []
                print("PreferencesViewController: HardwareMonitor não encontrado. Nenhum sensor disponível para quadrantes.")
            }
        } else {
            self.availableSensorsForQuadrants = []
            print("PreferencesViewController: AppDelegate não encontrado. Nenhum sensor disponível para quadrantes.")
        }
    }

    private func refreshAvailableSensorsForQuadrants() {
        if let monitor = self.hardwareMonitor {
            self.availableSensorsForQuadrants = monitor.getAvailableSensors()
            print("PreferencesViewController: Atualizados \(self.availableSensorsForQuadrants.count) sensores disponíveis para quadrantes.")
        } else {
            self.availableSensorsForQuadrants = []
        }
        // Após atualizar a lista de sensores disponíveis para quadrantes,
        // repopular os popups dos quadrantes e recarregar as seleções.
        populateQuadrantPopUpButtons()
        loadCurrentQuadrantSelections()
    }


    private func setupUI() {
        let mainStackView = NSStackView()
        mainStackView.orientation = .vertical
        mainStackView.alignment = .leading
        mainStackView.spacing = 25 // Espaço entre seções
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStackView)

        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            mainStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            mainStackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])

        // --- Seção de Seleção de Sensores Monitorados (Checkboxes) ---
        let monitoredSensorsGroup = NSBox()
        monitoredSensorsGroup.title = "Sensores Monitorados"
        monitoredSensorsGroup.translatesAutoresizingMaskIntoConstraints = false

        let checkboxesStackView = NSStackView()
        checkboxesStackView.orientation = .vertical
        checkboxesStackView.alignment = .leading
        checkboxesStackView.spacing = 8
        checkboxesStackView.translatesAutoresizingMaskIntoConstraints = false

        // Para organizar em colunas, se necessário
        let checkboxGrid = NSGridView()
        checkboxGrid.translatesAutoresizingMaskIntoConstraints = false

        var columnViews: [[NSView]] = []
        let maxRowsPerColumn = (allPotentialSensors.count + 1) / 2 // Exemplo: 2 colunas
        var currentRowInColumn = 0
        var currentColumnIndex = 0
        columnViews.append([])

        for sensor in allPotentialSensors {
            let checkbox = NSButton(checkboxWithTitle: sensor.name, target: self, action: #selector(sensorCheckboxChanged(_:)))
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            // Usar a chave do sensor como uma forma de identificá-lo. Poderíamos usar a tag ou um dicionário.
            // Para simplicidade, vamos associar a chave via `identifier` ou encontrar na ação.
            // Aqui, vamos armazenar a chave em `representedObject` do checkbox para fácil acesso.
            checkbox.representedObject = sensor.key
            sensorSelectionCheckboxes.append(checkbox)

            if currentRowInColumn >= maxRowsPerColumn && currentColumnIndex < 1 { // Limitar a 2 colunas
                currentColumnIndex += 1
                columnViews.append([])
                currentRowInColumn = 0
            }
            columnViews[currentColumnIndex].append(checkbox)
            currentRowInColumn += 1
        }

        for colIdx in 0..<columnViews.count {
            let colStack = NSStackView(views: columnViews[colIdx])
            colStack.orientation = .vertical
            colStack.alignment = .leading
            colStack.spacing = 6
            checkboxGrid.addColumn(with: [colStack])
        }
        checkboxGrid.columnSpacing = 20


        monitoredSensorsGroup.contentView = checkboxGrid // Adiciona o grid ao box
        // Adicionar constraints para o contentView do NSBox (o checkboxGrid)
        if let contentView = monitoredSensorsGroup.contentView {
             contentView.translatesAutoresizingMaskIntoConstraints = false // importante
             NSLayoutConstraint.activate([
                 contentView.leadingAnchor.constraint(equalTo: monitoredSensorsGroup.contentViewMarginsGuide.leadingAnchor),
                 contentView.trailingAnchor.constraint(equalTo: monitoredSensorsGroup.contentViewMarginsGuide.trailingAnchor),
                 contentView.topAnchor.constraint(equalTo: monitoredSensorsGroup.contentViewMarginsGuide.topAnchor),
                 contentView.bottomAnchor.constraint(equalTo: monitoredSensorsGroup.contentViewMarginsGuide.bottomAnchor)
             ])
        }
        mainStackView.addArrangedSubview(monitoredSensorsGroup)
        NSLayoutConstraint.activate([
             monitoredSensorsGroup.widthAnchor.constraint(equalTo: mainStackView.widthAnchor)
        ])


        // --- Seção de Atribuição de Quadrantes (PopUps) ---
        let quadrantAssignmentGroup = NSBox()
        quadrantAssignmentGroup.title = "Atribuição aos Quadrantes"
        quadrantAssignmentGroup.translatesAutoresizingMaskIntoConstraints = false

        let quadrantStackView = NSStackView()
        quadrantStackView.orientation = .vertical
        quadrantStackView.alignment = .leading
        quadrantStackView.spacing = 10
        quadrantStackView.translatesAutoresizingMaskIntoConstraints = false

        quadrantPopUpButtons.removeAll() // Limpa para o caso de recarregar a UI
        labels.removeAll()

        for i in 1...4 {
            let label = NSTextField(labelWithString: "Sensor para Quadrante \(i):")
            label.translatesAutoresizingMaskIntoConstraints = false
            labels.append(label)

            let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
            popUpButton.translatesAutoresizingMaskIntoConstraints = false
            popUpButton.target = self
            popUpButton.action = #selector(quadrantPopUpButtonChanged(_:))
            popUpButton.tag = i
            quadrantPopUpButtons.append(popUpButton)

            let hStack = NSStackView(views: [label, popUpButton])
            hStack.orientation = .horizontal
            hStack.spacing = 8
            hStack.alignment = .centerY
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            popUpButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
             NSLayoutConstraint.activate([
                popUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
                label.widthAnchor.constraint(equalToConstant: 150)
            ])
            quadrantStackView.addArrangedSubview(hStack)
        }

        quadrantAssignmentGroup.contentView = quadrantStackView
        if let contentView = quadrantAssignmentGroup.contentView {
             contentView.translatesAutoresizingMaskIntoConstraints = false
             NSLayoutConstraint.activate([
                 contentView.leadingAnchor.constraint(equalTo: quadrantAssignmentGroup.contentViewMarginsGuide.leadingAnchor),
                 contentView.trailingAnchor.constraint(equalTo: quadrantAssignmentGroup.contentViewMarginsGuide.trailingAnchor),
                 contentView.topAnchor.constraint(equalTo: quadrantAssignmentGroup.contentViewMarginsGuide.topAnchor),
                 contentView.bottomAnchor.constraint(equalTo: quadrantAssignmentGroup.contentViewMarginsGuide.bottomAnchor)
             ])
        }
        mainStackView.addArrangedSubview(quadrantAssignmentGroup)
        NSLayoutConstraint.activate([
             quadrantAssignmentGroup.widthAnchor.constraint(equalTo: mainStackView.widthAnchor)
        ])
    }

    private func loadAndApplyUserSelections() {
        // 1. Carregar e aplicar estado das checkboxes de seleção de sensor
        let selectedKeys = AppSettings.shared.userSelectedSensorKeys
        for checkbox in sensorSelectionCheckboxes {
            if let sensorKey = checkbox.representedObject as? String {
                checkbox.state = selectedKeys.contains(sensorKey) ? .on : .off
            }
        }

        // 2. Popular os popups dos quadrantes com base nos sensores *agora disponíveis*
        //    (que já foram filtrados por userSelectedSensorKeys e disponibilidade real em loadSensorData)
        populateQuadrantPopUpButtons()

        // 3. Carregar e aplicar as seleções atuais para os quadrantes
        loadCurrentQuadrantSelections()
    }


    private func populateQuadrantPopUpButtons() {
        let noneSensor = Sensor(key: "", name: "Nenhum")

        for popUpButtonToPopulate in quadrantPopUpButtons {
            popUpButtonToPopulate.removeAllItems()
            popUpButtonToPopulate.addItem(withTitle: noneSensor.name)
            popUpButtonToPopulate.lastItem?.representedObject = noneSensor.key

            let currentQuadrantTag = popUpButtonToPopulate.tag
            var otherSelectedKeysInQuadrants: Set<String> = []
            for otherButton in quadrantPopUpButtons {
                if otherButton.tag == currentQuadrantTag { continue }
                if let otherKey = AppSettings.shared.sensorKey(forQuadrant: otherButton.tag), !otherKey.isEmpty {
                    otherSelectedKeysInQuadrants.insert(otherKey)
                }
            }

            let currentSensorKeyForThisPopUp = AppSettings.shared.sensorKey(forQuadrant: currentQuadrantTag)

            // Usar availableSensorsForQuadrants, que já está filtrado corretamente
            for sensor in availableSensorsForQuadrants {
                if !otherSelectedKeysInQuadrants.contains(sensor.key) || sensor.key == currentSensorKeyForThisPopUp {
                    popUpButtonToPopulate.addItem(withTitle: sensor.name)
                    popUpButtonToPopulate.lastItem?.representedObject = sensor.key
                }
            }
        }
    }

    private func loadCurrentQuadrantSelections() {
        for popUpButton in quadrantPopUpButtons {
            let quadrant = popUpButton.tag
            let savedKey = AppSettings.shared.sensorKey(forQuadrant: quadrant)

            if let key = savedKey, !key.isEmpty {
                // Verifica se a chave salva corresponde a um sensor em availableSensorsForQuadrants
                if availableSensorsForQuadrants.contains(where: { $0.key == key }) {
                    var foundAndSelected = false
                    for item in popUpButton.itemArray {
                        if let itemKey = item.representedObject as? String, itemKey == key {
                            popUpButton.select(item)
                            foundAndSelected = true
                            break
                        }
                    }
                    if !foundAndSelected {
                        print("Preferências: Chave salva '\(key)' para Q\(quadrant) não encontrada no popup. Definindo para Nenhum.")
                        popUpButton.selectItem(withTitle: "Nenhum")
                        // AppSettings.shared.setSensorKey(nil, forQuadrant: quadrant) // Opcional: limpar
                    }
                } else {
                    print("Preferências: Chave salva '\(key)' para Q\(quadrant) refere-se a um sensor não disponível/selecionado. Definindo para Nenhum.")
                    popUpButton.selectItem(withTitle: "Nenhum")
                    AppSettings.shared.setSensorKey(nil, forQuadrant: quadrant) // Limpa se não mais válido
                }
            } else {
                popUpButton.selectItem(withTitle: "Nenhum")
            }
        }
    }

    @objc private func sensorCheckboxChanged(_ sender: NSButton) {
        guard let sensorKey = sender.representedObject as? String else { return }

        var currentlySelectedKeys = AppSettings.shared.userSelectedSensorKeys
        if sender.state == .on {
            currentlySelectedKeys.insert(sensorKey)
        } else {
            currentlySelectedKeys.remove(sensorKey)

            // Se o sensor foi desmarcado, verificar se ele estava em uso em algum quadrante
            // e removê-lo (definir para "Nenhum").
            for i in 1...4 {
                if AppSettings.shared.sensorKey(forQuadrant: i) == sensorKey {
                    AppSettings.shared.setSensorKey(nil, forQuadrant: i)
                    // A notificação sensorSettingsDidChange será enviada por setSensorKey,
                    // o que fará com que handleSensorSettingsChange recarregue os popups.
                }
            }
        }
        AppSettings.shared.userSelectedSensorKeys = currentlySelectedKeys
        // A notificação userSelectedSensorsDidChange será postada por AppSettings.
        // O AppDelegate (e este VC) a observará para atualizar o que for necessário.
        // handleUserSelectedSensorsChange() será chamado aqui.
    }


    @objc private func quadrantPopUpButtonChanged(_ sender: NSPopUpButton) {
        let quadrant = sender.tag
        guard let selectedItem = sender.selectedItem else { return }
        let sensorKey = selectedItem.representedObject as? String

        AppSettings.shared.setSensorKey(sensorKey, forQuadrant: quadrant)
        // A notificação .sensorSettingsDidChange será postada por AppSettings.
        // handleSensorSettingsChange() será chamado para repopular e recarregar os popups.
        print("Preferências: Quadrante \(quadrant) definido para sensor key: '\(sensorKey ?? "nil")'")
    }

    // Chamado quando AppSettings.shared.setSensorKey é chamado (mudança em um quadrante)
    @objc func handleSensorSettingsChange(_ notification: Notification) {
        print("PreferencesVC: Notificação de mudança de sensor nos quadrantes recebida.")
        // Repopular os popups dos quadrantes e recarregar as seleções.
        // Não precisa recarregar availableSensorsForQuadrants aqui, pois a seleção de sensores ativos não mudou.
        populateQuadrantPopUpButtons()
        loadCurrentQuadrantSelections()
    }

    // Chamado quando AppSettings.shared.userSelectedSensorKeys é alterado
    @objc func handleUserSelectedSensorsChange(_ notification: Notification) {
        print("PreferencesVC: Notificação de mudança nos sensores selecionados pelo usuário recebida.")
        // 1. Atualizar a lista de sensores disponíveis para os quadrantes.
        refreshAvailableSensorsForQuadrants()
        // 2. (Opcional, mas bom para consistência) Recarregar o estado das checkboxes.
        //    Normalmente não é necessário se a mudança veio desta UI, mas seguro.
        let selectedKeys = AppSettings.shared.userSelectedSensorKeys
        for checkbox in sensorSelectionCheckboxes {
            if let sensorKey = checkbox.representedObject as? String {
                checkbox.state = selectedKeys.contains(sensorKey) ? .on : .off
            }
        }
        // A chamada para refreshAvailableSensorsForQuadrants() já cuida de repopular
        // os popups dos quadrantes e recarregar suas seleções.
    }
}
