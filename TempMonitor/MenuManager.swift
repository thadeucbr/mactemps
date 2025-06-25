import Cocoa

// Notificação para quando o layout mudar através do menu
extension Notification.Name {
    static let layoutDidChange = Notification.Name("layoutDidChangeNotification")
}

class MenuManager: NSObject { // Precisa ser NSObject para ser target de NSMenuItem

    private weak var appDelegate: AppDelegate? // Para acessar statusItemView e outras coisas se necessário

    // Não precisamos mais da chave de layout aqui, será gerenciada por AppSettings.

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let layoutSubmenu = NSMenu()
        let layoutMenuItem = NSMenuItem(title: "Layout de Exibição", action: nil, keyEquivalent: "")

        let singleQuadrantItem = NSMenuItem(title: "1 Quadrante", action: #selector(selectLayout(_:)), keyEquivalent: "")
        singleQuadrantItem.target = self
        singleQuadrantItem.representedObject = StatusItemView.LayoutMode.singleQuadrant
        layoutSubmenu.addItem(singleQuadrantItem)

        let dualQuadrantItem = NSMenuItem(title: "2 Quadrantes", action: #selector(selectLayout(_:)), keyEquivalent: "")
        dualQuadrantItem.target = self
        dualQuadrantItem.representedObject = StatusItemView.LayoutMode.dualQuadrant
        layoutSubmenu.addItem(dualQuadrantItem)

        let quadQuadrantItem = NSMenuItem(title: "4 Quadrantes", action: #selector(selectLayout(_:)), keyEquivalent: "")
        quadQuadrantItem.target = self
        quadQuadrantItem.representedObject = StatusItemView.LayoutMode.quadQuadrant
        layoutSubmenu.addItem(quadQuadrantItem)

        menu.addItem(layoutMenuItem)
        menu.setSubmenu(layoutSubmenu, for: layoutMenuItem)

        updateLayoutMenuSelection() // Define a marca de seleção inicial

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(title: "Preferências...", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Sair do Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    // Removido: currentSavedLayout() - será usado AppSettings.shared.currentLayout

    @objc func selectLayout(_ sender: NSMenuItem) {
        guard let newLayout = sender.representedObject as? StatusItemView.LayoutMode else { return }

        // Define o layout através do AppSettings, que cuidará de salvar e notificar.
        AppSettings.shared.currentLayout = newLayout

        // A StatusItemView deve observar a notificação .layoutDidChange ou ser atualizada pelo AppDelegate
        // appDelegate?.statusItemView?.currentLayout = newLayout // Isso será feito pelo observador da notificação

        updateLayoutMenuSelection() // Atualiza a marca de seleção no menu

        // A notificação .layoutDidChange é postada por AppSettings.shared.currentLayout = newLayout
        // O AppDelegate vai observar isso e chamar updateStatusItemViewWithCurrentSettings()
        // appDelegate?.updateStatusItemViewWithTestData() // Não é mais necessário chamar diretamente daqui
    }

    func updateLayoutMenuSelection() {
        guard let layoutMenu = appDelegate?.statusItem?.menu?.item(withTitle: "Layout de Exibição")?.submenu else { return }
        // Usa o layout de AppSettings para determinar a seleção
        let selectedLayout = AppSettings.shared.currentLayout

        for item in layoutMenu.items {
            if let itemLayout = item.representedObject as? StatusItemView.LayoutMode {
                item.state = (itemLayout == selectedLayout) ? .on : .off
            }
        }
    }

    @objc func openPreferences(_ sender: NSMenuItem) {
        // A lógica para abrir a janela de preferências virá aqui
        print("Ação: Abrir Preferências...")
        appDelegate?.openPreferencesWindow()
    }
}
