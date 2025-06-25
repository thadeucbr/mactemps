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
        case keyNotFound(String) // Usado quando a chave não é encontrada pelo SMC (e.g., result 0x84)
        case readFailed(String, kern_return_t) // Usado para falhas na chamada IOKit ou erros SMC não específicos de 'não encontrado'
        case unknownFormat(String)
        // Poderíamos adicionar um caso mais específico para erros SMC que não são 'keyNotFound'
        // case smcOperationError(key: String, smcResult: UInt8)
    }

    init() throws {
        var iterator: io_iterator_t = 0
        var result: kern_return_t

        // Encontrar o serviço AppleSMC
        let matchingDictionary = IOServiceMatching("AppleSMC")
        result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)

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
            result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingAlt, &iterator)
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
        var vers: SMCVersion = SMCVersion()         // Não usado para leitura simples de temperatura
        var pLimitData: SMCPLimitData = SMCPLimitData()// Não usado
        var keyInfo: SMCKeyInfoData = SMCKeyInfoData()  // Informações sobre a chave (tipo, tamanho)
        var padding: UInt16 = 0         // Preenchimento
        var result: UInt8 = 0           // Resultado da operação
        var status: UInt8 = 0           // Status da operação
        var data8: UInt8 = 0            // Dado (se for 1 byte)
        var data32: UInt32 = 0          // Dado (se for 4 bytes)
        var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) // Buffer para dados (até 32 bytes)

        // Inicializador explícito para fornecer valores padrão
        init(key: UInt32 = 0,
             vers: SMCVersion = SMCVersion(),
             pLimitData: SMCPLimitData = SMCPLimitData(),
             keyInfo: SMCKeyInfoData = SMCKeyInfoData(),
             padding: UInt16 = 0,
             result: UInt8 = 0,
             status: UInt8 = 0,
             data8: UInt8 = 0,
             data32: UInt32 = 0,
             bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) {
            self.key = key
            self.vers = vers
            self.pLimitData = pLimitData
            self.keyInfo = keyInfo
            self.padding = padding
            self.result = result
            self.status = status
            self.data8 = data8
            self.data32 = data32
            self.bytes = bytes
        }
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

        // kernResult é o nome mais comum para o resultado de chamadas IOKit.
        let kernResult = IOConnectCallStructMethod(connection,
                                               UInt32(selector), // Selector para a chamada SMC
                                               &inputStruct,     // Ponteiro para a estrutura de entrada
                                               inputSize,        // Tamanho da estrutura de entrada
                                               &outputStruct,    // Ponteiro para a estrutura de saída
                                               &outputSize)      // Tamanho da estrutura de saída

        // Log detalhado em callSMC
        let keyStr = inputStruct.key.toString()
        print("callSMC for key '\(keyStr)' (selector \(selector), input.data8: \(inputStruct.data8)):")
        print("  IOConnectCallStructMethod kern_result: \(kernResult)")

        if kernResult == kIOReturnSuccess {
            // Esses logs só fazem sentido se a chamada IOConnect foi bem-sucedida
            print("  outputStruct.result (SMC op result): \(outputStruct.result)")
            let typeAsUInt32 = outputStruct.keyInfo.dataType
        let typeStr = String(bytes: [
            UInt8(truncatingIfNeeded: typeAsUInt32 >> 24),
            UInt8(truncatingIfNeeded: typeAsUInt32 >> 16),
            UInt8(truncatingIfNeeded: typeAsUInt32 >> 8),
            UInt8(truncatingIfNeeded: typeAsUInt32)
        ], encoding: .ascii) ?? "N/A"
        print("  outputStruct.keyInfo: dataSize=\(outputStruct.keyInfo.dataSize), dataType=\(typeStr) (\(typeAsUInt32)), dataAttributes=\(outputStruct.keyInfo.dataAttributes)")
        // Log dos primeiros bytes de outputStruct.bytes para depuração, se necessário
        // print("  outputStruct.bytes (first 4): \(outputStruct.bytes.0), \(outputStruct.bytes.1), \(outputStruct.bytes.2), \(outputStruct.bytes.3)")
        } else {
            print("  IOConnectCallStructMethod failed (kern_result: \(kernResult)), no further outputStruct logs.")
        }

        if kernResult == kIOReturnSuccess {
            inputStruct.result = outputStruct.result // Copia o resultado da operação SMC
            inputStruct.keyInfo = outputStruct.keyInfo
            inputStruct.bytes = outputStruct.bytes
        }
        return kernResult // Retornar o kernResult da chamada IOConnectCallStructMethod
    }

    private func getSensorInfo(key: String) throws -> SMCKeyInfoData {
        var input = SMCParamStruct()
        input.key = FourCharCode(fromString: key)
        input.data8 = UInt8(kSMCGetKeyInfo) // kSMCGetKeyInfo (9)

        print("getSensorInfo for key '\(key)': Attempting callSMC (selector 2, data8: \(input.data8))")
        let kernResult = callSMC(inputStruct: &input, selector: 2)

        // Log após callSMC em getSensorInfo
        print("getSensorInfo for key '\(key)' (after callSMC):")
        print("  kern_result from callSMC: \(kernResult)")

        if kernResult == kIOReturnSuccess {
            // Somente logar input.result e input.keyInfo se kernResult da chamada IOKit foi sucesso.
            let typeAsUInt32_input = input.keyInfo.dataType
            let typeStr_input = String(bytes: [
                UInt8(truncatingIfNeeded: typeAsUInt32_input >> 24),
                UInt8(truncatingIfNeeded: typeAsUInt32_input >> 16),
                UInt8(truncatingIfNeeded: typeAsUInt32_input >> 8),
                UInt8(truncatingIfNeeded: typeAsUInt32_input)
            ], encoding: .ascii) ?? "N/A"
            print("  input.result (SMC op result): \(input.result)")
            print("  input.keyInfo: dataSize=\(input.keyInfo.dataSize), dataType=\(typeStr_input) (\(typeAsUInt32_input)), dataAttributes=\(input.keyInfo.dataAttributes)")
        }

        if kernResult != kIOReturnSuccess {
            // Este erro é sobre a falha da chamada IOConnectCallStructMethod em si
            throw SMCError.readFailed("getSensorInfo (IOConnectCallStructMethod failed for key \(key))", kernResult)
        }

        // Se a chamada IOKit (kernResult) foi sucesso, agora verificamos o resultado da operação SMC (input.result)
        if input.result == KSMCSensorKeyNotFound {
             print("SMC reported Key '\(key)' not found (SMC result: \(input.result)).")
             throw SMCError.keyNotFound("Sensor key '\(key)' not found by SMC (SMC result code: \(input.result)).")
        }
        if input.result != KSMCSuccess { // Outro erro da operação SMC
             print("SMC reported an error for key '\(key)' (SMC result: \(input.result))")
             // Usar um kern_return_t genérico como kIOReturnInternalError para o segundo parâmetro de readFailed,
             // já que input.result (UInt8) não é um kern_return_t. A mensagem de erro contém o código SMC real.
             throw SMCError.readFailed("SMC operation failed for key '\(key)' (SMC result code: \(input.result))", kIOReturnInternalError)
        }
        // Se kernResult == kIOReturnSuccess E input.result == KSMCSuccess (0), então a keyInfo deve ser válida.
        return input.keyInfo
    }

    func readTemperature(key: String) throws -> Double {
        guard connection != 0 else {
            print("Erro: Tentativa de ler temperatura sem conexão SMC válida.")
            throw SMCError.connectionFailed
        }

        // 1. Obter informações (tipo, tamanho) da chave SMC
        let fetchedKeyInfo: SMCKeyInfoData
        do {
            fetchedKeyInfo = try getSensorInfo(key: key)
            // Se getSensorInfo foi bem-sucedido, fetchedKeyInfo contém o dataType e dataSize corretos.
        } catch {
            print("readTemperature: Falha ao obter informações para a chave '\(key)' via getSensorInfo. Erro: \(error)")
            throw error // Re-lança o erro de getSensorInfo (pode ser keyNotFound, readFailed, etc.)
        }

        // 2. Preparar a estrutura SMCParamStruct para a operação de LEITURA (kSMCReadKey)
        var readInput = SMCParamStruct() // Nova struct para a operação de leitura
        readInput.key = FourCharCode(fromString: key)
        readInput.keyInfo.dataSize = fetchedKeyInfo.dataSize // Usar o dataSize obtido!
        readInput.keyInfo.dataType = fetchedKeyInfo.dataType // Usar o dataType obtido!
        readInput.data8 = UInt8(kSMCReadKey) // Especifica a operação de leitura para o selector 2

        let fetchedDataTypeStr = fetchedKeyInfo.dataType.toString() // Para logging
        print("readTemperature for key '\(key)': Attempting callSMC (selector 2, data8: kSMCReadKey=\(kSMCReadKey)) with keyInfo: size=\(readInput.keyInfo.dataSize), type=\(fetchedDataTypeStr)")

        // 3. Chamar SMC para LER os bytes da chave
        let kernResultRead = callSMC(inputStruct: &readInput, selector: 2)

        // 4. Verificar resultados da chamada IOKit e da operação SMC de leitura
        if kernResultRead != kIOReturnSuccess {
            print("Erro na chamada IOConnectCallStructMethod ao ler chave SMC '\(key)'. Código IOKit: \(kernResultRead)")
            throw SMCError.readFailed("Read operation (IOConnectCallStructMethod for key '\(key)')", kernResultRead)
        }

        if readInput.result == KSMCSensorKeyNotFound {
             print("SMC reported Key '\(key)' not found during read operation (SMC result: \(readInput.result)).")
             throw SMCError.keyNotFound("Sensor key '\(key)' not found by SMC during read (SMC result code: \(readInput.result)).")
        }
        if readInput.result != KSMCSuccess { // Outro erro SMC
            print("Erro específico do SMC ao ler a chave '\(key)'. Resultado SMC: \(readInput.result)")
            throw SMCError.readFailed("SMC read operation failed for key '\(key)' (SMC result code: \(readInput.result))", kIOReturnInternalError)
        }

        // 5. Interpretar os bytes lidos (readInput.bytes) usando fetchedKeyInfo
        // Usar fetchedKeyInfo para dataTypeStr e dataSize, pois são os valores autoritativos.
        let dataTypeStr = fetchedKeyInfo.dataType.toString() // Reutiliza a string do tipo de dado
        let dataSize = fetchedKeyInfo.dataSize

        print("Interpreting key '\(key)': dataType='\(dataTypeStr)', dataSize=\(dataSize). Bytes from SMC: \(readInput.bytes.0),\(readInput.bytes.1),\(readInput.bytes.2),\(readInput.bytes.3)...")

        if dataTypeStr == "sp78" && dataSize == 2 {
            // sp78: signed, 7 bits inteiros, 8 bits fracionários. Big-endian.
            // Byte 0 é o mais significativo.
            let value = (Int16(readInput.bytes.0) << 8) | Int16(readInput.bytes.1) // Combina os dois bytes em Int16
            return Double(value) / 256.0
        } else if dataTypeStr == "flt " && dataSize == 4 {
            // flt: float de 32 bits. Big-endian.
            let b0 = UInt32(readInput.bytes.0)
            let b1 = UInt32(readInput.bytes.1)
            let b2 = UInt32(readInput.bytes.2)
            let b3 = UInt32(readInput.bytes.3)
            let uint32Value = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            let floatValue = Float32(bitPattern: uint32Value)
            return Double(floatValue)
        } else {
            // Se dataTypeStr for algo como "\0\0\0\0" ou dataSize for 0, cairá aqui.
            print("Formato de dados não suportado ou inválido para '\(key)': dataType='\(dataTypeStr)', dataSize=\(dataSize). Bytes: \(readInput.bytes.0),\(readInput.bytes.1)")
            throw SMCError.unknownFormat("Chave: \(key), Formato: \(dataTypeStr), Tamanho: \(dataSize)")
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
