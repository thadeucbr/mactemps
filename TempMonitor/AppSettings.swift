import Foundation

// Notificação para quando as configurações de sensores mudarem
extension Notification.Name {
    static let sensorSettingsDidChange = Notification.Name("sensorSettingsDidChangeNotification")
}

class AppSettings {

    static let shared = AppSettings() // Singleton para fácil acesso

    // Chaves para UserDefaults
    private enum Keys {
        static let selectedLayout = "appSettingSelectedLayout"
        static let sensorKeyForQuadrant1 = "appSettingSensorKeyQ1"
        static let sensorKeyForQuadrant2 = "appSettingSensorKeyQ2"
        static let sensorKeyForQuadrant3 = "appSettingSensorKeyQ3"
        static let sensorKeyForQuadrant4 = "appSettingSensorKeyQ4"
    }

    // MARK: - Layout Setting
    var currentLayout: StatusItemView.LayoutMode {
        get {
            // O valor 0 será o padrão se nada estiver salvo.
            // Mapeamos 0 para .dualQuadrant como um padrão razoável.
            // 1 -> single, 2 -> dual, 4 -> quad
            let savedValue = UserDefaults.standard.integer(forKey: Keys.selectedLayout)
            switch savedValue {
            case 1: return .singleQuadrant
            case 2: return .dualQuadrant
            case 4: return .quadQuadrant
            default: return .dualQuadrant // Padrão se não salvo ou valor inválido
            }
        }
        set {
            let valueToSave: Int
            switch newValue {
            case .singleQuadrant: valueToSave = 1
            case .dualQuadrant: valueToSave = 2
            case .quadQuadrant: valueToSave = 4
            }
            UserDefaults.standard.set(valueToSave, forKey: Keys.selectedLayout)
            // Postar notificação de mudança de layout (pode ser redundante se o MenuManager já faz,
            // mas bom para consistência se AppSettings for alterado de outro lugar)
            NotificationCenter.default.post(name: .layoutDidChange, object: newValue)
        }
    }

    // MARK: - Sensor Selection for Quadrants

    // Retorna a chave do sensor para um quadrante específico (1 a 4)
    func sensorKey(forQuadrant quadrant: Int) -> String? {
        guard quadrant >= 1 && quadrant <= 4 else { return nil }
        let key: String
        switch quadrant {
        case 1: key = Keys.sensorKeyForQuadrant1
        case 2: key = Keys.sensorKeyForQuadrant2
        case 3: key = Keys.sensorKeyForQuadrant3
        case 4: key = Keys.sensorKeyForQuadrant4
        default: return nil // Impossível
        }
        return UserDefaults.standard.string(forKey: key)
    }

    // Define a chave do sensor para um quadrante específico
    func setSensorKey(_ sensorKey: String?, forQuadrant quadrant: Int) {
        guard quadrant >= 1 && quadrant <= 4 else { return }
        let key: String
        switch quadrant {
        case 1: key = Keys.sensorKeyForQuadrant1
        case 2: key = Keys.sensorKeyForQuadrant2
        case 3: key = Keys.sensorKeyForQuadrant3
        case 4: key = Keys.sensorKeyForQuadrant4
        default: return // Impossível
        }
        UserDefaults.standard.set(sensorKey, forKey: key) // Salva nil se sensorKey for nil (para "nenhum")
        NotificationCenter.default.post(name: .sensorSettingsDidChange, object: quadrant) // Envia o quadrante modificado
    }

    // MARK: - Default Sensor Assignments

    // Define os sensores padrão se nenhum estiver configurado
    func registerDefaultSensorKeys() {
        // Padrão: Q1=CPU Proximity, Q2=GPU Diode. Q3 e Q4 vazios.
        if UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant1) == nil &&
           UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant2) == nil &&
           UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant3) == nil &&
           UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant4) == nil {

            print("AppSettings: Registrando chaves de sensores padrão.")
            // Tenta pegar as chaves reais dos sensores conhecidos (usando nomes traduzidos)
            let defaultQ1Key = HardwareMonitor.knownSensors.first { $0.name.contains("Proximidade da CPU") }?.key ?? "TC0P"
            let defaultQ2Key = HardwareMonitor.knownSensors.first { $0.name.contains("Diodo da GPU") }?.key ?? "TG0D"

            setSensorKey(defaultQ1Key, forQuadrant: 1)
            setSensorKey(defaultQ2Key, forQuadrant: 2)
            setSensorKey(nil, forQuadrant: 3) // Nenhum por padrão
            setSensorKey(nil, forQuadrant: 4) // Nenhum por padrão
        }
    }

    // MARK: - Helper to get sensor keys for current layout

    // Retorna uma lista de chaves de sensores (String?) para os slots ativos do layout atual.
    // O tamanho da lista corresponde ao número de temperaturas do layout.
    func getActiveSensorKeysForCurrentLayout() -> [String?] {
        let layout = currentLayout
        var keys: [String?] = []

        switch layout {
        case .singleQuadrant:
            keys.append(sensorKey(forQuadrant: 1))
        case .dualQuadrant:
            keys.append(sensorKey(forQuadrant: 1))
            keys.append(sensorKey(forQuadrant: 2))
        case .quadQuadrant:
            keys.append(sensorKey(forQuadrant: 1))
            keys.append(sensorKey(forQuadrant: 2))
            keys.append(sensorKey(forQuadrant: 3))
            keys.append(sensorKey(forQuadrant: 4))
        }
        return keys
    }


    // Inicializador privado para o singleton
    private init() {
        // Poderia registrar padrões aqui, mas é melhor chamar explicitamente no AppDelegate
        // para garantir que HardwareMonitor.knownSensors esteja acessível se necessário.
    }
}
