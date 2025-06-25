import IOKit
import Cocoa // Para NSAlert

// Estrutura para representar um sensor
struct Sensor: Hashable, Identifiable {
    let id = UUID() // Para conformar com Identifiable, útil para listas em UI se necessário
    let key: String   // Chave SMC (FourCharCode)
    let name: String  // Nome amigável para o usuário
}

class HardwareMonitor {

    // Lista de sensores conhecidos
    // Referência para chaves comuns: https://github.com/exelban/stats/blob/master/shared/modules/sensors/types.swift
    static let knownSensors: [Sensor] = [
        Sensor(key: "TC0P", name: "Proximidade da CPU"),
        Sensor(key: "TC0D", name: "Diodo da CPU"),
        Sensor(key: "TC0H", name: "Dissipador da CPU"),
        Sensor(key: "TC1C", name: "Núcleo CPU 1"),
        Sensor(key: "TC2C", name: "Núcleo CPU 2"),
        Sensor(key: "TCGC", name: "Gráficos da CPU"),
        Sensor(key: "TG0P", name: "Proximidade da GPU"),
        Sensor(key: "TG0D", name: "Diodo da GPU"),
        Sensor(key: "TG0H", name: "Dissipador da GPU"),
        Sensor(key: "TM0P", name: "Proximidade da Memória"),
        Sensor(key: "TM0S", name: "Slot de Memória 1"),
        Sensor(key: "TS0S", name: "Controlador SSD"),
        Sensor(key: "TA0P", name: "Temperatura Ambiente"),
        Sensor(key: "Th0H", name: "Heatpipe Principal 1"),
        Sensor(key: "Tp0P", name: "Proximidade da Fonte")
    ]

    private var connection: io_connect_t = 0
    private let SMCOpenSource = "com.apple.driver.AppleSMC" // Fonte alternativa comum

    enum SMCError: Error {
        case serviceNotFound
        case connectionFailed
        case keyNotFound(String)
        case readFailed(String, kern_return_t)
        case unknownFormat(String)
    }

    init() throws {
        var iterator: io_iterator_t = 0
        var result: kern_return_t

        // Encontrar o serviço AppleSMC
        let matchingDictionary = IOServiceMatching("AppleSMC")
        result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDictionary, &iterator)

        if result != kIOReturnSuccess {
            print("Erro: Serviço AppleSMC não encontrado. Código: \(result)")
            throw SMCError.serviceNotFound
        }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        if device == 0 {
            print("Erro: Nenhum dispositivo AppleSMC encontrado.")
            // Tentar uma fonte alternativa se a primária falhar
            let matchingAlt = IOServiceNameMatching(SMCOpenSource)
            result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingAlt, &iterator)
            if result != kIOReturnSuccess {
                print("Erro: Serviço \(SMCOpenSource) não encontrado. Código: \(result)")
                throw SMCError.serviceNotFound
            }
            let deviceAlt = IOIteratorNext(iterator)
            IOObjectRelease(iterator)
            if deviceAlt == 0 {
                print("Erro: Nenhum dispositivo \(SMCOpenSource) encontrado.")
                throw SMCError.serviceNotFound
            }
             result = IOServiceOpen(deviceAlt, mach_task_self_, 0, &connection)
             IOObjectRelease(deviceAlt)
        } else {
             result = IOServiceOpen(device, mach_task_self_, 0, &connection)
             IOObjectRelease(device)
        }


        if result != kIOReturnSuccess {
            print("Erro: Falha ao abrir conexão com AppleSMC. Código: \(result)")
            self.connection = 0 // Garante que a conexão é inválida
            throw SMCError.connectionFailed
        }
        print("HardwareMonitor: Conexão com AppleSMC estabelecida.")
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
            print("HardwareMonitor: Conexão com AppleSMC fechada.")
        }
    }

    private func FourCharCode(fromString str: String) -> UInt32 {
        var result: UInt32 = 0
        if str.count == 4 {
            for char_big_endian in str.utf8 {
                result = (result << 8) + UInt32(char_big_endian)
            }
        }
        return result
    }

    // Estrutura para comunicação com SMC
    // Baseado em https://github.com/beltex/SMCKit/blob/master/SMCKit/SMC.swift
    private struct SMCParamStruct {
        var key: UInt32                 // Chave do sensor (FourCharCode)
        var vers = SMCVersion()         // Não usado para leitura simples de temperatura
        var pLimitData = SMCPLimitData()// Não usado
        var keyInfo = SMCKeyInfoData()  // Informações sobre a chave (tipo, tamanho)
        var padding: UInt16 = 0         // Preenchimento
        var result: UInt8 = 0           // Resultado da operação
        var status: UInt8 = 0           // Status da operação
        var data8: UInt8 = 0            // Dado (se for 1 byte)
        var data32: UInt32 = 0          // Dado (se for 4 bytes)
        var bytes = SMCBytes()          // Buffer para dados (até 32 bytes)
    }

    private struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: IOByteCount = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    // Precisamos de um tipo C-style array para SMCBytes
    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )


    private func callSMC(inputStruct: inout SMCParamStruct, selector: UInt8) -> kern_return_t {
        var outputStruct = SMCParamStruct() // Estrutura de saída
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        // IOConnectCallStructMethod não está diretamente disponível em Swift puro para todas as versões.
        // A maneira mais comum de chamar é através de `IOConnectCallMethod` ou `IOConnectCallScalarMethod`
        // quando possível, ou definindo um wrapper se `IOConnectCallStructMethod` for estritamente necessário.
        // Para ler chaves, `kSMCReadKey` (selector 2) é usado com `SMCParamStruct`.

        // Usaremos IOConnectCallStructMethod que é mais seguro para essa estrutura.
        // No entanto, sua disponibilidade direta em Swift pode ser limitada sem um bridging header ou wrapper.
        // Para este exemplo, vamos assumir que podemos chamá-lo.
        // Se ocorrerem problemas de compilação aqui, pode ser necessário um wrapper C.

        // Temporariamente usando IOConnectCallMethod que é mais simples de chamar de Swift,
        // mas pode não ser o ideal para estruturas complexas.
        // Para kSMCReadKey, o selector é 5. Para kSMCWriteKey é 6.
        // Para kSMCGetKeyInfo é 9.
        // A chamada correta para ler uma chave geralmente envolve kSMCUserClientOpen, depois kSMCReadKey.
        // A struct SMCParamStruct é usada com selector kSMCHandleYPCEvent (ou similar, dependendo da ação)
        // quando se usa IOConnectCallStructMethod.

        // Selector para ler chave: kSMCReadKey (valor 5)
        // Selector para obter informações da chave: kSMCGetKeyInfo (valor 9)

        let result = IOConnectCallStructMethod(connection,
                                               UInt32(selector), // Selector para a chamada SMC
                                               &inputStruct,     // Ponteiro para a estrutura de entrada
                                               inputSize,        // Tamanho da estrutura de entrada
                                               &outputStruct,    // Ponteiro para a estrutura de saída
                                               &outputSize)      // Tamanho da estrutura de saída

        if result == kIOReturnSuccess {
            inputStruct.result = outputStruct.result // Copia o resultado da operação SMC
            inputStruct.keyInfo = outputStruct.keyInfo
            inputStruct.bytes = outputStruct.bytes
        }
        return result
    }

    func getSensorInfo(key: String) throws -> SMCKeyInfoData {
        var input = SMCParamStruct()
        input.key = FourCharCode(fromString: key)
        input.data8 = UInt8(kSMCGetKeyInfo) // kSMCGetKeyInfo (const 9)

        let kernResult = callSMC(inputStruct: &input, selector: 2) // kSMCUserClientSmc Rautine

        if kernResult != kIOReturnSuccess {
            throw SMCError.readFailed("getSensorInfo (callSMC)", kernResult)
        }
        if input.result != KSMCSuccess { // KSMCSuccess é 0
             throw SMCError.keyNotFound("getSensorInfo, key: \(key), smc result: \(input.result)")
        }
        return input.keyInfo
    }


    func readTemperature(key: String) throws -> Double {
        guard connection != 0 else {
            print("Erro: Tentativa de ler temperatura sem conexão SMC válida.")
            throw SMCError.connectionFailed
        }

        var input = SMCParamStruct()
        input.key = FourCharCode(fromString: key)

        // Primeiro, obtemos informações sobre a chave para saber o tipo e tamanho
        do {
            let keyInfo = try getSensorInfo(key: key)
            input.keyInfo.dataSize = keyInfo.dataSize
            input.keyInfo.dataType = keyInfo.dataType
        } catch {
            // Se getSensorInfo falhar, não podemos prosseguir
            print("Falha ao obter informações para a chave \(key): \(error)")
            throw error // Re-throw o erro de getSensorInfo
        }

        // input.data8 = UInt8(kSMCReadKey) // kSMCReadKey (const 5)
        // A chamada de leitura usa o selector 2 (kSMCUserClientSmc) e o data8 como sub-comando.
        input.data8 = UInt8(kSMCReadKey)


        let kernResult = callSMC(inputStruct: &input, selector: 2) // kSMCUserClientSmc Routine

        if kernResult != kIOReturnSuccess {
            print("Erro ao ler chave SMC \(key) (chamada SMC). Código: \(kernResult)")
            throw SMCError.readFailed(key, kernResult)
        }

        if input.result != KSMCSuccess { // KSMCSuccess é 0
            // Este erro é mais específico do SMC, indicando que a chave pode não existir ou não ser legível
            print("Erro específico do SMC ao ler a chave \(key). Resultado SMC: \(input.result)")
            throw SMCError.keyNotFound(key)
        }


        // Verificar o tipo de dado retornado pela keyInfo
        // Tipos comuns: "flt ", "sp78", "ui16", "ui32"
        // sp78 é um formato de ponto fixo (signed, 7 bits inteiros, 8 bits fracionários)

        let dataTypeStr = String(bytes: [
            UInt8(input.keyInfo.dataType >> 24 & 0xFF),
            UInt8(input.keyInfo.dataType >> 16 & 0xFF),
            UInt8(input.keyInfo.dataType >> 8 & 0xFF),
            UInt8(input.keyInfo.dataType & 0xFF)
        ], encoding: .ascii) ?? "----"

        if dataTypeStr == "sp78" && input.keyInfo.dataSize == 2 {
            // O valor está em input.bytes
            // sp78 é signed, 7 bits inteiros, 8 bits fracionários
            let value = (Int(input.bytes.0) * 256 + Int(input.bytes.1)) // Combina os dois bytes
            // Se o bit mais significativo (bit 15) for 1, o número é negativo
            if (value & 0x8000) != 0 { // Checa o bit de sinal
                 // Converte para complemento de dois se for negativo
                return Double(Int16(bitPattern: UInt16(value))) / 256.0
            } else {
                return Double(value) / 256.0
            }
        } else if dataTypeStr == "flt " && input.keyInfo.dataSize == 4 {
             // O valor é um float de 32 bits. A ordem dos bytes pode precisar ser ajustada (big-endian)
            var floatValue: Float32 = 0.0
            withUnsafeMutableBytes(of: &floatValue) { pointer in
                pointer.storeBytes(of: UInt32(bigEndian: Data(bytes: [input.bytes.0, input.bytes.1, input.bytes.2, input.bytes.3]).withUnsafeBytes { $0.load(as: UInt32.self) } ) , as: Float32.self)
            }
            return Double(floatValue)
        } else {
            print("Formato de dados não suportado para \(key): \(dataTypeStr), tamanho: \(input.keyInfo.dataSize). Bytes: \(input.bytes.0),\(input.bytes.1)")
            throw SMCError.unknownFormat("Chave: \(key), Formato: \(dataTypeStr), Tamanho: \(input.keyInfo.dataSize)")
        }
    }

    // Constantes para SMC (algumas podem não ser definidas publicamente)
    private let kSMCUserClientOpen: Int = 0 // Ou outro valor, dependendo da API do kernel
    private let kSMCUserClientClose: Int = 1
    private let kSMCReadKey: UInt8 = 5 // Usado como sub-comando em data8 para selector 2
    private let kSMCWriteKey: UInt8 = 6 // Usado como sub-comando em data8 para selector 2
    private let kSMCGetKeyCount: UInt8 = 7 // Usado como sub-comando em data8 para selector 2
    private let kSMCGetKeyFromIndex: UInt8 = 8 // Usado como sub-comando em data8 para selector 2
    private let kSMCGetKeyInfo: UInt8 = 9 // Usado como sub-comando em data8 para selector 2

    // Resultado da operação SMC
    private let KSMCSuccess: UInt8 = 0 // Sucesso
    private let KSMCSensorKeyNotFound: UInt8 = 0x84 // Chave não encontrada
    // Outros códigos de erro SMC existem, 0x80 a 0xff geralmente são erros.
}

// Função auxiliar para mostrar alerta de erro SMC e terminar
func showSMCErrorAndTerminate(message: String) {
    let alert = NSAlert()
    alert.messageText = "Erro Crítico do Monitor de Hardware" // Traduzido
    alert.informativeText = "\(message)\n\nO aplicativo será encerrado."
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.runModal()
    NSApplication.shared.terminate(nil)
}

extension FourCharCode {
    init(fromString str: String) {
        self = str.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }

    func toString() -> String {
        return String(describing: UnicodeScalar((self >> 24) & 0xff)!) +
               String(describing: UnicodeScalar((self >> 16) & 0xff)!) +
               String(describing: UnicodeScalar((self >> 8) & 0xff)!) +
               String(describing: UnicodeScalar(self & 0xff)!)
    }
}
