import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var hardwareMonitor: HardwareMonitor?
    var statusItemView: StatusItemView?
    var menuManager: MenuManager?
    var preferencesWindowController: NSWindowController?
    var temperatureUpdateTimer: Timer?

    // Propriedade para o item da Touch Bar
    var touchBarItem: NSCustomTouchBarItem?
    let touchBarItemIdentifier = NSTouchBarItem.Identifier("com.example.TempMonitor.tempItem")
    var touchBarTempLabel: NSTextField?


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Habilita a customização da Touch Bar
        if #available(OSX 10.12.2, *) { // NSTouchBar é formalmente API a partir de 10.12.2
            NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true
        }

        // Tenta inicializar o HardwareMonitor PRIMEIRO, pois precisamos dos sensores disponíveis
        // para registrar os padrões em AppSettings.
        do {
            hardwareMonitor = try HardwareMonitor()
            print("HardwareMonitor inicializado com sucesso.")

            // Agora que o monitor está pronto, obtenha os sensores disponíveis
            let availableSensors = hardwareMonitor!.getAvailableSensors()
            print("AppDelegate: \(availableSensors.count) sensores disponíveis detectados.")

            // Registra os sensores padrão (se ainda não estiverem definidos),
            // passando os sensores disponíveis.
            AppSettings.shared.registerDefaultSensorKeys(availableSensors: availableSensors)

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

            // Configura a Touch Bar para a aplicação
            if #available(OSX 10.12.2, *) {
                // A chamada a makeTouchBar() será feita pelo sistema quando necessário,
                // devido à conformidade com NSTouchBarDelegate e isAutomaticCustomizeTouchBarMenuItemEnabled = true.
                // Para forçar a associação com NSApp imediatamente:
                NSApp.touchBar = self.makeTouchBar()
                print("Touch Bar configurada para NSApp.")
            }

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
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTouchBarSettingsChange(_:)),
                                               name: .touchBarSettingsDidChange,
                                               object: nil)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .layoutDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .sensorSettingsDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .touchBarSettingsDidChange, object: nil)
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
        updateTouchBarItem() // Atualiza a Touch Bar também
    }

    @objc func handleTouchBarSettingsChange(_ notification: Notification) {
        print("Notificação: Configurações da Touch Bar mudaram.")
        if #available(OSX 10.12.2, *) {
            // Reconstruir ou atualizar a Touch Bar da aplicação
            NSApp.touchBar = self.makeTouchBar() // Força a reconstrução
            updateTouchBarItem() // Garante que o conteúdo seja atualizado
        }
    }


    // Renomeada de updateStatusItemViewWithTestData para updateStatusItemViewWithCurrentSettings
    func updateStatusItemViewWithCurrentSettings() {
        guard let monitor = hardwareMonitor, let view = statusItemView else {
            statusItemView?.temperaturesToDisplay = []
            // Se não houver view de status, não há nada a fazer na Touch Bar também (ou definimos um padrão)
            if #available(OSX 10.12.2, *) {
                touchBarTempLabel?.stringValue = "--°" // Atualiza o label diretamente
            }
            return
        }

        let activeSensorKeys = AppSettings.shared.getActiveSensorKeysForCurrentLayout()
        var tempsToShow: [StatusItemView.TemperatureDisplayInfo] = []

        // Lógica para determinar qual temperatura mostrar na Touch Bar
        var tempForTouchBar: String? = nil
        if AppSettings.shared.showInTouchBar {
            if let touchBarKey = AppSettings.shared.touchBarSensorKey, !touchBarKey.isEmpty {
                if let sensorInfo = HardwareMonitor.potentialSensors.first(where: { $0.key == touchBarKey }) {
                    do {
                        let temp = try monitor.readTemperature(key: sensorInfo.key)
                        tempForTouchBar = "\(String(format: "%.0f", temp))°"
                    } catch {
                        tempForTouchBar = "ER°"
                    }
                } else {
                    tempForTouchBar = "??°" // Chave configurada mas sensor não encontrado
                }
            } else {
                // Se nenhuma chave específica para Touch Bar, usa a lógica de fallback (primeiro sensor do layout)
                // Esta lógica de fallback é movida para DENTRO do loop de activeSensorKeys
            }
        }


        print("Atualizando StatusItemView. Layout: \(view.currentLayout), Chaves de Sensor: \(activeSensorKeys.map { $0 ?? "nil" })")

        var firstValidTempFromLayout: String? = nil // Para fallback da Touch Bar

        for (index, sensorKey) in activeSensorKeys.enumerated() {
            if let key = sensorKey, !key.isEmpty {
                let sensorInfo = HardwareMonitor.potentialSensors.first { $0.key == key }

                if let currentSensor = sensorInfo {
                    do {
                        let temp = try monitor.readTemperature(key: currentSensor.key)
                        let tempString = "\(String(format: "%.0f", temp))°"
                        tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: tempString))
                        if firstValidTempFromLayout == nil { // Pega a primeira temperatura válida do layout para fallback
                            firstValidTempFromLayout = tempString
                        }
                        print("Lido: \(currentSensor.name) (\(key)): \(tempString) para slot \(index)")
                    } catch {
                        print("Falha ao ler \(currentSensor.name) (\(key)) para slot \(index): \(error)")
                        tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "ER°"))
                        if firstValidTempFromLayout == nil { firstValidTempFromLayout = "ER°" }
                    }
                } else {
                    print("Sensor com chave '\(key)' não encontrado na lista potentialSensors para slot \(index).")
                    tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "??°"))
                     if firstValidTempFromLayout == nil { firstValidTempFromLayout = "??°" }
                }
            } else {
                tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "--°"))
                if firstValidTempFromLayout == nil { firstValidTempFromLayout = "--°" }
            }
        }

        let expectedCount = view.currentLayout.numberOfTemperatures
        while tempsToShow.count < expectedCount {
            tempsToShow.append(StatusItemView.TemperatureDisplayInfo(stringValue: "--°"))
        }

        view.temperaturesToDisplay = Array(tempsToShow.prefix(expectedCount))

        // Define o valor final para a Touch Bar
        if AppSettings.shared.showInTouchBar {
            let finalTouchBarTemp = tempForTouchBar ?? firstValidTempFromLayout ?? "--°"
            if #available(OSX 10.12.2, *) {
                touchBarTempLabel?.stringValue = finalTouchBarTemp
            }
        } else {
             if #available(OSX 10.12.2, *) {
                // Se não for para mostrar, podemos limpar o label ou o AppDelegate.makeTouchBar
                // pode retornar nil para o item se showInTouchBar for false.
                // Por enquanto, limpar o label. A lógica de não mostrar o item está em makeTouchBar.
                touchBarTempLabel?.stringValue = ""
            }
        }
    }

    @available(OSX 10.12.2, *)
    func updateTouchBarItem() {
        // Esta função agora pode ser mais simples, pois a lógica de leitura está em updateStatusItemViewWithCurrentSettings
        // Apenas garantimos que o label da Touch Bar seja atualizado.
        // A chamada a updateStatusItemViewWithCurrentSettings já deve ter atualizado o `touchBarTempLabel`.
        // Se precisarmos de lógica separada para a Touch Bar (ex: sensor diferente), adicionaremos aqui.
        // Por enquanto, a atualização do label já acontece em `updateStatusItemViewWithCurrentSettings`.
        // Esta função pode ser chamada explicitamente se precisarmos de uma atualização da Touch Bar
        // independente da StatusItemView.
        print("Touch Bar update requested (label should have been updated by updateStatusItemViewWithCurrentSettings)")
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
        // A atualização da Touch Bar já está incluída em updateStatusItemViewWithCurrentSettings
        // ou pode ser chamada separadamente se necessário:
        // if #available(OSX 10.12.2, *) {
        //    updateTouchBarTemperature()
        // }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("Aplicativo será encerrado.")
        removeObservers()
        stopTemperatureUpdateTimer() // Para o timer ao encerrar
    }
}

// MARK: - NSTouchBarDelegate
@available(OSX 10.12.2, *)
extension AppDelegate: NSTouchBarDelegate {
    func makeTouchBar() -> NSTouchBar? {
        // Só cria a Touch Bar se a configuração permitir
        guard AppSettings.shared.showInTouchBar else {
            // Retornar nil aqui efetivamente desabilita a touch bar customizada para o app
            // ou previne que ela seja mostrada se já estava visível.
            return nil
        }

        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = .appTouchBar
        // Adiciona o item de temperatura. O item em si será fornecido por touchBar(_:makeItemForIdentifier:)
        touchBar.defaultItemIdentifiers = [touchBarItemIdentifier, .flexibleSpace]
        touchBar.customizationAllowedItemIdentifiers = [touchBarItemIdentifier]

        // É importante que o label seja atualizado quando a touch bar é criada.
        // updateStatusItemViewWithCurrentSettings() é chamado em vários lugares,
        // incluindo no final de applicationDidFinishLaunching e quando as configurações mudam,
        // o que deve cobrir a atualização do label.
        // Se makeTouchBar é chamado e o label ainda não existe, touchBar(_:makeItemForIdentifier:) irá criá-lo.
        // E a próxima chamada a updateStatusItemViewWithCurrentSettings irá popular o valor.
        // Para garantir que o valor seja o mais recente possível ao mostrar a TouchBar:
        updateStatusItemViewWithCurrentSettings()


        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        // Não retorna o item se a configuração showInTouchBar for false.
        // A verificação em makeTouchBar() já deve prevenir a chamada aqui se showInTouchBar for false
        // e makeTouchBar retornar nil. Mas uma verificação dupla não faz mal.
        guard AppSettings.shared.showInTouchBar else {
            return nil
        }

        if identifier == touchBarItemIdentifier {
            // Reutiliza o item e o label se já existirem, caso contrário, cria-os.
            if touchBarItem == nil || touchBarTempLabel == nil {
                let label = NSTextField(labelWithString: "--°") // Valor inicial padrão
                label.textColor = .white // Ajuste a cor conforme necessário
                // Outras configurações de aparência podem ser adicionadas aqui (fonte, alinhamento)
                // label.font = NSFont.systemFont(ofSize: 14)
                // label.alignment = .center

                touchBarTempLabel = label // Mantém a referência ao label para atualizações

                let customItem = NSCustomTouchBarItem(identifier: identifier)
                customItem.view = label
                customItem.customizationLabel = "Temperatura" // Usado para customização da Touch Bar pelo usuário
                touchBarItem = customItem
            }

            // O valor do label é atualizado por updateStatusItemViewWithCurrentSettings().
            // Se o item está sendo criado agora, ele terá "--°" e será atualizado na próxima vez
            // que updateStatusItemViewWithCurrentSettings() for chamado.
            return touchBarItem
        }
        return nil
    }
}

// Adiciona um identificador para a nossa Touch Bar customizada
@available(OSX 10.12.2, *)
extension NSTouchBar.CustomizationIdentifier {
    static let appTouchBar = NSTouchBar.CustomizationIdentifier("com.example.TempMonitor.appTouchBar")
}

// Se o NSWindow não tiver um TouchBarProvider, o AppDelegate pode ser o provedor global.
// Para isso, a janela principal precisaria ter seu `touchBar` configurado
// ou o AppDelegate precisaria implementar `touchBar(makeItemForIdentifier:)` de forma global
// ou ser o `NSTouchBarProvider` da janela.
// A forma mais simples para um app de barra de status é deixar o NSApplication gerenciar.
// Para que o makeTouchBar() do AppDelegate seja chamado, precisamos que uma janela o peça.
// Como este é um app de barra de status sem janela principal visível por padrão,
// a Touch Bar mostrada será a do sistema ou do app em foco.
// Para ter uma Touch Bar global para o nosso app, precisaríamos de uma janela (mesmo que oculta)
// ou usar APIs mais avançadas para itens globais da Touch Bar (DFRSystemModalShowsCloseBoxWhenFrontMost).

// No entanto, para apps baseados em NSWindow, você faria window.touchBar = makeTouchBar()
// No nosso caso, como é um app de menu bar, a Touch Bar será associada ao NSApplication.
// O `NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true` e a conformidade
// do AppDelegate com NSTouchBarDelegate (e a implementação de makeTouchBar())
// deve ser suficiente para que o sistema apresente a Touch Bar quando o app estiver ativo
// (por exemplo, quando o menu está aberto ou a janela de preferências).

// Para que a Touch Bar apareça de forma mais persistente associada ao app,
// mesmo sem uma janela visível, é um cenário mais complexo.
// O comportamento padrão é a Touch Bar mudar com o app em primeiro plano.
// Se quisermos um "control strip item" global, isso requer uma abordagem diferente
// (geralmente via `DFRFoundation.framework` de forma privada, ou `NSControlStripTouchBarItem`
// se fosse um app com janela principal).

// Para o propósito deste exercício, assumiremos que a Touch Bar aparecerá
// quando o aplicativo tiver algum tipo de foco (menu aberto, janela de preferências).
// A ativação `NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true`
// e a implementação de `makeTouchBar()` no AppDelegate é o caminho padrão.
// Precisamos garantir que o `NSApp` (NSApplication.shared) tenha sua `touchBar`
// propriedade configurada em `applicationDidFinishLaunching`.

// Adicionando a configuração da touchBar para NSApp:
// Esta linha deve ser adicionada no final de applicationDidFinishLaunching
// if #available(OSX 10.12.2, *) {
// NSApp.touchBar = makeTouchBar()
// }
// Isso garante que o AppDelegate forneça a Touch Bar para a aplicação.
