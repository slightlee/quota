import Foundation

/// HTTP client for Xiaomi's Token Plan console usage and detail endpoints.
final class MiMoUsageClient {
    struct FetchResult {
        var response: MiMoUsageResponse
        var detail: MiMoPlanDetail?
        var account: MiMoCodeAccount
        var timeZone: TimeZone
    }

    private let endpoint: URL
    private let detailEndpoint: URL
    private let session: URLSession
    private let authStore: MiMoAuthStore
    private let decoder = JSONDecoder()

    init(
        endpoint: URL = URL(
            string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage"
        )!,
        detailEndpoint: URL = URL(
            string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/detail"
        )!,
        session: URLSession,
        authStore: MiMoAuthStore = .shared
    ) {
        self.endpoint = endpoint
        self.detailEndpoint = detailEndpoint
        self.session = session
        self.authStore = authStore
    }

    convenience init(
        proxyConfiguration: ProxyConfiguration,
        authStore: MiMoAuthStore = .shared
    ) {
        self.init(
            session: ProxiedURLSession.make(configuration: proxyConfiguration),
            authStore: authStore
        )
    }

    func fetchUsage(completion: @escaping (Result<FetchResult, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loadCredentialsAndRequest(completion: completion)
        }
    }

    private func loadCredentialsAndRequest(
        completion: @escaping (Result<FetchResult, Error>) -> Void
    ) {
        let account: MiMoCodeAccount
        let cookie: String
        do {
            account = try authStore.loadMiMoCodeAccount()
            cookie = try authStore.loadSessionCookie()
        } catch {
            completion(.failure(error))
            return
        }

        let timeZone = TimeZone.current
        let usageRequest = makeRequest(
            url: endpoint,
            cookie: cookie,
            timeZone: timeZone
        )

        session.dataTask(with: usageRequest) { [weak self, decoder] data, response, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }

            do {
                let data = try Self.validatedData(data, response: response)
                let payload = try decoder.decode(MiMoUsageResponse.self, from: data)
                self.fetchDetail(
                    cookie: cookie,
                    timeZone: timeZone
                ) { detail in
                    completion(.success(FetchResult(
                        response: payload,
                        detail: detail,
                        account: account,
                        timeZone: timeZone
                    )))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// Detail is supplementary: a temporary detail failure must not hide valid
    /// quota percentages. It only removes the reset time for that refresh.
    private func fetchDetail(
        cookie: String,
        timeZone: TimeZone,
        completion: @escaping (MiMoPlanDetail?) -> Void
    ) {
        let request = makeRequest(
            url: detailEndpoint,
            cookie: cookie,
            timeZone: timeZone
        )
        session.dataTask(with: request) { [decoder] data, response, error in
            guard error == nil,
                  let data = try? Self.validatedData(data, response: response),
                  let payload = try? decoder.decode(MiMoPlanDetailResponse.self, from: data),
                  payload.code == 0 else {
                completion(nil)
                return
            }
            completion(payload.data)
        }.resume()
    }

    private func makeRequest(
        url: URL,
        cookie: String,
        timeZone: TimeZone
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Quota/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(
            "https://platform.xiaomimimo.com/console/plan-manage",
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            "https://platform.xiaomimimo.com",
            forHTTPHeaderField: "Origin"
        )
        request.setValue(timeZone.identifier, forHTTPHeaderField: "x-timezone")
        return request
    }

    private static func validatedData(
        _ data: Data?,
        response: URLResponse?
    ) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiMoQuotaError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            guard let data else { throw MiMoQuotaError.invalidResponse }
            return data
        case 401, 403:
            throw MiMoQuotaError.unauthorized
        default:
            throw MiMoQuotaError.requestFailed(httpResponse.statusCode)
        }
    }
}
