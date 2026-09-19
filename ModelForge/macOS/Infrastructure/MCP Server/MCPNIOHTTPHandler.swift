//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1

/// Thin NIO adapter that converts between NIO's HTTP types and the MCP SDK's framework-agnostic
/// `HTTPRequest`/`HTTPResponse`, delegating all protocol logic to ``MCPServerController``.
///
/// Declared `nonisolated` (the project defaults new declarations to `@MainActor` isolation) because
/// `ChannelInboundHandler` callbacks run on NIO's event-loop threads, not the main actor.
nonisolated final class MCPNIOHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let controller: MCPServerController

    private struct RequestState {
        var head: HTTPRequestHead
        var bodyBuffer: ByteBuffer
    }

    private var requestState: RequestState?

    init(controller: MCPServerController) {
        self.controller = controller
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestState = RequestState(head: head, bodyBuffer: context.channel.allocator.buffer(capacity: 0))
        case .body(var buffer):
            requestState?.bodyBuffer.writeBuffer(&buffer)
        case .end:
            guard let state = requestState else { return }
            requestState = nil
            nonisolated(unsafe) let ctx = context
            Task { await self.handleRequest(state: state, context: ctx) }
        }
    }

    // MARK: - Request processing

    private func handleRequest(state: RequestState, context: ChannelHandlerContext) async {
        let head = state.head
        let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
        let endpoint = await controller.endpoint

        guard path == endpoint else {
            await writeResponse(.error(statusCode: 404, .invalidRequest("Not Found")), version: head.version, context: context)
            return
        }

        let httpRequest = makeHTTPRequest(from: state)
        let response = await controller.handleHTTPRequest(httpRequest)
        await writeResponse(response, version: head.version, context: context)
    }

    // MARK: - NIO <-> HTTPRequest/HTTPResponse conversion

    private func makeHTTPRequest(from state: RequestState) -> HTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let body: Data?
        if state.bodyBuffer.readableBytes > 0,
           let bytes = state.bodyBuffer.getBytes(at: 0, length: state.bodyBuffer.readableBytes) {
            body = Data(bytes)
        } else {
            body = nil
        }

        let path = String(state.head.uri.split(separator: "?").first ?? Substring(state.head.uri))
        return HTTPRequest(method: state.head.method.rawValue, headers: headers, body: body, path: path)
    }

    private func writeResponse(_ response: HTTPResponse, version: HTTPVersion, context: ChannelHandlerContext) async {
        nonisolated(unsafe) let ctx = context
        let eventLoop = ctx.eventLoop
        let statusCode = response.statusCode
        let headers = response.headers

        switch response {
        case .stream(let stream, _):
            eventLoop.execute {
                var head = HTTPResponseHead(version: version, status: HTTPResponseStatus(statusCode: statusCode))
                for (name, value) in headers { head.headers.add(name: name, value: value) }
                ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)
                ctx.flush()
            }

            do {
                for try await chunk in stream {
                    eventLoop.execute {
                        var buffer = ctx.channel.allocator.buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        ctx.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    }
                }
            } catch {
                // Stream ended with an error — fall through and close the connection.
            }

            eventLoop.execute {
                ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }

        default:
            let bodyData = response.bodyData
            eventLoop.execute {
                var head = HTTPResponseHead(version: version, status: HTTPResponseStatus(statusCode: statusCode))
                for (name, value) in headers { head.headers.add(name: name, value: value) }
                ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)

                if let body = bodyData {
                    var buffer = ctx.channel.allocator.buffer(capacity: body.count)
                    buffer.writeBytes(body)
                    ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }

                ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}
