import Foundation
import CoreLocation

/// Tiered local cache for spatial data. Prevents redundant network calls when
/// the user revisits an area or moves within the same geohash cell.
///
/// Cache tiers:
/// - POIs by geohash (precision 6 ≈ 1.2km): TTL 7 days
/// - Wikipedia summaries by POI ID: TTL 30 days
/// - Weather by rounded coordinate: TTL 1 hour
/// - Reverse geocoding by rounded coordinate: TTL 7 days
final class SpatialCache {

    static let shared = SpatialCache()

    private let fileManager = FileManager.default
    private let cacheDir: URL
    private let queue = DispatchQueue(label: "com.raah.spatialcache", attributes: .concurrent)

    // TTLs in seconds
    private let poiTTL: TimeInterval = 4 * 3600             // 4 hours (restaurants change, keep fresh)
    private let wikiTTL: TimeInterval = 30 * 24 * 3600      // 30 days
    private let weatherTTL: TimeInterval = 3600              // 1 hour
    private let geocodeTTL: TimeInterval = 7 * 24 * 3600    // 7 days

    // Stats
    private(set) var hits: Int = 0
    private(set) var misses: Int = 0

    var hitRate: Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0
    }

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("SpatialCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - POI Cache (by geohash)

    func cachedPOIs(coordinate: CLLocationCoordinate2D) -> [POI]? {
        // v2: bumped when Google Places was added to pipeline — busts all old Overpass-only cache entries
        let key = "pois_v2_\(geohash(coordinate, precision: 6))"
        return load(key: key, type: [POI].self, ttl: poiTTL)
    }

    func cachePOIs(_ pois: [POI], coordinate: CLLocationCoordinate2D) {
        let key = "pois_v2_\(geohash(coordinate, precision: 6))"
        save(key: key, value: pois)
    }

    // MARK: - Wikipedia Cache (by POI ID)

    func cachedWikipediaSummary(poiID: String) -> String? {
        let key = "wiki_\(safeKey(poiID))"
        return load(key: key, type: String.self, ttl: wikiTTL)
    }

    func cacheWikipediaSummary(_ summary: String, poiID: String) {
        let key = "wiki_\(safeKey(poiID))"
        save(key: key, value: summary)
    }

    // MARK: - Weather Cache (by rounded coordinate)

    func cachedWeather(coordinate: CLLocationCoordinate2D) -> String? {
        let key = "weather_\(roundedCoordKey(coordinate))"
        return load(key: key, type: String.self, ttl: weatherTTL)
    }

    func cacheWeather(_ summary: String, coordinate: CLLocationCoordinate2D) {
        let key = "weather_\(roundedCoordKey(coordinate))"
        save(key: key, value: summary)
    }

    func cachedForecast(coordinate: CLLocationCoordinate2D) -> String? {
        let key = "forecast_\(roundedCoordKey(coordinate))"
        return load(key: key, type: String.self, ttl: weatherTTL)
    }

    func cacheForecast(_ forecast: String, coordinate: CLLocationCoordinate2D) {
        let key = "forecast_\(roundedCoordKey(coordinate))"
        save(key: key, value: forecast)
    }

    // MARK: - Geocode Cache (by rounded coordinate)

    struct GeocodeCacheEntry: Codable {
        let locationName: String?
        let countryCode: String?
    }

    func cachedGeocode(coordinate: CLLocationCoordinate2D) -> GeocodeCacheEntry? {
        let key = "geo_\(roundedCoordKey(coordinate))"
        return load(key: key, type: GeocodeCacheEntry.self, ttl: geocodeTTL)
    }

    func cacheGeocode(_ entry: GeocodeCacheEntry, coordinate: CLLocationCoordinate2D) {
        let key = "geo_\(roundedCoordKey(coordinate))"
        save(key: key, value: entry)
    }

    // MARK: - Cleanup

    func clearExpired() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let maxAge = max(poiTTL, max(wikiTTL, max(weatherTTL, geocodeTTL)))
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = attrs.contentModificationDate,
               modified < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        hits = 0
        misses = 0
    }

    // MARK: - Internal

    private struct CacheEntry<T: Codable>: Codable {
        let timestamp: Date
        let data: T
    }

    private func load<T: Codable>(key: String, type: T.Type, ttl: TimeInterval) -> T? {
        let url = cacheDir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry<T>.self, from: data) else {
            queue.async(flags: .barrier) { self.misses += 1 }
            return nil
        }
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            try? fileManager.removeItem(at: url)
            queue.async(flags: .barrier) { self.misses += 1 }
            return nil
        }
        queue.async(flags: .barrier) { self.hits += 1 }
        return entry.data
    }

    private func save<T: Codable>(key: String, value: T) {
        let entry = CacheEntry(timestamp: Date(), data: value)
        let url = cacheDir.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Geohash

    private func geohash(_ coordinate: CLLocationCoordinate2D, precision: Int) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var isEven = true
        var bit = 0
        var ch = 0

        while hash.count < precision {
            if isEven {
                let mid = (lonRange.0 + lonRange.1) / 2
                if coordinate.longitude >= mid {
                    ch |= (1 << (4 - bit))
                    lonRange.0 = mid
                } else {
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if coordinate.latitude >= mid {
                    ch |= (1 << (4 - bit))
                    latRange.0 = mid
                } else {
                    latRange.1 = mid
                }
            }
            isEven.toggle()
            bit += 1
            if bit == 5 {
                hash.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return hash
    }

    private func roundedCoordKey(_ coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lon = (coordinate.longitude * 100).rounded() / 100
        return "\(lat)_\(lon)"
    }

    private func safeKey(_ string: String) -> String {
        string.replacingOccurrences(of: "/", with: "_")
              .replacingOccurrences(of: ":", with: "_")
              .prefix(80)
              .description
    }
}
