import Foundation
import Network
import Darwin
internal import Combine

@MainActor
final class WebTeleprompterServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var urlString: String?
    @Published private(set) var statusMessage = "尚未啟動"

    private let port: NWEndpoint.Port = 8080
    private var listener: NWListener?
    private var currentState = LiveSyncState(lyric: "", style: TextSettings())

    func start(initialState: LiveSyncState) {
        currentState = initialState

        do {
            stop()
            let listener = try NWListener(using: .tcp, on: port)
            listener.service = NWListener.Service(name: "WorshipProjection", type: "_worship-web._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handle(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            statusMessage = "啟動失敗：\(error.localizedDescription)"
            isRunning = false
            urlString = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        urlString = nil
        statusMessage = "尚未啟動"
    }

    func publish(_ state: LiveSyncState) {
        currentState = state
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            let ip = Self.localIPAddress() ?? "本機 IP"
            urlString = "http://\(ip):\(port.rawValue)"
            statusMessage = "已啟動"
        case .failed(let error):
            isRunning = false
            urlString = nil
            statusMessage = "啟動失敗：\(error.localizedDescription)"
            listener?.cancel()
            listener = nil
        case .cancelled:
            isRunning = false
            urlString = nil
            statusMessage = "尚未啟動"
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] data, _, _, _ in
            Task { @MainActor in
                guard let self, let connection else { return }
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                self.respond(to: request, on: connection)
            }
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        let path = requestPath(from: request)
        let response: HTTPResponse

        switch path {
        case "/state":
            response = jsonResponse()
        default:
            response = htmlResponse()
        }

        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func requestPath(from request: String) -> String {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return "/" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1]).components(separatedBy: "?").first ?? "/"
    }

    private func jsonResponse() -> HTTPResponse {
        let state = WebLyricState(
            lyric: currentState.lyric,
            fontSize: Double(currentState.style.fontSize),
            lineSpacing: Double(currentState.style.lineSpacing),
            textColor: currentState.style.textColor.hexString
        )
        let data = (try? JSONEncoder().encode(state)) ?? Data()
        return HTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data)
    }

    private func htmlResponse() -> HTTPResponse {
        HTTPResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: Self.pageHTML.data(using: .utf8) ?? Data())
    }

    private static let pageHTML = """
    <!doctype html>
    <html lang="zh-Hant">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
      <title>WorshipProjection 提詞機</title>
      <style>
        html, body {
          width: 100%;
          height: 100%;
          margin: 0;
          background: #000;
          color: #fff;
          overflow: hidden;
          font-family: -apple-system, BlinkMacSystemFont, "PingFang TC", "Noto Sans TC", sans-serif;
        }
        body {
          display: flex;
          align-items: center;
          justify-content: center;
        }
        #lyric {
          box-sizing: border-box;
          width: 100vw;
          padding: 6vw;
          text-align: center;
          white-space: pre-wrap;
          font-weight: 800;
          text-shadow: 2px 2px 10px rgba(0,0,0,.85);
          line-height: 1.25;
        }
        #status {
          position: fixed;
          right: 14px;
          bottom: 12px;
          color: rgba(255,255,255,.35);
          font-size: 12px;
        }
      </style>
    </head>
    <body>
      <main id="lyric">等待主控端發送歌詞...</main>
      <div id="status">connecting</div>
      <script>
        const lyric = document.getElementById('lyric');
        const status = document.getElementById('status');
        let last = "";

        function fitText(fontSize) {
          const base = Math.max(24, Math.min(window.innerHeight * (fontSize / 1000), 120));
          lyric.style.fontSize = base + "px";
        }

        async function refresh() {
          try {
            const response = await fetch('/state', { cache: 'no-store' });
            const state = await response.json();
            const text = state.lyric && state.lyric.trim().length ? state.lyric : '等待主控端發送歌詞...';
            if (text !== last) {
              lyric.textContent = text;
              last = text;
            }
            lyric.style.color = state.textColor || '#FFFFFF';
            lyric.style.lineHeight = String(1.15 + Math.max(0, Number(state.lineSpacing || 0)) / 120);
            fitText(Number(state.fontSize || 80));
            status.textContent = 'live';
          } catch (error) {
            status.textContent = 'offline';
          }
        }

        window.addEventListener('resize', refresh);
        refresh();
        setInterval(refresh, 500);
      </script>
    </body>
    </html>
    """

    private static func localIPAddress() -> String? {
        var address: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            address = String(cString: hostname)
            break
        }

        return address
    }
}

private struct WebLyricState: Codable {
    var lyric: String
    var fontSize: Double
    var lineSpacing: Double
    var textColor: String
}

private struct HTTPResponse {
    var status: String
    var contentType: String
    var body: Data

    var data: Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var data = header.data(using: .utf8) ?? Data()
        data.append(body)
        return data
    }
}
