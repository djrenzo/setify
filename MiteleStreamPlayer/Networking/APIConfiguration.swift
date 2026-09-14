import Foundation

enum DefaultCredentials {
    static let gmid = "gmid=gmid.ver4.AtLt8k4V6A.5Kt9Om8B8H72kqDYUwevTpcTcJudgWf9fCgojlCzzyrZM3ZxAh0Y8sg9bqCiUd3y.emqVgH6O1rV0Dhm17cYTbv2SFGVAufHLUH-GkERwUoVPtOHNK0W4gqQZCQNlqQN1JcUSfI9sW8W6JhqaeDRqhQ.sc3; ucid=3nIeQuA68LNQBQ0oP292xw; hasGmid=ver4"
    static let cookie = "include=profile%2Cdata&extraProfileFields=username&lang=es&APIKey=3_-Io69iQoOPkTetSCpOyyuCH7KLUHfBQXFl3DADd-tYAPdlcT47Mp43nFJGr5kHpt&sdk=js_latest&login_token=st2.s.AtLt04QX0A.MnQUaDY5RnYAVBD8V-j0gkYkLtfIlIkAxLZQfA8M4n0YwttbZZbUROByniQft0nRGJdKCmu9WuzGc1qNuepEhRpRoEkB-Ru11xYuFdAYcvTsSGD_Xfo1yjcyf_2PC9ad.PyDgh-xXsdUeS5JwgkjXvC-eC7lKl0AAhOOgRYR-slg3UEcVXOH9Zow9rw08ep99R4UZVKAjXIPj6_CgLxiNkw.sc3&authMode=cookie&pageURL=https%3A%2F%2Fwww.mitele.es%2Fprogramas-tv%2Fmadres-desde-el-corazon%2Ftemporada-1%2Fepisodios%2Fprograma-3-40_015018833%2Fplayer%2F&sdkBuild=17112&format=json"
}

enum APIConfiguration {
    static let chromeUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
    static let firefoxUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0"

    static let graphQLHeaders = [
        "User-Agent": firefoxUserAgent,
        "x-m-platform": "WEB",
        "x-m-property": "MITELE",
        "x-m-app-version": "1.0.20",
        "Accept": "application/json"
    ]

    static let deliveryHeaders = [
        "User-Agent": chromeUserAgent,
        "Referer": "https://www.mediaset.es/",
        "Origin": "https://www.mediaset.es",
        "Accept": "application/json"
    ]

    static let cerberoHeaders = [
        "Accept-Encoding": "gzip",
        "Accept": "application/json, text/plain, */*",
        "Origin": "app.mitele.android.es",
        "User-Agent": "MOBILE/6.13.2(2108)",
        "Content-Type": "application/json;charset=UTF-8"
    ]

    static let mediasetPlaybackHeaders = [
        "User-Agent": chromeUserAgent,
        "Referer": "https://www.mediasetinfinity.es/"
    ]

    static let rtvePlaybackHeaders = [
        "User-Agent": firefoxUserAgent,
        "Referer": "https://www.rtve.es/",
        "Origin": "https://www.rtve.es"
    ]

    static func sessionHeaders(gmid: String) -> [String: String] {
        [
            "Cookie": gmid,
            "User-Agent": chromeUserAgent,
            "Accept": "application/json"
        ]
    }

    // Unauthenticated legacy bitban scrape (editorial index / tabs) — no session cookie sent.
    static let scrapeHeaders = [
        "User-Agent": firefoxUserAgent,
        "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
        "Accept-Language": "es-ES,es;q=0.9"
    ]
}

enum APIURL {
    static let graphQL = URL(string: "https://ottesp.api-graph.mediaset.it/")!
    static let gigyaAccount = URL(string: "https://login.mitele.es/accounts.getAccountInfo")!
    static let mab = URL(string: "https://mab.mediaset.es/1.0.0/get")!
    static let cerbero = URL(string: "https://cerbero.mediaset.es/")!

    static func mabURL(oid: String, eid: String) throws -> URL {
        guard var components = URLComponents(url: mab, resolvingAgainstBaseURL: false) else {
            throw PlaybackFailure.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "oid", value: oid),
            URLQueryItem(name: "eid", value: eid)
        ]
        guard let url = components.url else { throw PlaybackFailure.invalidURL }
        return url
    }
}
