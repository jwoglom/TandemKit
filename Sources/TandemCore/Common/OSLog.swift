#if canImport(os)
    import os.log

    public extension OSLog {
        convenience init(category: String) {
            self.init(subsystem: "com.jwoglom.TandemKit", category: category)
        }

        func debug(_ message: StaticString, _ args: CVarArg...) {
            log(message, type: .debug, args)
        }

        func info(_ message: StaticString, _ args: CVarArg...) {
            log(message, type: .info, args)
        }

        func `default`(_ message: StaticString, _ args: CVarArg...) {
            log(message, type: .default, args)
        }

        func error(_ message: StaticString, _ args: CVarArg...) {
            log(message, type: .error, args)
        }

        func log(_ message: StaticString, type: OSLogType, _ args: [CVarArg]) {
            switch args.count {
            case 0:
                os_log(message, log: self, type: type)
            case 1:
                os_log(message, log: self, type: type, args[0])
            case 2:
                os_log(message, log: self, type: type, args[0], args[1])
            case 3:
                os_log(message, log: self, type: type, args[0], args[1], args[2])
            case 4:
                os_log(message, log: self, type: type, args[0], args[1], args[2], args[3])
            case 5:
                os_log(message, log: self, type: type, args[0], args[1], args[2], args[3], args[4])
            default:
                os_log(message, log: self, type: type, args)
            }
        }
    }
#else
    public struct OSLog {
        public init(subsystem _: String = "com.jwoglom.TandemKit", category _: String) {}
        public init(category: String) { self.init(subsystem: "com.jwoglom.TandemKit", category: category) }
        public func debug(_: StaticString, _: CVarArg...) {}
        public func info(_: StaticString, _: CVarArg...) {}
        public func `default`(_: StaticString, _: CVarArg...) {}
        public func error(_: StaticString, _: CVarArg...) {}
    }
#endif
