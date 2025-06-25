import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var hardwareMonitor: HardwareMonitor?
    var statusItemView: StatusItemView?
    var menuManager: MenuManager?
    var preferencesWindowController: NSWindowController?
    var temperatureUpdateTimer: Timer?


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Registra os sensores padrão (se ainda não estiverem definidos)
        AppSettings.shared.registerDefaultSensorKeys()

        // Tenta inicializar o HardwareMonitor
        do {
            hardwareMonitor = try HardwareMonitor()
            print("HardwareMonitor inicializado com sucesso.")

            // Configura o MenuManager
            menuManager = MenuManager(appDelegate: self)

            // Configura o status item e a StatusItemView
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let item = statusItem, let manager = menuManager {
                statusItemView = StatusItemView(statusItem: item)
                // item.view = statusItemView // Depreciado
                if let button = item.button {
                    button.addSubview(statusItemView!) // Adiciona como subview do botão
                    // Ajusta o frame da statusItemView para preencher o botão, se necessário
                    // statusItemView?.frame = button.bounds // Ou defina constraints
                }
                item.menu = manager.createMenu()

                // Define o layout inicial da StatusItemView com base no AppSettings
                let initialLayout = AppSettings.shared.currentLayout
                statusItemView?.currentLayout = initialLayout
                // menuManager.updateLayoutMenuSelection() é chamado dentro de createMenu ou chamado explicitamente se necessário
                // para garantir que o menu reflita o estado correto APÓS ser criado.
                // No nosso caso, createMenu já chama updateLayoutMenuSelection.

                updateStatusItemViewWithCurrentSettings() // Carrega dados iniciais com base nas configurações
            } else {
                showSMCErrorAndTerminate(message: "Falha ao criar o NSStatusItem ou MenuManager.")
                return
            }

            // Adiciona observadores para mudanças de configuração
            addObservers()

            // Inicia o timer para atualização de temperatura
            startTemperatureUpdateTimer()

            print("Aplicativo iniciado. StatusItemView configurada. Observadores e Timer adicionados.")

        } catch let error as HardwareMonitor.SMCError {
            let errorMessage: String
            switch error {
            case .serviceNotFound:
                errorMessage = "O serviço AppleSMC não foi encontrado no sistema."
            case .connectionFailed:
                errorMessage = "Falha ao estabelecer conexão com o serviço AppleSMC."
            default:
                errorMessage = "Ocorreu um erro inesperado ao inicializar o monitor de hardware: \(error)"
            }
            showSMCErrorAndTerminate(message: errorMessage)
        } catch {
            showSMCErrorAndTerminate(message: "Ocorreu um erro desconhecido durante a inicialização: \(error.localizedDescription)")
        }
    }

    deinit {
        removeObservers()
        stopTemperatureUpdateTimer() // Garante que o timer pare se o AppDelegate for desalocado
    }

    private func addObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleLayoutChange(_:)),
                                               name: .layoutDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleSensorSettingsChange(_:)),
                                               name: .sensorSettingsDidChange,
                                               object: nil)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .layoutDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .sensorSettingsDidChange, object: nil)
    }

    @objc func handleLayoutChange(_ notification: Notification) {
        print("Notificação: Layout mudou.")
        if let newLayout = notification.object as? StatusItemView.LayoutMode {
            statusItemView?.currentLayout = newLayout
            menuManager?.updateLayoutMenuSelection() // Garante que o menu reflita a mudança
        } else {
            // Se o objeto da notificação não for o layout, pega de AppSettings
            statusItemView?.currentLayout = AppSettings.shared.currentLayout
            menuManager?.updateLayoutMenuSelection()
        }
        updateStatusItemViewWithCurrentSettings()
    }

    @objc func handleSensorSettingsChange(_ notification: Notification) {
        print("Notificação: Configurações de sensor mudaram.")
        // Opcionalmente, podemos verificar notification.object se for útil (ex: qual quadrante mudou)
        updateStatusItemViewWithCurrentSettings()
    }

    // Renomeada de updateStatusItemViewWithTestData para updateStatusItemViewWithCurrentSettings
    func updateStatusItemViewWithCurrentSettings() {
        guard let monitor = hardwareMonitor, let view = statusItemView else {
            statusItemView?.temperaturesToDisplay = []
            return
        }

        let activeSensorKeys = AppSettings.shared.getActiveSensorKeysForCurrentLayout()
        var tempsToShow: [StatusItemView.TemperatureDisplayInfo] = []

        print("Atualizando StatusItemView. Layout: \(view.currentLayout), Chaves de Sensor: \(activeSensorKeys.map { $0 ?? "nil" })")

        for (index, sensorKey) in activeSensorKeys.enumerated() {
            if let key = sensorKey, !key.isEmpty {
                if let sensor = HardwareMonitor.knownSensors.first(where: { $0.key == key }) {
                    do {
                        let temp = try monitor.readTemperature(key: sensor.key)
                        let tempString = "\(String(format: "%.0f", temp))°"
                        tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: tempString))
                        print("Lido: \(sensor.name) (\(key)): \(tempString) para slot \(index)")
                    } catch {
                        print("Falha ao ler \(sensor.name) (\(key)) para slot \(index): \(error)")
                        tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "ER°"))
                    }
                } else {
                    print("Sensor com chave '\(key)' não encontrado na lista knownSensors para slot \(index).")
                    tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "??°")) // Chave não encontrada
                }
            } else {
                // Nenhuma chave de sensor configurada para este slot
                tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "--°"))
            }
        }

        // Garante que temos o número certo de entradas para o layout, mesmo que algumas chaves não sejam encontradas
        // ou não configuradas. A StatusItemView já lida com desenhar placeholders se a lista for curta,
        // mas é bom ser explícito.
        let expectedCount = view.currentLayout.numberOfTemperatures
        while tempsToShow.count < expectedCount {
            tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "--°"))
        }

        view.temperaturesToDisplay = Array(tempsToShow.prefix(expectedCount))
    }

    func openPreferencesWindow() {
        print("AppDelegate: openPreferencesWindow() chamado.")

        if preferencesWindowController == nil {
            let preferencesVC = PreferencesViewController()
            // O título da janela pode ser definido no viewDidLoad do PreferencesViewController
            // ou aqui se preferir.
            // preferencesVC.title = "Preferências do Monitor de Temperatura" // Se o VC for gerenciar seu título

            let window = NSWindow(contentViewController: preferencesVC)
            window.title = "Preferências do Monitor de Temperatura"
            window.styleMask.remove(.resizable) // Janela não redimensionável
            window.styleMask.remove(.miniaturizable) // Não minimizável
            // window.styleMask.remove(.closable) // Se não quiser o botão de fechar padrão, mas geralmente é bom ter

            // Centralizar a janela (opcional)
            window.center()

            preferencesWindowController = NSWindowController(window: window)
        }

        preferencesWindowController?.showWindow(self)
        // Traz o aplicativo para a frente e foca na janela de preferências.
        // Isso é importante especialmente se o aplicativo não tiver um ícone no Dock.
        NSApp.activate(ignoringOtherApps: true)

        // Garante que a janela de preferências seja a janela principal ativa.
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Temperature Update Timer

    func startTemperatureUpdateTimer() {
        // Invalida qualquer timer existente para evitar múltiplos timers
        temperatureUpdateTimer?.invalidate()

        // Cria e agenda um novo timer
        // Usamos .main RunLoop para garantir que as atualizações da UI (feitas por updateStatusItemViewWithCurrentSettings)
        // ocorram na thread principal.
        temperatureUpdateTimer = Timer.scheduledTimer(timeInterval: 2.0, // 2 segundos
                                                      target: self,
                                                      selector: #selector(performTemperatureUpdate),
                                                      userInfo: nil,
                                                      repeats: true)

        // Adiciona o timer ao runloop no modo .common para que continue funcionando
        // mesmo quando menus estão abertos ou durante o rastreamento de eventos modais.
        if let timer = temperatureUpdateTimer {
            RunLoop.main.add(timer, forMode: .common)
            print("Timer de atualização de temperatura iniciado.")
        }
    }

    func stopTemperatureUpdateTimer() {
        temperatureUpdateTimer?.invalidate()
        temperatureUpdateTimer = nil
        print("Timer de atualização de temperatura parado.")
    }

    @objc func performTemperatureUpdate() {
        // print("Timer disparado: Atualizando temperaturas...") // Log verboso, pode ser removido
        updateStatusItemViewWithCurrentSettings()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("Aplicativo será encerrado.")
        removeObservers()
        stopTemperatureUpdateTimer() // Para o timer ao encerrar
    }
}
