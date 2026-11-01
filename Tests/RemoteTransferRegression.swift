import AppKit
import Network
import Security

@main enum RemoteTransferRegression {
    @MainActor static func main() throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let tls=try RemoteTLS.prepare(in:directory.appendingPathComponent("TLS"))
        let options=NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(options.securityProtocolOptions,sec_identity_create(tls.identity)!)
        let params=NWParameters(tls:options,tcp:NWProtocolTCP.Options())
        params.requiredLocalEndpoint = .hostPort(host:.ipv4(.loopback),port:.any)
        let listener=try NWListener(using:params)
        let data=Data(String(repeating:"A koala packed this entire response.\n",count:40000).utf8)
        try data.write(to:directory.appendingPathComponent("expected.bin"))
        var connections:[UUID:RemoteHTTPConnection]=[:]
        listener.newConnectionHandler={ connection in
            Task { @MainActor in
                let c=RemoteHTTPConnection(connection);connections[c.id]=c
                c.onRequest={_ in RemoteHTTPResponse(body:data,type:"application/octet-stream")}
                c.onClose={ [weak c] in if let c=c { connections.removeValue(forKey:c.id) } }
                c.start()
            }
        }
        listener.stateUpdateHandler={state in
            if case .ready=state {
                let object:[String:Any]=["port":Int(listener.port!.rawValue),"ca":directory.appendingPathComponent("TLS/ca.pem").path]
                try! JSONSerialization.data(withJSONObject:object).write(to:directory.appendingPathComponent("ready.json"),options:.atomic)
            }
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        listener.start(queue:.main)
        NSApplication.shared.run()
        _=connections
    }
}
