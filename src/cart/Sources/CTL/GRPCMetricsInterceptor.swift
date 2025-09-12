import Dispatch
import GRPCCore
import Metrics

struct GRPCMetricsInterceptor: ServerInterceptor {
    let serverHostname: String
    let networkTransportMethod: String

    func intercept<Input: Sendable, Output: Sendable>(
        request: GRPCCore.StreamingServerRequest<Input>,
        context: GRPCCore.ServerContext,
        next: @Sendable (
            GRPCCore.StreamingServerRequest<Input>,
            GRPCCore.ServerContext
        ) async throws -> GRPCCore.StreamingServerResponse<Output>
    ) async throws -> GRPCCore.StreamingServerResponse<Output> {
        let startTime = DispatchTime.now().uptimeNanoseconds
        var dimensions = [
            ("rpc.system", "grpc"),
            ("rpc.method", context.descriptor.method),
            ("rpc.service", context.descriptor.service.fullyQualifiedService),
            ("server.address", serverHostname),
            ("network.transport", networkTransportMethod),
            ("unit", "ms")
        ]

        do {
            let response = try await next(request, context)
            let statusCode: Int
            switch response.accepted {
            case .success:
                statusCode = 0
            case .failure(let error):
                statusCode = error.code.rawValue
            }
            dimensions.append(("rpc.grpc.status_code", "\(statusCode)"))

            Timer(
                label: "rpc.server.duration",
                dimensions: dimensions,
                preferredDisplayUnit: .milliseconds
            )
            .recordNanoseconds(DispatchTime.now().uptimeNanoseconds - startTime)

            return response
        } catch let error as Error & RPCErrorConvertible {
            dimensions.append(("rpc.grpc.status_code", "\(error.rpcErrorCode.rawValue)"))
            Timer(
                label: "rpc.server.duration",
                dimensions: dimensions,
                preferredDisplayUnit: .milliseconds
            )
            .recordNanoseconds(DispatchTime.now().uptimeNanoseconds - startTime)
            throw error
        } catch {
            dimensions.append(("rpc.grpc.status_code", "\(RPCError.Code.unknown.rawValue)"))
            Timer(
                label: "rpc.server.duration",
                dimensions: dimensions,
                preferredDisplayUnit: .milliseconds
            )
            .recordNanoseconds(DispatchTime.now().uptimeNanoseconds - startTime)
            throw error
        }
    }
}
