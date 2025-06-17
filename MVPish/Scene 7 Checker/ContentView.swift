import Foundation
import CryptoKit

// MARK: - Configuration

let placeholderHash = "115485ffcdb7a6419a5751a6045b482f"

// MARK: - Scene7 URL Generator

/// Generates a Scene7 URL for a given item image name (e.g., "J443781.001")
func scene7URL(for imageName: String) -> URL? {
    let name = imageName.lowercased()
    let components = name.split(separator: ".")
    guard let itemPart = components.first, itemPart.count >= 3 else { return nil }
    let itemNumber = String(itemPart)
    guard let firstLetter = itemNumber.first else { return nil }
    let lastTwo = itemNumber.suffix(2)
    let urlString = "https://qvc.scene7.com/is/image/QVC/\(firstLetter)/\(lastTwo)/\(name)"
    return URL(string: urlString)
}

// MARK: - CSV Reading

/// Loads image names from a CSV file (expects one image name per line)
func loadImageNames(from csvURL: URL) throws -> [String] {
    let content = try String(contentsOf: csvURL)
    return content
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

// MARK: - Image Hashing

/// Downloads a URL and returns its MD5 hash as a hex string
func fetchImageHash(url: URL, completion: @escaping (String?) -> Void) {
    let task = URLSession.shared.dataTask(with: url) { data, _, error in
        guard let data = data, error == nil else { completion(nil); return }
        let hash = Insecure.MD5.hash(data: data)
        let hashString = hash.map { String(format: "%02hhx", $0) }.joined()
        completion(hashString)
    }
    task.resume()
}

// MARK: - Bulk Checker

/// For each image name, checks if a real image exists at Scene7 (not placeholder)
func checkImages(csvFile: URL, completion: @escaping ([Result]) -> Void) {
    let imageNames: [String]
    do {
        imageNames = try loadImageNames(from: csvFile)
    } catch {
        print("Failed to load CSV: \(error)")
        completion([])
        return
    }
    let group = DispatchGroup()
    var results: [Result] = Array(repeating: Result(imageName: "", url: nil, isRealImage: false, error: "Not checked"), count: imageNames.count)
    
    for (index, name) in imageNames.enumerated() {
        guard let url = scene7URL(for: name) else {
            results[index] = Result(imageName: name, url: nil, isRealImage: false, error: "Invalid name format")
            continue
        }
        results[index] = Result(imageName: name, url: url, isRealImage: false, error: nil)
        group.enter()
        fetchImageHash(url: url) { hash in
            if let hash = hash {
                results[index].isRealImage = (hash != placeholderHash)
                results[index].error = nil
            } else {
                results[index].error = "Fetch/Network error"
            }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        completion(results)
    }
}

// MARK: - Result Structure

struct Result {
    let imageName: String
    let url: URL?
    var isRealImage: Bool
    var error: String?
}

// MARK: - Main Command-Line Entry

/// Usage: Scene7ImageChecker <csv file path>
func main() {
    guard CommandLine.arguments.count > 1 else {
        print("Usage: Scene7ImageChecker <csv file path>")
        return
    }
    let csvPath = CommandLine.arguments[1]
    let csvURL = URL(fileURLWithPath: csvPath)
    print("Loading CSV and checking Scene7 images...")

    let semaphore = DispatchSemaphore(value: 0)
    checkImages(csvFile: csvURL) { results in
        print("image_name,scene7_url,is_real_image,error")
        for res in results {
            let urlStr = res.url?.absoluteString ?? ""
            let real = res.isRealImage ? "yes" : "no"
            let error = res.error ?? ""
            print("\(res.imageName),\(urlStr),\(real),\(error)")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

// Only run main() if compiled as a command-line tool
#if !DEBUG
main()
#endif
