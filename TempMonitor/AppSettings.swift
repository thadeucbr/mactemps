import Foundation

// Notificação para quando as configurações de sensores mudarem
extension Notification.Name {
    static let sensorSettingsDidChange = Notification.Name("sensorSettingsDidChangeNotification")
    static let userSelectedSensorsDidChange = Notification.Name("userSelectedSensorsDidChangeNotification") // Nova notificação
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
        static let userSelectedSensorKeys = "appSettingUserSelectedSensorKeys" // Nova chave
    }

    // MARK: - User Selected Sensors
    var userSelectedSensorKeys: Set<String> {
        get {
            // Carrega as chaves salvas. Se não houver nada salvo (primeira execução), retorna um conjunto vazio.
            // A lógica de inicialização padrão será tratada no AppDelegate ou similar,
            // onde temos acesso à lista de `potentialSensors`.
            let savedKeys = UserDefaults.standard.array(forKey: Keys.userSelectedSensorKeys) as? [String]
            return Set(savedKeys ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Keys.userSelectedSensorKeys)
            NotificationCenter.default.post(name: .userSelectedSensorsDidChange, object: nil)
        }
    }

    // Método para registrar os padrões iniciais para userSelectedSensorKeys
    // Deve ser chamado uma vez, por exemplo, pelo AppDelegate, se nenhuma configuração for encontrada.
    func registerDefaultUserSelectedSensorKeys(potentialSensorKeys: [String]) {
        if UserDefaults.standard.object(forKey: Keys.userSelectedSensorKeys) == nil {
            print("AppSettings: Registrando conjunto padrão de userSelectedSensorKeys (todos os potenciais).")
            userSelectedSensorKeys = Set(potentialSensorKeys)
        }
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
    // Agora precisa de acesso ao HardwareMonitor para obter sensores disponíveis.
    // Isso é um pouco problemático para uma classe de configurações puras.
    // Idealmente, o AppDelegate chamaria isso e passaria os sensores disponíveis.
    // Por enquanto, vamos assumir que podemos acessá-los, mas isso pode precisar de refatoração.
    func registerDefaultSensorKeys(availableSensors: [Sensor]) {
        // Padrão: Q1=CPU Proximity, Q2=GPU Diode. Q3 e Q4 vazios.
        if UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant1) == nil &&
           UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant2) == nil &&
           UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant3) == nil &&
           UserDefaults.standard.string(forKey: Keys.sensorKeyForQuadrant4) == nil {

            print("AppSettings: Registrando chaves de sensores padrão com base nos sensores disponíveis.")

            // Tenta encontrar os sensores preferidos na lista de disponíveis
            let preferredQ1Name = "Proximidade da CPU"
            let preferredQ2Name = "Diodo da GPU"

            var defaultQ1Key: String? = availableSensors.first { $0.name == preferredQ1Name }?.key
            var defaultQ2Key: String? = availableSensors.first { $0.name == preferredQ2Name }?.key

            // Fallback se os preferidos não estiverem disponíveis
            if defaultQ1Key == nil && !availableSensors.isEmpty {
                defaultQ1Key = availableSensors[0].key // Pega o primeiro disponível
            }
            if defaultQ2Key == nil && availableSensors.count > 1 {
                // Tenta pegar um segundo sensor diferente do Q1, se possível
                if defaultQ1Key != nil && availableSensors[1].key != defaultQ1Key {
                    defaultQ2Key = availableSensors[1].key
                } else if availableSensors.count > 1 && availableSensors[0].key != defaultQ1Key {
                     defaultQ2Key = availableSensors[0].key // Se Q1 pegou o primeiro, e há outro.
                } else if availableSensors.count > 1 { // Pega o segundo se Q1 não for o primeiro
                     defaultQ2Key = availableSensors[1].key
                }
                 // Se Q1 pegou o primeiro e só há um sensor, Q2 ficará nil.
            }
            // Garante que Q1 e Q2 não sejam o mesmo sensor se ambos foram definidos por fallback
            if defaultQ1Key != nil && defaultQ1Key == defaultQ2Key {
                if availableSensors.count > 1 { // Se há outro sensor para Q2
                    let q1Sensor = availableSensors.first { $0.key == defaultQ1Key }
                    if let nextSensor = availableSensors.first(where: { $0.key != q1Sensor?.key }) {
                        defaultQ2Key = nextSensor.key
                    } else {
                        defaultQ2Key = nil // Não há outro sensor diferente para Q2
                    }
                } else {
                    defaultQ2Key = nil // Só um sensor disponível, Q2 fica sem.
                }
            }


            print("AppSettings: Padrão Q1: \(defaultQ1Key ?? "Nenhum"), Padrão Q2: \(defaultQ2Key ?? "Nenhum")")
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
